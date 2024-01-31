#!/usr/bin/env perl
use File::Basename;
use lib dirname(__FILE__);
use DB_File;
use File::Basename;
use POSIX qw(strftime);
use DBI qw(:sql_types);
use Encode qw(encode);
use Getopt::Std;
use rightsDB;
use strict;

my $prgname = basename($0);
our($opt_x);
getopts('x:');
$opt_x or die "usage: $prgname -x indexfile (no index  file specified)";
my $indexfile = $opt_x;

my %INDEX;
unlink($indexfile);
tie %INDEX, "DB_File", $indexfile, O_RDWR|O_CREAT, 0644, $DB_BTREE;

my $rightsDB = rightsDB->new();
my $sdr_dbh = $rightsDB->{sdr_dbh};

print "getting attribute codes\n";
my $attribute_codes = TableToHash($sdr_dbh, "attributes");
print "getting reason codes\n";
my $reason_codes = TableToHash($sdr_dbh, "reasons");
my $source_codes = TableToHash($sdr_dbh, "sources");
my $access_profile_codes = TableToHash($sdr_dbh, "access_profiles");

#| namespace      | varchar(8)  | NO   |     | NULL                |       | 
#| id             | varchar(32) | NO   |     |                     |       | 
#| attr           | tinyint(4)  | NO   |     | NULL                |       | 
#| reason         | tinyint(4)  | NO   |     | NULL                |       | 
#| source         | tinyint(4)  | NO   |     | NULL                |       | 
#| access_profile | tinyint(4)  | NO   |     | NULL                |       | 
#| user           | varchar(32) | NO   |     |                     |       | 
#| time           | timestamp   | NO   |     | 0000-00-00 00:00:00 |       | 
#| note           | text        | YES  |     | NULL                |       | 

print "prepare\n";
my $sdr_sth = $sdr_dbh->prepare("SELECT id, namespace, attr, reason, source, time, note, access_profile FROM rights_current") or die "can't prepare";
print "execute\n";
$sdr_sth->execute() or die "can't execute";

my $incnt = 0;
my $outcnt = 0;
my $attr_code;
my $reason_code;
my $source_code;
my $access_profile_code;
print "entering fetch loop\n";
while ( my ($id, $namespace, $attr_num, $reason_num, $source_num, $timestamp, $note, $access_profile_num) = $sdr_sth->fetchrow_array() ) {
  $incnt++;
  # print STDERR "processing $incnt\n" if $incnt % 100000 == 0;
  $id =~ s/\s+$//;
  $attr_code = $attribute_codes->{$attr_num};
  $source_code = $source_codes->{$source_num};
  $reason_code = $reason_codes->{$reason_num};
  $access_profile_code = $access_profile_codes->{$access_profile_num};
  my $mdp_id = join(".", $namespace, $id);
  my $data = join("\t", $attr_code, $reason_code, $source_code, $timestamp, $note, $access_profile_code);
  $INDEX{"$mdp_id"} = encode("UTF-8", $data);
  $outcnt++;
}
dbmclose(%INDEX);

print STDERR "$incnt rights records read\n";
print STDERR "$outcnt index records written\n";

sub TableToHash {
  my $sdr_dbh = shift;
  my $table_name = shift;
  my $hash = {};
  my $ref = $sdr_dbh->selectall_arrayref( "SELECT id,name FROM $table_name");
  foreach ( @{$ref} ) {
    $hash->{$_->[0]} = $_->[1];
  }
  return $hash;
}

