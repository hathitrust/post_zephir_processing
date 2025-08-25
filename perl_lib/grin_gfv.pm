package grin_gfv;

use strict;
use warnings;
use utf8;

use POSIX qw(strftime);

# Day Mo NN XX:YY:ZZ Year
our $REPORT_TIME_FORMAT = "%a %b %e %T %Y";

my $UPDATE_USER   = 'libadm';
# For rights_current update ($write_update_to_gfv_sql)
our $GFV_ATTR_ID   = 9;  # pdus
our $GFV_REASON_ID = 12; # gfv
# For rights_current reversion update
my $REVERSION_NOTE = 'Revert to previous attr/reason; no longer VIEW_FULL';


# This gets us the items to update in update_gfv.
my $select_updates_to_gfv_sql = <<~'SQL';
  SELECT r.namespace, r.id, a.name
  FROM rights_current     r
  INNER JOIN attributes   a ON r.attr   = a.id
  INNER JOIN reasons      e ON r.reason = e.id
  INNER JOIN ht.feed_grin g ON r.id     = g.id AND r.namespace = g.namespace
  WHERE g.viewability = 'VIEW_FULL' AND a.name IN ('ic', 'und') AND e.name = 'bib' AND g.claimed != 'true' AND r.namespace != 'keio'
  ORDER BY r.namespace, r.id
SQL

my $select_reversions_from_gfv_sql = <<~'SQL';
  SELECT r.namespace, r.id
  FROM rights_current r
  INNER JOIN ht.feed_grin g ON r.id = g.id AND r.namespace = g.namespace
  WHERE r.reason='12' AND (g.viewability != 'VIEW_FULL' OR g.claimed = 'true' OR r.namespace = 'keio')
  ORDER BY r.namespace, r.id
SQL

my $select_rights_log_sql = <<~'SQL';
  SELECT attr, reason, source
  FROM rights_log
  WHERE namespace = ? AND id = ?
  ORDER BY time DESC
SQL

my $write_update_to_gfv_sql = <<~SQL;
  UPDATE rights_current
  SET
    attr   = $GFV_ATTR_ID,
    reason = $GFV_REASON_ID,
    time   = CURRENT_TIMESTAMP,
    user   = '$UPDATE_USER'
  WHERE namespace = ? AND id = ?
SQL

my $write_reversion_from_gfv_sql = <<~SQL;
  UPDATE rights_current
  SET
    attr   = ?,
    reason = ?,
    time   = CURRENT_TIMESTAMP,
    user   = '$UPDATE_USER',
    note   = '$REVERSION_NOTE'
  WHERE namespace = ? AND id = ?
SQL

sub new {
  my ($class, %args) = @_;
  my $self = bless {}, $class;
  my $dbh = Database::get_rights_rw_dbh;
  $self->{dbh} = $dbh;
  $self->{select_updates_to_gfv_sth} = $dbh->prepare($select_updates_to_gfv_sql) || die "could not prepare query: $select_updates_to_gfv_sql";;
  $self->{select_reversions_from_gfv_sth} = $dbh->prepare($select_reversions_from_gfv_sql) || die "could not prepare query: $select_reversions_from_gfv_sql";
  $self->{select_rights_log_sth} = $dbh->prepare($select_rights_log_sql) || die "could not prepare query: $select_rights_log_sql";
  $self->{write_update_to_gfv_sth} = $dbh->prepare($write_update_to_gfv_sql) || die "could not prepare query: $write_update_to_gfv_sql";
  $self->{write_reversion_from_gfv_sth} = $dbh->prepare($write_reversion_from_gfv_sql) || die "could not prepare query: $write_reversion_from_gfv_sql";
  return $self;
}

# ic/und items that should nonetheless be pdus/gfv according to GRIN
# Returns an arrayref of hashref, sorted by namespace and id
# Each hashref contains the fields {namespace, id, attr}
# e.g. { namespace => 'mdp', id => '001', attr => 'ic' }
sub updates_to_gfv {
  my $self = shift;

  my $updates = [];
  my $sth = $self->{select_updates_to_gfv_sth};
  $sth->execute or die $sth->errstr;
  while (my $row = $sth->fetch) {
    my ($namespace, $id, $attr) = @$row;
    push @$updates, {namespace => $namespace, id => $id, attr => $attr};
  }
  $sth->finish;
  return $updates;
}

# Extract updates_to_gfv data into e-mail report
# Optional date_string keyword arg is for testing
sub updates_to_gfv_report {
  my $self    = shift;
  my $updates = shift;
  my %args    = @_;

  my $date_string = $args{date_string} || strftime($REPORT_TIME_FORMAT, localtime);
  my $report = sprintf "%d volumes set to pdus/gfv at $date_string\n\n", scalar @$updates;
  my $ic_section = "IC\n\n";
  my $und_section = "UND\n\n";
  foreach my $update (@$updates) {
    if ($update->{attr} eq 'ic') {
      $ic_section .= "$update->{namespace}.$update->{id}\n";
    } elsif ($update->{attr} eq 'und') {
      $und_section .= "$update->{namespace}.$update->{id}\n";
    } else {
      printf STDERR "ERROR: unknown attribute in %s\n", Dumper($update);
    }
  }
  $report .= $ic_section . "\n";
  $report .= $und_section;
  return $report;
}

# Write a pdus/gfv update (one of the hashrefs from updates_to_gfv) to the Rights DB
sub write_update_to_gfv {
  my $self   = shift;
  my $update = shift;

  $self->{write_update_to_gfv_sth}->execute(
    $update->{namespace},
    $update->{id}
  );
}

# pdus_gfv items that should be reverted to bib rights
# Returns an arrayref of hashref, sorted by namespace, id
# Each hashref contains the fields {namespace, id, attr, reason, source, gfv_count}
# e.g. { namespace => 'mdp', id => '001', attr => 5, reason => 8, source => 1, gfv_count => 0 }
# NOTE, the attr/reason/src are NUMERIC this time
sub reversions_from_gfv {
  my $self = shift;

  my $updates = [];
  my $sth = $self->{select_reversions_from_gfv_sth};
  $sth->execute or die $sth->errstr;
  while (my $row = $sth->fetch) {
    my ($namespace, $id) = @$row;
    my $rights_log_data = $self->_rights_log_data($namespace, $id);
    push @$updates, {
      namespace => $namespace,
      id => $id,
      attr => $rights_log_data->{attr},
      reason => $rights_log_data->{reason},
      source => $rights_log_data->{source},
      gfv_count => $rights_log_data->{gfv_count}
    };
  }
  $sth->finish;
  return $updates;
}

# Extract reversions_from_gfv data into e-mail report
# Optional date_string keyword arg is for testing
sub reversions_from_gfv_report {
  my $self       = shift;
  my $reversions = shift;
  my %args       = @_;

  my $date_string = $args{date_string} || strftime($REPORT_TIME_FORMAT, localtime);
  my $report = sprintf "%d volumes reverted from pdus/gfv at $date_string\n\n", scalar @$reversions;
  my $prior_section = "Has prior GFV status\n\n";
  my $no_prior_section = "No prior GFV status\n\n";
  foreach my $reversion (@$reversions) {
    # There should be at least one GFV (the one we are reverting from).
    # Anything more than that counts as prior GFV status.
    if ($reversion->{gfv_count} > 1) {
      $prior_section .= "$reversion->{namespace}.$reversion->{id}\n";
    } else {
      $no_prior_section .= "$reversion->{namespace}.$reversion->{id}\n";
    }
  }
  $report .= $prior_section . "\n";
  $report .= $no_prior_section;
  return $report;
}

sub write_reversion_from_gfv {
  my $self      = shift;
  my $reversion = shift;

  $self->{write_reversion_from_gfv_sth}->execute(
    $reversion->{attr},
    $reversion->{reason},
    $reversion->{namespace},
    $reversion->{id}
  );
}

# Returns data from the most recent non-gfv entry in rights_log,
# plus a count of */gfv entries (including the one we are reverting from)
# e.g., { attr => 5, reason => 8, source => 1, gfv_count => 1 }
sub _rights_log_data {
  my $self      = shift;
  my $namespace = shift;
  my $id        = shift;

  my $rights_log_data = { gfv_count => 0 };
  my $sth = $self->{select_rights_log_sth};
  $sth->execute($namespace, $id) or die $sth->errstr;
  while (my $row = $sth->fetch) {
    my ($attr, $reason, $source) = @$row;
    if ($reason == $GFV_REASON_ID) {
      $rights_log_data->{gfv_count}++;
    } elsif (!defined $rights_log_data->{attr}) {
      $rights_log_data->{attr} = $attr;
      $rights_log_data->{reason} = $reason;
      $rights_log_data->{source} = $source;
    }
  }
  return $rights_log_data;
}

1;