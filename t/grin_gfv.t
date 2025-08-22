#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Data::Dumper;
use POSIX qw(strftime);
use Test::More;

use lib "$ENV{ROOTDIR}/perl_lib";
use Database;
use grin_gfv;

my $dbh = Database::get_rights_rw_dbh;

sub load_test_fixtures {
  my $fixture_data = shift;

  my $rights_current_sql = 'INSERT INTO rights_current (namespace, id, attr, reason, source, access_profile) VALUES (?, ?, ?, ?, 1, 1)';
  # For reversion, create a matching rights_log entry
  my $rights_log_sql = 'INSERT INTO rights_log (namespace, id, attr, reason, source, access_profile) VALUES (?, ?, ?, ?, 1, 1)';
  # Old rights to revert to and old VIEW_FULL cases to count
  my $old_rights_log_sql = <<~'SQL';
    INSERT INTO rights_log (namespace, id, attr, reason, source, access_profile, time)
    VALUES (?, ?, ?, ?, 1, 1, ?)
  SQL
  my $feed_grin_sql = 'INSERT INTO ht.feed_grin (namespace, id, viewability, claimed) VALUES (?, ?, ?, ?)';
  my $rights_current_sth = $dbh->prepare($rights_current_sql);
  my $rights_log_sth = $dbh->prepare($rights_log_sql);
  my $old_rights_log_sth = $dbh->prepare($old_rights_log_sql);
  my $feed_grin_sth = $dbh->prepare($feed_grin_sql);
  foreach my $fixture (@$fixture_data) {
    my ($namespace, $id, $attr, $reason, $viewability, $claimed, $logs) = @$fixture;
    $rights_current_sth->execute($namespace, $id, $attr, $reason);
    $rights_log_sth->execute($namespace, $id, $attr, $reason);
    # Insert an old ic/bib so we have something to revert to
    $old_rights_log_sth->execute($namespace, $id, 2, 1, '2021-01-01 00:00:00');
    $feed_grin_sth->execute($namespace, $id, $viewability, $claimed);
    # Optionally insert some old pdus/gfv entries so we can count them
    foreach my $n (1..$logs) {
      my $date = "2020-01-0$n 00:00:00";
      $old_rights_log_sth->execute($namespace, $id, 9, 12, $date);
    }
  }
}

sub unload_test_fixtures {
  $dbh->prepare('DELETE FROM rights_current WHERE namespace IN ("gfvtest","keio")')->execute;
  $dbh->prepare('DELETE FROM rights_log WHERE namespace IN ("gfvtest","keio")')->execute;
  $dbh->prepare('DELETE FROM ht.feed_grin WHERE namespace IN ("gfvtest","keio")')->execute;
}

# Clean up any previously failed tests
unload_test_fixtures;

# Qualifies if ic/und and bib and VIEW_FULL and not claimed
my $updates_test_fixtures = [
  # namespace id             attr (ic=2 und=5) reason (bib=1) viewability  claimed  logs comment
  ['gfvtest', 'ic',          2,                1,             'VIEW_FULL', 'false', 0,   'ic included'],
  ['gfvtest', 'und',         5,                1,             'VIEW_FULL', 'false', 0,   'und included'],
  ['gfvtest', 'pd',          1,                1,             'VIEW_FULL', 'false', 0,   'pd/* excluded'],
  ['gfvtest', 'nfi',         5,                8,             'VIEW_FULL', 'false', 0,   '*/nfi excluded'],
  ['gfvtest', 'nonviewable', 2,                1,             '',          'false', 0,   'viewability != VIEW_FULL excluded'],
  ['gfvtest', 'claimed',     2,                1,             'VIEW_FULL', 'true',  0,   'claimed=true excluded'],
  ['keio',    'keio',        2,                1,             'VIEW_FULL', 'false', 0,   'keio excluded'],
];

subtest "updates_to_gfv" => sub {
  my $err;
  load_test_fixtures($updates_test_fixtures);
  my $grin_gfv = grin_gfv->new;
  my $updates = $grin_gfv->updates_to_gfv;
  my $expected = [
    {
      'attr'      => 'ic',
      'id'        => 'ic',
      'namespace' => 'gfvtest'
    },
    {
      'attr'      => 'und',
      'id'        => 'und',
      'namespace' => 'gfvtest'
    }
  ];
  unload_test_fixtures;
  is_deeply($updates, $expected);
};

subtest 'updates_to_gfv_report' => sub {
  load_test_fixtures($updates_test_fixtures);
  my $grin_gfv = grin_gfv->new;
  my $date_string = strftime($grin_gfv::REPORT_TIME_FORMAT, localtime);
  my $updates = $grin_gfv->updates_to_gfv;
  my $report = $grin_gfv->updates_to_gfv_report($updates, date_string => $date_string);
  my $expected = <<~REPORT;
  2 volumes set to pdus/gfv at $date_string

  IC

  gfvtest.ic

  UND

  gfvtest.und
  REPORT
  unload_test_fixtures;
  is($report, $expected);
};


# Qualifies if gfv and (not VIEW_FULL or claimed or keio)
# old_logs is in addition to the rights we're reverting from so the result will be old_logs + 1 for gfv_count
my $reversions_test_fixtures = [
  # namespace id             attr (pdus=9) reason (gfv=12) viewability  claimed old_logs comment
  ['gfvtest', 'bib',         9,                1,          'VIEW_FULL', 'false', 0,      'non-gfv excluded'],
  ['gfvtest', 'nonviewable', 9,                12,         '',          'false', 0,      'viewability != VIEW_FULL included'],
  ['gfvtest', 'claimed',     9,                12,         'VIEW_FULL', 'true',  1,      'claimed=true included'],
  ['keio',    'keio',        9,                12,         'VIEW_FULL', 'false', 2,      'keio included'],
];

subtest "reversions_from_gfv" => sub {
  load_test_fixtures($reversions_test_fixtures);
  my $grin_gfv = grin_gfv->new;
  my $reversions = $grin_gfv->reversions_from_gfv;
  my $expected = [
    {
      'attr'      => 2,
      'gfv_count' => 2,
      'id'        => 'claimed',
      'namespace' => 'gfvtest',
      'reason'    => 1,
      'source'    => 1
    },
    {
      'attr'      => 2,
      'gfv_count' => 1,
      'id'        => 'nonviewable',
      'namespace' => 'gfvtest',
      'reason'    => 1,
      'source'    => 1
    },
    {
      'attr'      => 2,
      'gfv_count' => 3,
      'id'        => 'keio',
      'namespace' => 'keio',
      'reason'    => 1,
      'source'    => 1
    }
  ];
  unload_test_fixtures;
  is_deeply($reversions, $expected);
};

subtest 'reversions_from_gfv_report' => sub {
  load_test_fixtures($reversions_test_fixtures);
  my $grin_gfv = grin_gfv->new;
  my $date_string = strftime($grin_gfv::REPORT_TIME_FORMAT, localtime);
  my $reversions = $grin_gfv->reversions_from_gfv;
  my $report = $grin_gfv->reversions_from_gfv_report($reversions, date_string => $date_string);
  my $expected = <<~REPORT;
  3 volumes reverted from pdus/gfv at $date_string

  Has prior GFV status

  gfvtest.claimed
  keio.keio

  No prior GFV status

  gfvtest.nonviewable
  REPORT
  unload_test_fixtures;
  is($report, $expected);
};

done_testing;

__END__

