package rightsDB;

use strict;
no strict 'refs';
no strict 'subs';

use lib "$ENV{ROOTDIR}/perl_lib";

use File::Basename;
use YAML;
use Database;

sub new {
  my $class = shift;
  $class = ref($class) || $class; # Handle cloning

  my $self;

  # globals
  my $sdr_dbh = Database::get_ht_ro_dbh;
  my $sdr_sth = InitSdrSth($sdr_dbh);
  $self->{sdr_dbh} = $sdr_dbh;
  $self->{sdr_sth} = $sdr_sth;

  $self->{attribute_codes} = TableToHash($self, "attributes");
  $self->{reason_codes} = TableToHash($self, "reasons");
  $self->{source_codes} = TableToHash($self, "sources");
  $self->{access_profile_codes} = TableToHash($self, "access_profiles");
  $self->{access_profile_table} = getAccessProfileTable($self);

  return bless $self, $class;
}

sub InitSdrSth {
  my $dbh = shift;

  my $sql = "SELECT attr, reason, source, time, note, access_profile, user FROM rights_current WHERE id=? and namespace = ?";
  my $sth = $dbh->prepare($sql) or die "can't prepare $sql\n";
  return $sth
}

sub GetRightsFromDB {
  my $self = shift;
  my $full_id = shift;

  my $sth = $self->{sdr_sth};
  my ($ns, $id) = split(/\./,$full_id,2);

  $sth->execute($id, $ns) or do {
    print "$full_id: GetRightsFromDB: error in execute, message is " . $sth->errstr() . "\n";
    return "";
  };
  my $ref = $sth->fetchall_arrayref() or do {
    print "$full_id: GetRightsFromDB: error in fetchall_arrayref, message is " . $sth->errstr() . "\n";
    return "";
  };

  foreach ( @{$ref} ) {
    my $attr_code = $self->{attribute_codes}{$_->[0]};
    my $reason_code = $self->{reason_codes}{$_->[1]};
    my $source_code = $self->{source_codes}{$_->[2]};
    my $time = $_->[3];
    my $note = $_->[4];
    my $access_profile_code = $self->{access_profile_codes}{$_->[5]};
    my $user = $_->[6];
    #my $date = substr($time, 0, 4) . substr($time, 5, 2) . substr($time, 8, 2);
    #return join("\t", $attr_code, $reason_code, $source_code, $date, $note);
    return ($attr_code, $reason_code, $source_code, $time, $note, $access_profile_code, $user);
  }
  print STDERR "GetRightsFromDB ($full_id): can't get rights from rights database\n";
  return ();
}

sub TableToHash {
  my $self = shift;
  my $table_name = shift;
  my $hash = {};
  my $ref = $self->{sdr_dbh}->selectall_arrayref( "SELECT id,name FROM $table_name");
  foreach ( @{$ref} ) { 
    $hash->{$_->[0]} = $_->[1]; 
  }
  return $hash;
}

sub getAccessProfileTable {
  my $self = shift;
  my $hash = {};
  my $ref;
  $ref = $self->{sdr_dbh}->selectall_arrayref( "select collection, digitization_source, name from ht.ht_collection_digitizers, ht.access_profiles where access_profile = id");
  foreach my $row ( @{$ref} ) {
    my $collection = $$row[0];
    my $dig_source = $$row[1];
    my $access_profile = $$row[2];
    $hash->{join("\t", $collection, $dig_source)} = $access_profile;
  }
  return $hash;
}

sub determineAccessProfile {
  my $self = shift;
  my $collection = shift;
  my $dig_source  = shift;
  return $self->{access_profile_table}->{join("\t", $collection, $dig_source)};
}

1;
