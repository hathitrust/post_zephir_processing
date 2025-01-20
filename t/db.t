#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use lib "$ENV{ROOTDIR}/perl_lib";

use DBI;
use Encode qw(encode);
use Test::More;
use YAML;

use Database;

# This test is here as an example to help characterize the behavior of the
# database connection and ensure that we can process UTF-8 at least from the
# perl side. YMMV in production as it might be a different version of mariadb
# with different settings, etc.



my $dbh = Database::get_rights_rw_dbh;

subtest "UTF-8 support for ht_rights" => sub {
  my @tables = ('rights_current', 'rights_log');
  foreach my $table (@tables) {
    clean_utf8_test($table);
    my $note = '慶應義塾大';
    print "Length of note is " . length($note) . "\n";
    my $sql = "INSERT INTO $table (namespace,id,attr,reason,source,access_profile,user,note)" .
              " VALUES ('utf8test','0',2,1,1,1,'libadm','慶應義塾大')";
    my $sth = $dbh->prepare($sql);
    $sth->execute;
    $sth = $dbh->prepare("SELECT note FROM $table WHERE namespace=? AND id=?");
    $sth->execute('utf8test', '0');
    my @row = $sth->fetchrow_array;
    $sth->finish;
    is($row[0], "慶應義塾大", "UTF-8 round-trip in $table.note");
    $sth = $dbh->prepare("SELECT COUNT(*) FROM $table WHERE note='慶應義塾大'");
    $sth->execute;
    @row = $sth->fetchrow_array;
    is($row[0], 1, "Can find $table.note with UTF-8 value.");
    clean_utf8_test($table);
  }

  sub clean_utf8_test {
    my $table = shift;

    my $sth = $dbh->prepare("DELETE FROM $table WHERE namespace=? AND id=?");
    $sth->execute('utf8test', '0');
  }
};

done_testing();

__END__
