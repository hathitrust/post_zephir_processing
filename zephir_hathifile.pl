#!/usr/bin/perl

use open qw( :encoding(UTF-8) :std );
use strict;
use local::lib "$FindBin::Bin";
use lib "$FindBin::Bin/lib";
BEGIN {push @INC, '.'}
use File::Basename;
BEGIN {push @INC, dirname(__FILE__)}
no strict 'refs';
use Sys::Hostname;
use YAML qw'LoadFile';
use Data::Dumper;
use JSON::XS;
use URI::Escape;
use LWP::Simple;

use Getopt::Std;
use FileHandle;
use POSIX qw(strftime);
use DB_File;

use MARC::Record;
use MARC::Batch;
use MARC::Record::MiJ;
use MARC::File::XML(BinaryEncoding => 'utf8');

use bib_rights;
use rightsDB;

my $prgname = basename($0);
select STDERR; $| = 1;
select STDOUT; $| = 1;

sub usage {
  my $msg = shift;
  $msg and $msg = " ($msg)";
  return"usage: $prgname -i infile -o outbase [-f rights_db_file][-r rights_output_file [-d (rights debug file wanted]][-u incremental_cutoff_date (yyyymmdd, default is 00000000)][-h htrc_file_wanted][-z zephir_ingested_items_file_wanted]$msg\n";
};

our($opt_i, $opt_o, $opt_r, $opt_f, $opt_u, $opt_d, $opt_h, $opt_z);
getopts('i:o:r:f:u:h:z:d');

$opt_i or die usage("no input file specified");
$opt_o or die usage("no output file specified");
my $infile = $opt_i;
my $outbase = $opt_o;
my $out_hathi = $outbase . "_hathi.txt";
my $out_json = $outbase . ".json";
my $out_report = $outbase . "_rpt.txt";
my $out_dollar_dup = $outbase . "_dollar_dup.txt";
my $out_delete = $outbase . "_delete.txt";
my $out_zia = $outbase . "_zia.txt";
my $rights_db_file = '';
$opt_f and $rights_db_file = $opt_f;

my $rights_output_file = '';
$opt_r and do {
  $rights_output_file = $opt_r;
  open(RIGHTS, ">$rights_output_file") or die "can't open $rights_output_file for output: $!\n";
  open(RIGHTS_RPT, ">${rights_output_file}_rpt.tsv") or die "can't open ${rights_output_file}_rpt.tsv for output: $!\n";
  binmode(RIGHTS_RPT, ":encoding(UTF-8)");
};

my $rights_debug = 0;
$opt_d and do {
  $opt_r or die usage("can't use right debug flag without -r");
  $rights_debug++;
  open(DEBUG,">$rights_output_file.debug") or die "can't open $rights_output_file.debug for output: $!\n";
};

my $htrc_output = undef;
$opt_h and do {
  my $meta_base = $outbase . "_meta";
  $htrc_output = setup_htrc_output($meta_base);
  print "htrc outupt file basename: $meta_base\n";
};

my $zia_output = 0;
$opt_z and do {
  $zia_output++;
  open(ZIA,">$out_zia") or die "can't open $out_zia for output: $!\n";
};

my %rights_diff = ();
 
my %bib_error = ();

my $current_timestamp = `date '+%Y-%m-%d %H:%M:%S'`;
chomp $current_timestamp;
my $current_date = getDate(time() - 86400); 	# yesterday is the date the zephir file was created
my $update_cutoff = 0;
$opt_u and do {
  $opt_u =~ /^\d{8}$/ or die usage("invalid update cutoff date $opt_u");
  $update_cutoff = $opt_u;
};

print "Input file is $infile\n";

my $infile_open = $infile;
$infile =~ /\.gz$/ and do {
  # $infile_open = "unpigz -c $infile |";
  $infile_open = "gunzip -c $infile |";
  print "infile $infile is compressed, using gunzip to process: $infile_open\n";
  $infile =~ s/\.gz$//;
};
open(IN,"$infile_open") or die "can't open $infile for input: $!\n";

my $badfile;
my $changefile;
if ($infile eq '-') {
  $badfile = "stdin.json.bad";
  $changefile = "stdin.json.change";
} else {
  $badfile = "$infile.bad";
  $changefile = "$infile.change";
}
binmode(IN);
#binmode(IN,":utf8");

open(BAD, ">$badfile") or die "can't open $badfile for output: $!\n";
open(CHANGE, ">$changefile") or die "can't open $changefile for output: $!\n";
binmode(BAD);
binmode(CHANGE);

# TODO: open(OUT_HATHI,">$out_hathi") or die "can't open $out_hathi for output: $!\n";
open(OUT_JSON,">$out_json") or die "can't open $out_json for output: $!\n";
#binmode(OUT_JSON, ":encoding(UTF-8)");
binmode(OUT_JSON);
open(OUT_RPT,">$out_report") or die "can't open $out_report for output: $!\n";
select OUT_RPT; $| = 1;
select STDOUT;
open(OUT_DOLLAR_DUP,">$out_dollar_dup") or die "can't open $out_dollar_dup for output: $!\n";
open(OUT_DELETE,">$out_delete") or die "can't open $out_delete for output: $!\n";

# TODO: open(OUT_HATHI_HEADER, ">hathi_field_list.txt") or die "can't open hathi field header file for output: $!\n";
# TODO: write_hathi_header();
# TODO: close OUT_HATHI_HEADER;

print OUT_RPT "processing file $infile\n";

if ($update_cutoff) {
  print OUT_RPT "incremental mode, only include items with update date on or after $update_cutoff in hathifile\n";
} else {
  print OUT_RPT "full mode, include all items in hathifile\n";
}

my $rightsDB = rightsDB->new();
my $rights_sub = '';
my %RIGHTS;
if ($rights_db_file) {
  print "using dbm file $rights_db_file for rights determination\n";
  print OUT_RPT "using dbm file $rights_db_file for rights determination\n";
  tie %RIGHTS, "DB_File", $rights_db_file, O_RDONLY, 0644, $DB_BTREE or die "can't read rights db $rights_db_file: $!\n";
  $rights_sub = "GetRightsDBM";
} else {
  print "using mysql call for rights determination\n";
  print OUT_RPT "using mysql call for rights determination\n";
  $rights_sub = "GetRights";
}

# list of collections from ht_rights database
my $ht_collections = getCollectionTable($rightsDB);
#print  Dumper($ht_collections);
 
# build mapping of collection to sysnum prefixes (coll => sdr_prefix)
# first--set collections where the prefix differs
my $sdrnum_prefix_map = {
# collection => prefix
  'deu' => 'udel',
  #'ibc' => 'bc\.',
  'ibc' => '(?:bc\.|bc-loc\.)',
  'iduke' => 'duke\.',
  'iloc' => 'loc',
  'incsu' => 'ncsu\.',
  'innc' => 'nnc',
  'inrlf' => 'nrlf',
  'ipst' => 'pst\.',
  'isrlf' => 'srlf',
  'iucla' => 'ucla',
  'iucd' => 'ucd',
  'iufl' => '(?:ufl|ufdc)',
  'iuiuc' => 'uiuc',
  'iunc' => 'unc\.',
  'mdl' => 'mdl\.',
  'mwica' => 'mwica',
  'mmet' => 'tu',
  'mu' => 'uma',
  'nrlf' => '(?:nrlf-ucsc|nrlf-ucsf|nrlf)',
  'pst' => 'pst\.',
  'qmm' => 'qmm',
  'txcm' => 'tam',
  #'ucm' => 'ucm\.',
  'ucm' => '(?:ucm\.|ucm-loc\.)',
  #'uiucl' => 'uiuc-loc',
  'uiucl' => 'uiuc',
  'usu' => 'usu\.',
  'uva' => 'uva\.',
  'gri' => 'cmalg',
  'umlaw' => 'miu',
  'umdb' => 'miu',
  'umbus' => 'miu',
  'umdcmp' => 'miu',
  'umprivate' => 'miu',
  'gwla' => 'miu',
  'iau' => 'uiowa',
  'ctu' => 'ucw',
  'ucbk' => '(?:ucbk|ucb|ucb-2|cul)',
  'geu' => 'emu',
  'nbb' => 'miu',
  'aubru' => 'uql-1',
};
# read current list of hathitrust collections, add to map if not already set
#COLL:foreach my $coll (sort keys (%$ht_collections)) {
COLL:foreach my $coll (sort keys (%$ht_collections)) {
  $coll = lc($coll);
  exists $sdrnum_prefix_map->{$coll} and do {
    #print STDERR "$coll: sdr prefix set in program: $sdrnum_prefix_map->{$coll}\n";
    next COLL;
  };
  $sdrnum_prefix_map->{$coll} = $coll;
}

#foreach my $coll (sort keys %$sdrnum_prefix_map) {
#  print join("\t", $coll, $sdrnum_prefix_map->{$coll}), "\n";
#}

#my %rights_map = (
#  "pd" => "allow",      # 1 - public domain
#  "ic" => "deny",       # 2 - in-copyright
#  "opb" => "deny",      # 3 - out-of-print and brittle (implies in-copyright)
#  "op" => "deny",       # 3 - out-of-print (implies in-copyright)
#  "orph" => "deny",     # 4 - copyright-orphaned (implies in-copyright)
#  "und" => "deny",      # 5 - undetermined copyright status
#  "umall" => "deny",    # 6 - available to UM affiliates and walk-in patrons (all campuses)
#  "world" => "allow",   # 7 - available to everyone in the world (will be deprecated)
#  "ic-world" => "allow",        # 7 - in-copyright and permitted as world viewable by the depositor
#  "nobody" => "deny",   # 8 - available to nobody; blocked for all users
#  "pdus" => "allow",    # 9 - public domain only when viewed in the US
#  "cc-by" => "allow",           # 10 - Creative Commons
#  "cc-by-nd" => "allow",        # 11 - Creative Commons
#  "cc-by-nc-nd" => "allow",     # 12 - Creative Commons
#  "cc-by-nc" => "allow",        # 13 - Creative Commons
#  "cc-by-nc-sa" => "allow",     # 14 - Creative Commons
#  "cc-by-sa" => "allow",        # 15 - Creative Commons
#  "orphcand" => "deny",         # 16 - orphan candidate
#  "cc-zero" => "allow",         # 17 - Creative Commons
#  "und-world" => "allow",       # 18 - undetermined copyright status and permitted as world viewable by the depositor
#  "icus" => "deny",       # 19 - in copyright in the US 
#);

my $br = bib_rights->new();

my $exit = 0;
$SIG{INT} = sub { $exit = 1 };
$SIG{USR1} = 'handle_sig';
$SIG{USR2} = 'handle_sig';

sub handle_sig {
  my ($signal) = @_;
  my $now = strftime "%a %b %e %H:%M:%S %Y", localtime;
  print STDERR "$now: signal $signal ignored\n";
}

my $bibcnt = 0;
#my $dup_cid = 0;
my $f974_cnt = 0;
my $outcnt_hathi = 0;
my $excluded_update_date = 0;
my $outcnt_json = 0;
my $no_sdr_num = 0;
my $dollar_dup_cnt = 0;
my $rights_cnt = 0;
my $new_rights_cnt = 0;
my $db_rights_cnt = 0;
my $db_bib_rights_cnt = 0;
my $db_non_bib_rights_cnt = 0;
my $gfv_override_cnt = 0;
my $suppressed_974 = 0;
my $no_974 = 0;
my $no_resp_ent = 0;
my $no_cont_prov = 0;
my $no_access_profile = 0;
my $zia_cnt = 0;

my $rights_out_cnt = 0;

my $bib_info;
my $bib_key;
my ($sdr_list, $sdr_num, $lccn, $isbn, $issn, $title, $author, $imprint, $oclc_num);
my ($mdp_id, $rights, $description, $sub_library, $collection, $source, $update_date); 
#my %update_date = ();
my $digitization_source;
my $rights_diff_cnt = 0;
my $rights_match_cnt = 0;


my $bib;

#my %cid_list = ();

my $bad_skipped_cnt = 0;
my $bad_tab_newline_cnt = 0;
my $bad_out_cnt = 0;
my $change_out_cnt = 0;
my $num_nbsp_records = 0;

# labels for rights report file
$opt_r and print RIGHTS_RPT join("\t", 
  "#hathi_id",
  "CID",
  "current preferred record number",
  "new preferred record number",
  "access (rightsdb)",
  "access (bib record)",
  "rights attribute (rightsdb)", 
  "rights attribute (bib record)",
  "bib_ mt",
  "date used",
  "description",
  "reason",
  "008 field",
  "pub_place",
  "imprint",
  "title",
  "author",
), "\n";

my $jp = new JSON::XS;
$jp->utf8(1);
#$jp->pretty(0);

my $bib_line;

RECORD:while($bib_line = <IN> ) {
  $exit and do {
    print OUT_RPT "exitting due to signal\n";
    last RECORD;
  };
  my $current_preferred_record_number = ''; 	# cached preferred bib record from HT solr
  $bibcnt++;
  $bibcnt % 1000 == 0 and print STDERR "processing bib record $bibcnt\n";
  chomp($bib_line);
  my $save_bib_line = $bib_line;
  my $changes = 0;

  eval {
    ($bib_line, $changes)  = clean_json_line($bib_line);
    $bib = MARC::Record::MiJ->new($bib_line);
  };
  $@ and do {
    print OUT_RPT "problem processing json line $bibcnt\n";
    print OUT_RPT substr($bib_line,0,80), ":", join(' " ', $@), "\n";
    warn $@;
    print BAD $bib_line, "\n";
    $bad_out_cnt++;
    $bad_skipped_cnt++;
    next RECORD;
  };
  
  $bib_key = $bib->field('001')->as_string() or die "$bibcnt: no 001 field\n";
  $changes and do {
    #print STDERR "$bib_key($bibcnt): $changes characters stripped/blanked from json line\n";
    print OUT_RPT "$bib_key($bibcnt): $changes characters stripped/blanked from json line\n";
    print CHANGE $save_bib_line, "\n";
    $change_out_cnt++;
  };

  #$cid_list{$bib_key} and do {
  #  $dup_cid++;
  #  #print STDERR "$bib_key duplicate\n";
  #  next RECORD;
  #};
  #$cid_list{$bib_key}++;
  check_bib($bib, $bib_key);
  $bib_info = $br->get_bib_info($bib, $bib_key) or print OUT_RPT "$bib_key: can't get bib info\n";
  ($oclc_num, $sdr_list) = process_035($bib, $bib_key);
  $imprint = get_bib_data($bib, "260", 'bc');
  $imprint or do {
    $imprint = get_bib_data($bib, "264#1", 'bc');
    #$imprint and print "$$bib_key: no 260 bc in record, 264 2nd ind 1 used\n";
  };
  $title = get_bib_data($bib, "245", 'abcnp') or print OUT_RPT "$bib_key: null title for record\n";
  $isbn = get_bib_data($bib, "020", 'a');
  $issn = get_bib_data($bib, "022", 'a');
  $lccn = get_bib_data($bib, "010", 'a');
  $author = get_bib_data($bib, '100', 'abcd');
  $author or $author = get_bib_data($bib, '110', 'abcd');
  $author or $author = get_bib_data($bib, '111', 'acd');
  #$author or $author = get_bib_data($bib, '700', 'abc');
 
  my $preferred_record_number = get_bib_data($bib, "HOL", '0'); 
  my $preferred_record_collection = get_bib_data($bib, "HOL", 'c'); 
  
  my @f974 = $bib->field('974') or do {
    print OUT_RPT "$bib_key ($bibcnt): no 974 fields in input record\n";
    next RECORD;
  };
  # remove unwanted fields (should really be done in zephir)
  foreach my $field ($bib->field("PST|LOC|SBL")) {
    $bib->delete_field($field);
  }

  my $uc1_delete = filter_dollar_barcode(\@f974);	# check for duplication between uc1 BARCODE and $BARCODE
#  foreach my $id (sort keys %$uc1_delete) { print "$id\n";}

  F974:foreach my $f974 (@f974) {
    my ($print_id, $ns, $id);
    $mdp_id = $f974->as_string('u') or do {
      print OUT_RPT "$bib_key ($bibcnt): no subfield u for 974 field\n";
      next F974;
    };
    ($ns, $id) = split(/\./, $mdp_id);
    $uc1_delete->{$id} and do {
      $bib->delete_field($f974);
      print OUT_RPT "$mdp_id: non-dollar barcode uc1 $id with dollar version deleted\n";
      print OUT_DOLLAR_DUP "$mdp_id\n";
      $dollar_dup_cnt++;
      next F974;
    };
    $print_id = "$bib_key:$mdp_id ($bibcnt)";
    $description = $f974->as_string('z');
    $digitization_source = $f974->as_string('s');
    $source = $f974->as_string('b');
    $collection = $f974->as_string('c');
    $update_date = $f974->as_string('d');
    $zia_output and do {
      my $ia_id = $f974->as_string('8');
      print ZIA join("\t", $mdp_id, $source, $collection, $digitization_source, $ia_id), "\n";
      $zia_cnt++;
    };
    my $responsible_entity_code = $ht_collections->{$collection}->{responsible_entity_code} or do {
      print OUT_RPT "$mdp_id: no responsible entity for collection $collection in ht_collections\n";
      $no_resp_ent++;
    };
    my $content_provider_code = $ht_collections->{$collection}->{content_provider_code} or do {
      print OUT_RPT "$mdp_id: no content provider for collection $collection in ht_collections\n";
      $no_cont_prov++;
    };
    my $access_profile = $rightsDB->determineAccessProfile($collection, $digitization_source) or do {
      print OUT_RPT "$mdp_id: can't determine access profile fo collection '$collection' and dig source '$digitization_source'\n";
      $no_access_profile++;
    };

    # rights processing

    # determine rights from current bib/item info
    my $bri = $br->get_bib_rights_info($mdp_id, $bib_info, $description);
    my $bib_rights = $bri->{'attr'};
    my $rights_current = $bib_rights; 	# set to newly-determined bib rights
    my $reason_current = 'bib'; 	# set reason to bib for new records
    $bri->{date_used} and $bri->{date_used} ne '9999' and $f974->update('y' => $bri->{date_used});
    
    # check for existing rights in rights db
    #my ($db_rights, $db_reason, $timestamp) = &$rights_sub($mdp_id);
    my ($db_rights, $db_reason, $db_dig_source, $db_timestamp, $db_rights_note, $db_access_profile) = &$rights_sub($mdp_id);
    $rights_cnt++;

    my $compare_rights = 0;
    my $new_rights = 0;
    my $gfv_override = 0;
    my $access_profile = $db_access_profile;
    if ($db_rights eq '') {	# not in rights db
      #print STDERR "$print_id: no db rights\n";
      $new_rights_cnt++;
      $new_rights++;
    } elsif ($bib_rights =~ /^pd/ and $db_reason eq 'gfv') {	# gfv in rights db and bib rights pd/pdus
      $gfv_override_cnt++;
      $gfv_override++;
      print OUT_RPT "$print_id: gfv rights reverted to bib, db: $db_rights/$db_reason ($db_timestamp), bib: $bib_rights\n";
    } else {				# in rights db (non-gfv)
      $db_rights_cnt++;
      if ( $db_reason eq 'bib') {
        $db_bib_rights_cnt++;
        $compare_rights = 1;	# set flag for rights comparison
      } else {
        $db_non_bib_rights_cnt++;
        $rights_current = $db_rights;	# set to non-bib db rights
        $reason_current = $db_reason;	# set to non-bib db reason
        #print OUT_RPT "$print_id: non-bib reason $db_reason ($db_timestamp): " . outputField($f974) . "\n";
        print OUT_RPT "$print_id: non-bib reason, db: $db_rights/$db_reason ($db_timestamp), bib: $bib_rights\n";
      }
    }
      
    $rights_current eq 'supp' and do {
      $bib->delete_field($f974);
      print OUT_RPT "$print_id: suppressed 974 field deleted\n";
      $suppressed_974++;
      next F974;
    };
    $f974->update('r' => $rights_current);
    $f974->update( 'q' => $reason_current );
    $reason_current eq 'bib' and do {
      $f974->update( 't' => $bri->{reason} );
    };
    my $access_current;
    #$access_current = $rights_map{$rights_current} or do {
    #  print OUT_RPT "$print_id: can't map rights attribute $rights_current\n";
    #  $access_current = 'deny';
    #};
    $access_current = rights_map($rights_current);

    if ( $reason_current eq 'bib' and ($gfv_override or $rights_current ne $db_rights or $digitization_source ne $db_dig_source) ) {
      print RIGHTS "$mdp_id\t$rights_current\tbib\tjstever\t$digitization_source\n";
      $rights_out_cnt++;
      $update_date ne $current_date and do {
        print OUT_RPT "$print_id: bib rights update, 974 sub d changed from $update_date to $current_date\n";
        $update_date = $current_date;
        $f974->update('d' => $update_date);
      };
      ($new_rights == 0 and $digitization_source ne $db_dig_source) and do {
        print OUT_RPT "$print_id: bib rights update, dig source changed from $db_dig_source to $digitization_source\n";
      };
      $rights_debug and print DEBUG $br->debug_line($bib_info, $bri), "\n";
    }

    $compare_rights and do {	# if there exists bib rights in db
      # compare bib rights in db with bib rights from current record, report if different
      my $bib_access = rights_map($bib_rights);
      my $db_access = rights_map($db_rights);
      #if ($bib_rights ne $db_rights) {		# attribute changes
      if ($bib_access ne $db_access) {		# access changes
        if ($current_preferred_record_number eq '') { # already have preferred rec no from solr?
          $current_preferred_record_number = get_current_preferred_record_number($bib_key);
        }
        $rights_diff_cnt++;
        print RIGHTS_RPT join("\t", 
          $mdp_id,				# 1
          $bib_key,				# 2
#          $preferred_record_collection,		# 3	
          $current_preferred_record_number, 	# 3
          $preferred_record_number, 		# 4
          $db_access,				# 5
          $bib_access,				# 6
          "$db_rights/$db_reason",				# 7
          $bib_rights,				# 8
          $bib_info->{bib_fmt},			# 9
          $bri->{date_used},			# 10
          $description,				# 11
          $bri->{reason},			# 12
          $bib_info->{f008},			# 13
          $bib_info->{pub_place},		# 14
          $imprint,				# 15
          $title,				# 16
          $author,				# 17
          ), "\n";
        $rights_diff{"$db_rights -> $bib_rights"}++;
        $rights_diff{"$db_access -> $bib_access"}++;
      } else { 
        $rights_match_cnt++; 
      }
    };
  
    my $sdr_source = lc($collection);
    $source eq 'MiU' and $sdr_source = 'miu';
    $sdr_num = $sdr_list->{$sdr_source} or do {
      $no_sdr_num++;
      print OUT_RPT "$print_id: no sdr num for source $source ($sdr_source)\n"; 
      print STDERR "$print_id: no sdr num for source $source ($sdr_source)\n"; 
      print OUT_RPT Dumper($sdr_list);
    };

    $f974_cnt++;
    
    my $timestamp = $db_timestamp;
    $timestamp or $timestamp = $current_timestamp;

=begin
  TODO: remove all this
    if ($update_date < $update_cutoff) {
      $excluded_update_date++;
    } else {
      #$update_date{$update_date}++;
      my @hathi_lines = (
        $mdp_id,			# 1
        $access_current,		# 2
        $rights_current,		# 3
        $bib_key,			# 4
        $description,			# 5
        $source,			# 6
        $sdr_num,			# 7
        $oclc_num,			# 8
        $isbn,				# 9
        $issn,				# 10
        $lccn,				# 11
        $title,				# 12
        $imprint,			# 13
        $reason_current,		# 14
        $timestamp,			# 15
        $bib_info->{us_fed_doc},	# 16
        $bri->{date_used},		# 17
        $bib_info->{pub_place},		# 18
        $bib_info->{lang},		# 19
        $bib_info->{bib_fmt},		# 20
        $collection,			# 21
        $content_provider_code,		# 22
        $responsible_entity_code,	# 23
        $digitization_source,		# 24
        $access_profile,		# 25
        $author,			# 26
      ); 
      clean_fields(\@hathi_lines);
      print OUT_HATHI join("\t", @hathi_lines), "\n";
      $outcnt_hathi++;
    }
=cut
  }
  $bib->field('974') or do {	# make sure there are 974 fields
    print OUT_DELETE $bib_key, "\n";
    print OUT_RPT "$bib_key ($bibcnt): no unsuppressed 974 fields in record--not written\n";
    $no_974++;
    next RECORD;
  };
  print OUT_JSON MARC::Record::MiJ->to_mij($bib), "\n";
  $outcnt_json++;
  defined($htrc_output) and htrc_output($bib, $htrc_output);
}
  
print OUT_RPT "-----------------------------------------------\n";
print OUT_RPT "$bibcnt bib records read\n"; 
#print OUT_RPT "$dup_cid duplicate bib records for cid skipped\n"; 
print OUT_RPT "$bad_skipped_cnt bad bib records skipped\n"; 
print OUT_RPT "$bad_tab_newline_cnt bib records with tab or newline, fixed\n"; 
print OUT_RPT "$bad_out_cnt bad bib records written to bad file\n"; 
print OUT_RPT "$change_out_cnt changed bib records written to change file\n"; 
print OUT_RPT "$num_nbsp_records records with non-breaking spaces\n";
print OUT_RPT "$no_sdr_num no sdr number found in record\n";
print OUT_RPT "$suppressed_974 suppressed 974 fieids ignored\n";
print OUT_RPT "$no_974 no unsuppressed 974 fields in record, skipped\n";
print OUT_RPT "$no_resp_ent no responsible entity for collection\n";
print OUT_RPT "$no_cont_prov no content provider for collection\n";
print OUT_RPT "$no_access_profile can't determine access profile\n";
print OUT_RPT "$f974_cnt 974 fields processed\n";
print OUT_RPT "  $outcnt_hathi hathi records written\n";
print OUT_RPT "  $excluded_update_date hathi records excluded--update date\n";
print OUT_RPT "  $zia_cnt zephir ingested item records written\n";
print OUT_RPT "$outcnt_json json records written hathi catalog\n";
print OUT_RPT "-----------------------------------------------\n";
print OUT_RPT "$rights_cnt rights checked\n";
print OUT_RPT "$db_rights_cnt rights exist in rightsdb\n";
print OUT_RPT "  $db_bib_rights_cnt bib rights in rightsdb\n";
print OUT_RPT "  $db_non_bib_rights_cnt non-bib rights in rightsdb\n";
print OUT_RPT "  $gfv_override_cnt gfv rights changed to bib\n";
print OUT_RPT "$rights_out_cnt rights records written ($new_rights_cnt new, $rights_diff_cnt updates)\n";
print OUT_RPT "bib rights different: $rights_diff_cnt\n";
print OUT_RPT "bib rights match: $rights_match_cnt\n";
print OUT_RPT "$dollar_dup_cnt uc1 dollar barcode duplicates written\n";

print OUT_RPT "-----------------------------------------------\n";
print OUT_RPT "Rights changes\n";
foreach my $rights_change (sort keys %rights_diff) {
  print OUT_RPT "$rights_change: $rights_diff{$rights_change}\n";
}
print OUT_RPT "-----------------------------------------------\n";
#print OUT_RPT "Update dates\n";
#foreach my $update_date (sort keys %update_date) {
#  print OUT_RPT "$update_date: $update_date{$update_date} items\n";
#}
print OUT_RPT "-----------------------------------------------\n";
print OUT_RPT "Bib errors\n";
foreach my $bib_error (sort keys %bib_error) {
  print OUT_RPT "$bib_error: $bib_error{$bib_error}\n";
}

print OUT_RPT "DONE\n";
print STDERR  "DONE\n";

sub process_035 {
  # return oclc number and hash containing sdr numbers for each source
  my $bib = shift;
  my $bib_key = shift;
  my $oclc_num_hash = {};
  my $sdr_num_hash = {};
  my $sdr_num_with_prefix = '';
  my $oclc_num = '';
  my $source = '';
  #$sdr_num_hash->{'miu'} = $bib_key;	# always set this
  my ($sub_a, $prefix, $num);
  my $sysnum_separator = '';
  F035:foreach my $field ($bib->field('035')) {
    ($sub_a) = $field->as_string('a') or next F035; 
    ($sdr_num_with_prefix) = $sub_a =~ /^sdr-(.*)/ and do {
      $sdr_num_with_prefix =~ /^ia-/ and do {
        $sdr_num_with_prefix = substr($sdr_num_with_prefix, 3);
      };
      #print "sdr_num_with_prefix: $sdr_num_with_prefix\n";
      my $collection_match = 0;
      foreach my $collection (sort keys %$sdrnum_prefix_map) {
        my $prefix = $sdrnum_prefix_map->{$collection};
        #print "pattern: /^$prefix([.a-zA-Z0-9-]+)/\n";
        $sdr_num_with_prefix =~/^$prefix([.a-zA-Z0-9-]+)/ and do {
          $num = $1;
          $num =~ /^-loc/ and do {
            my $num_save = $num;
            $num = substr($num, 4);
          };
          #print "match, num is $num\n";
          $collection_match++;
          if ( exists($sdr_num_hash->{$collection}) ) { 
            $sdr_num_hash->{$collection} .= ',' . $num; 
          } else { 
            $sdr_num_hash->{$collection} = $num; 
          }
        };
      }
      $collection_match or do {
        print STDERR join("\t", $bib_key, $sdr_num_with_prefix, "no prefix match"), "\n";
      };
      next F035;
    };
    $sub_a =~ /(\(oco{0,1}lc\)|ocm|ocn)(\d+)/i and do {
      ($oclc_num) = $2;
      $oclc_num_hash->{$oclc_num + 0}++;
      $sub_a =~ /^(\(oco{0,1}lc\)|ocm|ocn)(\d+)/i or print OUT_RPT "$bib_key: 035 |a $sub_a, oclc number: $oclc_num\n";
      next F035;
    };
  }
  $oclc_num = join(',',sort(keys(%$oclc_num_hash)));
  #foreach my $source (sort keys %$sdr_num_hash)  { print "$source: $sdr_num_hash->{$source}\n";}
  return ($oclc_num, $sdr_num_hash);
}

sub get_bib_data {
  my $bib = shift;
  my $tag = shift; 
  my $i1 = '';
  my $i2 = '';
  length($tag) > 3 and do {
    length($tag) >= 4 and $i1 = substr($tag,3,1);
    length($tag) >= 5 and $i2 = substr($tag,4,1);
    $tag = substr($tag,0,3);
  };
  my $subfields = shift;
  my $data = [];
  my $field_string;
  TAG:foreach my $field ( $bib->field($tag) )  {
    $i1 ne '' and $i1 ne '#' and $field->indicator(1) != $i1 and next TAG;
    $i2 ne '' and $i2 ne '#' and $field->indicator(2) != $i2 and next TAG;
    $field_string = $field->as_string("'$subfields'") and push @$data, $field_string;
  }
  my $string = join(",", @$data);
  my $n = 0;
  $n = $string =~ s/\n/ /g and do {
    #print STDERR "$bib_key: get_bib_data, $n newline(s) stripped: '$string'\n";
  };
  $n = $string =~ s/\t/ <tab> /g and do {
    #print STDERR "$bib_key: get_bib_data, $n tab(s) stripped, tag=$tag, subfields=$subfields: '$string'\n";
  };
  $string =~ s/^\s*(.*?)\s*$/$1/;    # trim leading and trailing whitespace
  return $string;
}

sub GetRights {
  my $mdp_id = shift;
  #my ($rights, $reason, $source_code, $timestamp, $rights_note) = $rightsDB->GetRightsFromDB($mdp_id) or do {
  #  #print "$mdp_id:  can't get rights from rights db\n";
  #  return ('','','');
  #};
  #return ($rights, $reason, $timestamp);
  return $rightsDB->GetRightsFromDB($mdp_id); 
}

sub GetRightsDBM {
  my $full_id = shift;
  $full_id or return ();
  $RIGHTS{$full_id} or do {
    #print "$full_id: can't get rights from db file $rights_db_file\n";
    return ('','','');
  };
  return split("\t", $RIGHTS{$full_id});
}

sub filter_dollar_barcode {	 # check for duplication between uc1 BARCODE and $BARCODE
  my $f974 = shift;
  my $non_dollar_delete = {};
  my $all_ids = {};
  F974:foreach my $f974 (@$f974) {
    my $mdp_id = $f974->as_string('u') or next F974;
    my ($ns, $id) = split(/\./, $mdp_id);
    ($ns eq 'uc1') or next F974;
    $id =~ s/\$//g;
    my ($b_number) = $id =~ /^b(\d+)$/ or next F974;
    $b_number > 815188 and next F974;
    $all_ids->{$id} and $non_dollar_delete->{$id}++;
    $all_ids->{$id}++;
  }
  #foreach my $id (sort keys %$non_dollar_delete) { print "$id\n";}
  return $non_dollar_delete;
}

sub outputField {
  my $field = shift;
  my $newline = "\n";
  my $out = "";
  $out .= $field->tag()." ";
  if ($field->tag() lt '010') { $out .= "   ".$field->data; }
  else {
    $out .= $field->indicator(1).$field->indicator(2)." ";
    my @subfieldlist = $field->subfields();
    foreach my $sfl (@subfieldlist) {
      $out.="|".shift(@$sfl).shift(@$sfl);
    }
  }
  return $out;
}

sub getDate {
  my $inputDate = shift;
  if (!defined($inputDate)) { $inputDate = time; }
  my ($ss,$mm,$hh,$day,$mon,$yr,$wday,$yday,$isdst) = localtime($inputDate);
  my $year = $yr + 1900;
  $mon++;
  #my $fmtdate = sprintf("%4.4d-%2.2d-%2.2d",$year,$mon,$day);
  my $fmtdate = sprintf("%4.4d%2.2d%2.2d",$year,$mon,$day);
  return $fmtdate;
}

=begin
  # TODO: not necessary
sub write_hathi_header {

  print OUT_HATHI_HEADER join("\t", 
        "htid",				# 1
        "access",			# 2
        "rights",			# 3
        "ht_bib_key",			# 4
        "description",			# 5
        "source",			# 6
        "source_bib_num", 		# 7
        "oclc_num",			# 8
        "isbn",				# 9
        "issn",				# 10
        "lccn",				# 11
        "title",			# 12
        "imprint",			# 13
        "rights_reason_code",		# 14
        "rights_timestamp",		# 15
        "us_gov_doc_flag",		# 16
        "rights_date_used",		# 17
        "pub_place",			# 18
        "lang",				# 19
        "bib_fmt",			# 20
        "collection_code",		# 21
        "content_provider_code",	# 22
        "responsible_entity_code",	# 23
        "digitization_agent_code",	# 24
        "access_profile_code",		# 25
        "author",			# 26
  ), "\n";
}
=cut

=begin
sub clean_fields {
  my $fields = shift;
  my $field_count = 0;
  foreach my $field (@$fields) {
    $field_count++;
    $field =~ /\t/ and do {
      #print STDERR "$$fields[0]($$fields[3]): tab in field $field_count: $field\n";
      $field =~ s/\t/ /g;
    };
  }
  return;
}
=cut

sub clean_json_line {
  my $json = shift;
  my $pat1 = qr/[\t\n]/o;
  my $pat2 = qr/\xa0/o;         # non-breaking space

  my $h = $jp->decode($json);
  my $recID = '';
  my $changes = 0;
  $changes += ( $h->{'leader'} =~ s/$pat1//g );
  $changes += ( $h->{'leader'} =~ s/$pat2/ /g );
  foreach my $field (@{$h->{fields}}) {
    my ($tag, $val)  = each %$field; # just get the tag and value
    $tag eq '001' and $recID = $field->{$tag};
    my $val = (values %$field)[0];
    if (ref($val)) { # If it's a variable field
      $val->{ind1} = ' ' unless ($val->{ind1} =~ m/[0-9 ]/o);
      $val->{ind2} = ' ' unless ($val->{ind1} =~ m/[0-9 ]/o);
      foreach my $sf (@{$val->{subfields}}) {
        my ($code, $sfval)  = each %$sf; # just get the code and value
        $changes += ( $sf->{$code} =~ s/$pat1//g );
        $changes += ( $sf->{$code} =~ s/$pat2/ /g );
        unless ($sf->{$code} eq $sfval) {
          #print STDERR "$recID: $tag field, changed '$sfval' into '", $sf->{$code}, "'\n";
        }
        $code =~ /[^a-zA-Z0-9%*?@]/ and do {
          #print STDERR "$recID: $tag field, invalid subfield code $code, changed to 'a'\n";
          $code = 'a';
          $sf = {$code => $sfval};
          $changes++;
        };
      }
    } else {
      $changes += ( $field->{$tag} =~ s/$pat1//g );
      $changes += ( $field->{$tag} =~ s/$pat2/ /g );
    }
  }
  $changes and return ($jp->encode($h), $changes);
  return ($json, $changes);
}

sub rights_map {
  my $attr = shift;
  $attr =~ /^(pdus$|pd$|world|ic-world|cc|und-world)/ and return 'allow';
  return 'deny';
}

sub check_bib {
  my $bib = shift;
  my $bib_key = shift;
  # get source of record from cat field
  my $cat_field = $bib->field('CAT') or do {
    print STDERR "$bib_key (check_bib): no cat field in record\n";
    return;
  };
  my $bib_source = $cat_field->as_string('a') or do { 
    print STDERR "$bib_key (check_bib): no subfield a in cat field in record\n";
    return;
  };
  my $ldr = $bib->leader() or bib_error($bib_source, $bib_key, $bib, "no leader");
  $ldr and do {
    length($ldr) == 24 or bib_error($bib_source, $bib_key, $bib, "invalid ldr length");
  };

  substr($ldr, 5, 1) =~ /d/i and do {
    bib_error($bib_source, $bib_key, $bib, "leader set for delete (recstatus is 'd'), changed to 'c'");
    substr($ldr, 5, 1) = 'c';
    $bib->leader($ldr); 
  }; 
  my $f008 = $bib->field('008') or bib_error($bib_source, $bib_key, $bib, "no 008 field");
  $f008 and do {
    my $f008_data = $f008->as_string();
    length($f008_data) == 40 or do {
      bib_error($bib_source, $bib_key, $bib, "invalid 008 length: " . length($f008_data));
    };
  };
  my @f245 = $bib->field('245') or bib_error($bib_source, $bib_key, $bib, "no 245 field in record");
  if (scalar @f245 == 1) {
    my $f245_data = $f245[0]->as_string('ak') or bib_error($bib_source, $bib_key, $bib, "no subfield ak in 245 field");
  } else {
    bib_error($bib_source, $bib_key, $bib, "multiple 245 fields in record"); 
  }
  foreach my $field ($bib->field('00.')) {
    my $field_str = $field->as_string();
    my $tag = $field->tag();
    $field_str =~ s/[[:^ascii:]]/ /g and do {
      bib_error($bib_source, $bib_key, $bib, "$tag contains non-ascii characters, changed to blank");
      $field->replace_with(MARC::Field->new($tag,$field_str));
    };
  }
} 
 
sub bib_error {
  my $bib_source = shift;
  my $bib_key = shift;
  my $bib = shift;
  my $error_msg = shift;
  $bib_error{join(":", $bib_source, $error_msg)}++;
  print OUT_RPT "$bib_source ($bib_key): $error_msg\n";
  $bib_source =~  /MIU/i and do {
    print OUT_RPT "$bib_key: MIU error $error_msg\n";
    print BAD $bib_line, "\n";
    $bad_out_cnt++;
  };
}

sub get_current_preferred_record_number {
  my $bib_key = shift;
  my $hathi_bib_record = get_hathi_bib_record_solr($bib_key) or do {
    print STDERR "$bib_key: can't get hathi bib record\n";
    return '';
  };
  my $hol_field = $hathi_bib_record->field('HOL') or do {
    print STDERR "$bib_key: no HOL field in hathi bib record\n";
    return '';
  };
  return $hol_field->as_string('0');
}

sub get_hathi_bib_record_solr {
  my $hathi_bib_key = shift;
  #my $select = 'http://solr-sdr-catalog.umdl.umich.edu:9033/catalog/select';
  my $select = 'http://solr-sdr-catalog.umdl.umich.edu:9033/solr/catalog/select';
  my $q_orig = "id:$hathi_bib_key";
  my $fields = 'fullrecord';
  my $pagesize = 1;
  my $q = uri_escape($q_orig);
  my $url = "$select?q=$q&rows=$pagesize&start=0&wt=json&json.nl=arrarr&fl=$fields";
  my $result_raw = get($url) or do {
    print STDERR "$hathi_bib_key: no solr record, url is $url\n";
    return 0;
  };
  my $result;
  eval { $result = decode_json($result_raw); };
  $@ and do {
    print STDERR "$hathi_bib_key: error decoding json:  $@\n";
    print STDERR "raw result: $result_raw\n";
    return 0;
  };
  my $total = $result->{response}{numFound};
  $total != 1 and return 0;
  my $bib_record;
  my $bib_xml = $result->{response}{docs}[0]{fullrecord};
  ($bib_xml =~ tr/\xA0/ /) and do {
    #print STDERR "$hathi_bib_key: non-breaking space(s) translated to space\n";
  };
  eval { $bib_record = MARC::Record->new_from_xml($bib_xml); };
  $@ and do {
    print STDERR "problem processing marc xml\n";
    warn $@;
    print STDERR "$bib_xml\n";
    return 0;
  };
  return $bib_record;
}

sub getCollectionTable {
  my $rightsdb = shift;
  my $table_name = "ht_collections";
  my $hash = {};
  my $ref;
  $ref = $rightsdb->{sdr_dbh}->selectall_arrayref( "SELECT collection, name, inst_id FROM ht_repository.ht_collections, ht_repository.ht_institutions where content_provider_cluster = inst_id");
  foreach my $row ( @{$ref} ) {
    my $collection = $$row[0];
    my $content_provider = $$row[1];
    my $content_provider_code = $$row[2];
    $content_provider =~ s/&amp;/&/g;
    $hash->{$collection} = {
      'collection' => $collection,
      'content_provider' => $content_provider,
      'content_provider_code' => $content_provider_code,
    };
  }
  $ref = $rightsdb->{sdr_dbh}->selectall_arrayref( "SELECT collection, name, inst_id FROM ht_repository.ht_collections, ht_repository.ht_institutions where responsible_entity = inst_id");
  foreach my $row ( @{$ref} ) {
    my $collection = $$row[0];
    my $responsible_entity = $$row[1];
    my $responsible_entity_code = $$row[2];
    $responsible_entity =~ s/&amp;/&/g;
    exists $hash->{$collection} or $hash->{$collection} = { 'collection' => $collection };
    $hash->{$collection}->{responsible_entity} = $responsible_entity;
    $hash->{$collection}->{responsible_entity_code} = $responsible_entity_code;
  }
  return $hash;
}

sub setup_htrc_output {
  # set up a hash of filenhandles and counters for htrc output files
  my $htrc_out_basename = shift;
  my $htrc_output = {};
  foreach my $name ('pd_google', 'pd_open_access', 'ic', 'restricted') {
    print STDERR $htrc_out_basename . "_" . $name . ".jsonl";
    $htrc_output->{$name}{'fh'} = new FileHandle ">${htrc_out_basename}_$name.jsonl" or die "can't create filehandle for $name: $!\n";
    binmode($htrc_output->{$name}{'fh'});
    $htrc_output->{$name}{'count'} = 0;
  }
  $htrc_output->{pd_attr_list} = {    # (1,7,9,10,11,12,13,14,15,17,18,20,21,22,23,24,25)
    'pd' => 1,
    'ic-world' => 1,
    'und-world' => 1,
    'pdus' => 1,
    'cc-by-3.0' => 1,
    'cc-by-nd-3.0' => 1,
    'cc-by-nc-nd-3.0' => 1,
    'cc-by-nc-3.0' => 1,
    'cc-by-nc-sa-3.0' => 1,
    'cc-by-sa-3.0' => 1,
    'cc-zero' => 1,
    'cc-by-4.0' => 1,
    'cc-by-nd-4.0' => 1,
    'cc-by-nc-nd-4.0' => 1,
    'cc-by-nc-4.0' => 1,
    'cc-by-nc-sa-4.0' => 1,
    'cc-by-sa-4.0' => 1,
  };

  return $htrc_output;
}

sub htrc_output {
  my $bib = shift;
  my $output = shift;
  my $recID = $bib->field('001')->as_string();
  my $records_written = 0;

  my @f974 = $bib->field('974');
  scalar @f974 or return 0;
  foreach my $field (@f974) {
    $bib->delete_field($field);
  }

  my $field_fmt;
  $field_fmt = $bib->field('FMT') and $field_fmt->{_tag} = "970";

  foreach my $field ($bib->field("CID|HOL|DAT|FMT|HOL|CAT|COM")) {
    $bib->delete_field($field);
  }

  F974:foreach my $field (@f974) {
    my $ht_id = $field->as_string('u');
    my $rights = $field->as_string('r');
    my ($db_rights, $db_reason, $db_dig_source, $db_timestamp, $db_rights_note, $db_access_profile) = &$rights_sub($ht_id);
    $rights ne $db_rights and do {
      print "$ht_id: rights mismatch, catalog: $rights, rightsdb: $db_rights, update date: $db_timestamp\n";
      $field->update('r' => $db_rights);
      $rights = $db_rights;
    };
    $field->delete_subfield(code => 't');
    $field->add_subfields( 'a' => $db_access_profile );
    #$field->add_subfields( 'q' => $db_reason ); # (not needed, adding reason in regular output--tlp )
    $bib->append_fields($field);
    
    write_htrc_record($bib, $rights, $db_access_profile, $output) or do {
      print "ht_id: can't write htrc record\n";
      $bib->delete_field($field);
      next F974;
    };
    $bib->delete_field($field);
    $records_written++;
  }
  return $records_written;
}

sub write_htrc_record {
  my $bib = shift;
  my $rights = shift;
  my $access_profile = shift;
  my $output = shift;
  my $filename = '';
  SET_FILENAME: {
    $output->{pd_attr_list}{$rights} and $access_profile eq 'google' and $filename = 'pd_google' and last SET_FILENAME;
    $output->{pd_attr_list}{$rights} and $access_profile eq 'open' and $filename = 'pd_open_access' and last SET_FILENAME;
    $access_profile =~ /^(open|google)$/ and $filename = 'ic' and last SET_FILENAME;
    $access_profile =~ /^page/ and $filename = 'restricted' and last SET_FILENAME;
    print "can't set filename for rights = $rights and access_profile = $access_profile\n";
    return 0;
  }
  my $fh = $output->{$filename}{'fh'};
  print $fh MARC::Record::MiJ->to_mij($bib), "\n";
  $output->{$filename}{'count'}++;
  return 1;
}
1;
