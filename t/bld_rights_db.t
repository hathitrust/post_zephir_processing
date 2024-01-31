use strict;
use warnings;
use utf8;

use DB_File;
use File::Basename;
use Test::More;

BEGIN {push @INC, dirname(__FILE__) . "/.."};
use rightsDB;

subtest "bld_rights_db.pl" => sub {
  # Set up rights_current for call to bld_rights_db.pl
  my $rightsDB = rightsDB->new();
  my $sdr_dbh = $rightsDB->{sdr_dbh};
  InsertSomeUnicode($sdr_dbh);
  my $sql = 'SELECT COUNT(*) FROM rights_current';
  my $aref = $sdr_dbh->selectall_arrayref($sql);
  my $actual_count = $aref->[0]->[0];
  # Set up call to bld_rights_db.pl
  my $ROOT = dirname(__FILE__) . "/../";
  my $indexfile = dirname(__FILE__) . '/test_rights_dbm';
  my $bld_rights_db = $ROOT . 'bld_rights_db.pl';
  my $exit = system("$bld_rights_db -x $indexfile");
  is($exit, 0);
  my %INDEX;
  tie %INDEX, "DB_File", $indexfile, O_RDONLY, 0644, $DB_BTREE;
  my $index_count = scalar keys %INDEX;
  is($index_count, $actual_count);
  # Make sure we can actually read the value back out.
  my @values = split("\t", $INDEX{"test.unicode"});
  is(scalar @values, 6);
  RemoveSomeUnicode($sdr_dbh);
  unlink $indexfile if -f $indexfile;
};

done_testing();

sub InsertSomeUnicode {
  my $dbh = shift;

  my $sql = 'REPLACE INTO rights_current' .
    ' (namespace,id,attr,reason,source,access_profile,note)' .
    ' VALUES ("test","unicode",1,1,1,1,"ʇsnɹ⊥ıɥʇɐH")';
  $dbh->prepare($sql)->execute();
}

sub RemoveSomeUnicode {
  my $dbh = shift;

  my $sql = 'DELETE FROM rights_current WHERE namespace="test" AND id="unicode"';
  $dbh->prepare($sql)->execute();
}