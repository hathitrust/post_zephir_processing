#!/usr/bin/env perl

# Does things in 2 steps.
# Each step consists of running a set of queries,
# and sending an email about what was done.
#
# Step 1:
# Updates ic/bib and und/bib rows to pdus/gfv in rights_current
# if they have viewability 'VIEW_FULL' GRIN and are not marked as CLAIMED and are not Keio.
# CLAIMED items are items with the CLAIMED flag is set, items where the rights holder has given permission
# to Google to make the item VIEW_FULL. That permission does not extend to HathiTrust.
# We don't do it for Keio because there are items that are PD in Japan that are not PD in the US (e.g. icus)

# Step 2:
# Updates pdus/gfv rows in rights_current records
# with their previous attr&reason
# if they no longer have viewability 'VIEW_FULL' in GRIN.

use strict;
use warnings;

use Date::Manip qw(ParseDate UnixDate);
use DBI;
use Getopt::Long;
use Mail::Mailer;
use ProgressTracker;
use YAML::XS;

my $noop         = undef; # set with --noop
my $mailer       = undef;
my $email_body   = ""; # holds the current email body
my $volcount     = 0;

# static values for queries
my $force_attr   = "9";  # pdus
my $force_reason = "12"; # gfv
my $r_note       = 'Revert to previous attr/reason; no longer VIEW_FULL';
my $user         = 'libadm';

# config
my $config_dir   = $ENV{CONFIG_DIR} || '/usr/src/app/config';
my $config_yaml  = "$config_dir/rights.yml";
my $db_yaml      = "$config_dir/database.yml";
my $config       = YAML::XS::LoadFile($config_yaml);
my $rights_dir   = $config->{rights}->{rights_dir};
my $dbh          = get_dbh();

GetOptions(
    # skip update queries, emails, log file & tracker
    'noop=s' => \$noop,
);

#### Step 1: UPDATE ITEMS TO FULL VIEW ####
my $tracker = ProgressTracker->new();
$tracker->start_stage("set_pdus_gfv") unless $noop;

# This gets us the items to update in update_gfv.
my $select_gfv_sql = join(
    ' ',
    "SELECT r.namespace, r.id, a.name",
    "FROM rights_current     r",
    "INNER JOIN attributes   a ON r.attr   = a.id",
    "INNER JOIN reasons      e ON r.reason = e.id",
    "INNER JOIN ht.feed_grin g ON r.id     = g.id AND r.namespace = g.namespace",
    "WHERE g.viewability = 'VIEW_FULL' AND a.name IN ('ic', 'und') AND e.name = 'bib' AND g.claimed != 'true' AND r.namespace != 'keio'"
);

# Takes values for 2 bind-params, in the order: namespace, id.
# user, attr & reason are static, so no bind-params for those.
my $update_gfv_sql = join(
    ' ',
    "UPDATE rights_current",
    "SET attr = '$force_attr', reason = '$force_reason', time = CURRENT_TIMESTAMP, user = '$user'",
    "WHERE namespace = ? AND id = ?"
);
my $update_gfv_sth = $dbh->prepare($update_gfv_sql) || die "could not prepare query: $update_gfv_sql";

# Loop over the relevant items and update their attr/reason
foreach my $row (@{$dbh->selectall_arrayref($select_gfv_sql)}) {
    my ($namespace, $id, $attrname) = @$row;
    $email_body .= "$namespace.$id\t$attrname\n";
    $volcount++;
    unless ($noop) {
        $update_gfv_sth->execute($namespace, $id);
        $tracker->inc();
    }
}

# Send first email
unless ($noop) {
    $mailer = new_mailer("New ic/und but VIEW_FULL volumes");
    print $mailer "$volcount volumes set to pdus/gfv at " . CORE::localtime() . "\n";
    print $mailer "$email_body";
    $mailer->close() or warn("Couldn't send message: $!");
}

#### Step 2: REVERT FORMERLY VIEW_FULL ITEMS ####
$tracker->start_stage("revert_pdus_gfv") unless $noop;

my $select_revert_sql = join(
    ' ',
    "SELECT r.namespace, r.id",
    "FROM rights_current r",
    "INNER JOIN ht.feed_grin g ON r.id = g.id AND r.namespace = g.namespace",
    "WHERE r.reason='12' AND (g.viewability != 'VIEW_FULL' OR g.claimed = 'true' OR r.namespace = 'keio')"
);

# Takes values for 2 bind-params, in the order: id, namespace.
my $select_old_sql = join(
    ' ',
    "SELECT attr, reason, source",
    "FROM rights_log",
    "WHERE id = ? AND namespace = ? AND reason != '12'",
    "ORDER BY time DESC",
    "LIMIT 1"
);
my $select_old_sth = $dbh->prepare($select_old_sql) || die "could not prepare query: $select_old_sql";

# Takes values for 4 bind-params in the order: oldattr, oldreason, namespace, id.
# user, note & time are static so not a bind-params for them.
my $update_revert_sql = join(
    ' ',
    "UPDATE rights_current",
    "SET attr = ?, reason = ?, user = '$user', time = CURRENT_TIMESTAMP, note = '$r_note'",
    "WHERE namespace = ? AND id = ?"
);
my $update_revert_sth = $dbh->prepare($update_revert_sql) || die "could not prepare query: $update_revert_sql";

# Start second email
$email_body = "Reverting pdus/gfv volumes that are no longer VIEW_FULL\n";

# Open file for which to record reverted barcodes
my $barcode_log = sprintf(
    '%s/barcodes_%s_revert_gfv_feed',
    $rights_dir,
    UnixDate(ParseDate("now"), '%Y-%m-%d_%H-%M-%S')
);
open(my $fh, ">>", $barcode_log) or die("can't open $barcode_log: $!");

# This loop does a couple of things...
foreach my $row (@{$dbh->selectall_arrayref($select_revert_sql)}) {
    # get the namespace and id for the item to update
    my ($namespace, $id) = @$row;

    # get the item's most recent non-gfv attr/reason
    $select_old_sth->execute($id, $namespace);
    my ($oldattr, $oldreason) = $select_old_sth->fetchrow_array();

    unless ($noop) {
        # append item to email body and print barcode to log file
        $email_body .= "\t$namespace.$id\n";
        print $fh "$namespace.$id\n";

        # update item in rights_current with the old attr/reason
        $update_revert_sth->execute($oldattr, $oldreason, $namespace, $id);
        $tracker->inc();
    }
}
close($fh);

unless ($noop) {
    # Send the second email and we're done
    $mailer = new_mailer("Old pdus/gfv volumes no longer VIEW_FULL");
    $mailer->close() or warn("Couldn't send message: $!");
}

$tracker->finalize() unless $noop;
$dbh->disconnect;

# The 2 emails sent only differ in subject and body,
# so we can do everything else using the same template.
sub new_mailer {
    my $subject = shift;
    my $mailer  = new Mail::Mailer;
    my $to_addr = join(
        ', ',
        split(' ', $ENV{'TO_ADDRESSES'})
    );

    my $email = {
        'From'    => $ENV{'FROM_ADDRESS'},
        'Subject' => $subject,
        'To'      => $to_addr
    };

    $mailer->open($email);
}

# Inspired by HTFeed::DBTools::_init
sub get_dbh {
    my $db_conf  = YAML::XS::LoadFile($db_yaml);
    my $dbname   = $db_conf->{dbname};
    my $hostname = $db_conf->{hostname};
    my $dbuser   = $db_conf->{user};
    my $passwd   = $db_conf->{password};

    my $extra_params = {
        'RaiseError' => 1,
    };

    my $dbh = DBI->connect(
        "DBI:MariaDB:$dbname:$hostname",
        $dbuser,
        $passwd,
        $extra_params
    );

    return $dbh;
}
