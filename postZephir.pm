#!/usr/bin/env perl

package postZephir;

use open qw( :encoding(UTF-8) :std );
use strict;
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

use ProgressTracker;

my $tracker = ProgressTracker->new(report_interval => 10000);

# lifted from main because they need to be global (:
my $jp = new JSON::XS;
$jp->utf8(1);
#$jp->pretty(0);
my %RIGHTS;
my $rightsDB = rightsDB->new();
my %bib_error = ();
my $bib_line;
my $bad_out_cnt = 0;
my $rights_sub = '';

sub main {
  my $prgname = basename($0);
  select STDERR; $| = 1;
  select STDOUT; $| = 1;

  sub usage {
    my $msg = shift;
    $msg and $msg = " ($msg)";
    return"usage: $prgname -i infile -o outbase [-f rights_db_file][-r rights_output_file [-d (rights debug file wanted]][-z zephir_ingested_items_file_wanted]$msg\n";
  };

  our($opt_i, $opt_o, $opt_r, $opt_f, $opt_d, $opt_z);
  getopts('i:o:r:f:u:z:d');

  $opt_i or die usage("no input file specified");
  $opt_o or die usage("no output file specified");
  my $infile = $opt_i; # ht_bib_export_incr_<sephir_date>.json.gz
  my $outbase = $opt_o; #typically zephir_upd_<yesterday>
  my $out_hathi = $outbase . "_hathi.txt";
  my $out_json = $outbase . ".json";
  my $out_report = $outbase . "_rpt.txt";
  my $out_dollar_dup = $outbase . "_dollar_dup.txt";
  my $out_delete = $outbase . "_delete.txt";

  # ultimately this ends up as /htapps/babel/feed/var/bibrecords/zephir_ingested_items.txt.gz 
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

  my $zia_output = 0;
  $opt_z and do {
    $zia_output++;
    open(ZIA,">$out_zia") or die "can't open $out_zia for output: $!\n";
  };

  my %rights_diff = ();
   
  my $current_timestamp = `date '+%Y-%m-%d %H:%M:%S'`;
  chomp $current_timestamp;
  my $current_date = getDate(time() - 86400); 	# yesterday is the date the zephir file was created

  print "Input file is $infile\n";

  my $infile_open = $infile;
  $infile =~ /\.gz$/ and do {
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

  open(OUT_JSON,">$out_json") or die "can't open $out_json for output: $!\n";
  #binmode(OUT_JSON, ":encoding(UTF-8)");
  binmode(OUT_JSON);
  open(OUT_RPT,">$out_report") or die "can't open $out_report for output: $!\n";
  select OUT_RPT; $| = 1;
  select STDOUT;
  open(OUT_DOLLAR_DUP,">$out_dollar_dup") or die "can't open $out_dollar_dup for output: $!\n";
  open(OUT_DELETE,">$out_delete") or die "can't open $out_delete for output: $!\n";

  print OUT_RPT "processing file $infile\n";

  my $rightsDB = rightsDB->new();
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
  my $f974_cnt = 0;
  my $outcnt_json = 0;
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
  my ($lccn, $isbn, $issn, $title, $author, $imprint, $oclc_num);
  my ($htid, $rights, $description, $sub_library, $collection, $source, $update_date); 
  #my %update_date = ();
  my $rights_diff_cnt = 0;
  my $rights_match_cnt = 0;


  my $bib;

  my $bad_skipped_cnt = 0;
  my $bad_out_cnt = 0;
  my $change_out_cnt = 0;

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


  my $bib_line;

  RECORD:while($bib_line = <IN> ) {
    $tracker->inc();
    $exit and do {
      print OUT_RPT "exitting due to signal\n";
      last RECORD;
    };
    $bibcnt++;
    $bibcnt % 1000 == 0 and print STDERR "processing bib record $bibcnt\n";
    chomp($bib_line);
    my $save_bib_line = $bib_line;
    my $changes = 0;

    ##############################
    # Cleaning the json and checking if it's ok
    eval {
      ($bib_line, $changes)  = clean_json_line($bib_line);
      $bib = MARC::Record::MiJ->new($bib_line);
    };
    # $@ is the perl syntax error message from the last eval command
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
      print OUT_RPT "$bib_key($bibcnt): $changes characters stripped/blanked from json line\n";
      print CHANGE $save_bib_line, "\n";
      $change_out_cnt++;
    };

    ##############################
    # Collect a bunch of fields from the MARC
    check_bib($bib, $bib_key);
    $bib_info = $br->get_bib_info($bib, $bib_key) or print OUT_RPT "$bib_key: can't get bib info\n";
    $oclc_num = process_035($bib, $bib_key);
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

    # Get list of duplicate uc1 barcode ids that need to be deleted
    my $uc1_delete = filter_dollar_barcode(\@f974);	# check for duplication between uc1 BARCODE and $BARCODE

    #######################
    # Process each 974 in sequence
    F974:foreach my $f974 (@f974) {
      my ($print_id, $ns, $id);
      $htid = $f974->as_string('u') or do {
        print OUT_RPT "$bib_key ($bibcnt): no subfield u for 974 field\n";
        next F974;
      };
      ($ns, $id) = split(/\./, $htid);

      # actually delete duplicate uc1 NON-dollar barcodes
      $uc1_delete->{$id} and do {
        $bib->delete_field($f974);
        print OUT_RPT "$htid: non-dollar barcode uc1 $id with dollar version deleted\n";
        print OUT_DOLLAR_DUP "$htid\n";
        $dollar_dup_cnt++;
        next F974;
      };

      # Item info
      $print_id = "$bib_key:$htid ($bibcnt)";
      $description = $f974->as_string('z');
      my $digitization_source = $f974->as_string('s');
      $source = $f974->as_string('b');
      $collection = $f974->as_string('c');
      $update_date = $f974->as_string('d');

      # We want to generate a zia file. 
      # Get the IA id from 974, subfield 8
      $zia_output and do {
        my $ia_id = $f974->as_string('8');
        print ZIA join("\t", $htid, $source, $collection, $digitization_source, $ia_id), "\n";
        $zia_cnt++;
      };

      ######################### 
      # rights processing

      # determine rights from current bib/item info
      my $bri = $br->get_bib_rights_info($htid, $bib_info, $description);
      my $bib_rights = $bri->{'attr'};
      my $rights_current = $bib_rights; 	# set to newly-determined bib rights
      my $reason_current = 'bib'; 	# set reason to bib for new records
      $bri->{date_used} and $bri->{date_used} ne '9999' and $f974->update('y' => $bri->{date_used});
      
      # check for existing rights in rights db
      my ($db_rights, $db_reason, $db_dig_source, $db_timestamp, $db_rights_note, $db_access_profile) = &$rights_sub($htid);
      $rights_cnt++;

      my $compare_rights = 0; # boolean
      my $new_rights = 0; # boolean
      my $gfv_override = 0; # boolean
      my $access_profile = $db_access_profile;
      if ($db_rights eq '') {	# not in rights db
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
      $f974->update('q' => $reason_current );
      $reason_current eq 'bib' and do {
        $f974->update( 't' => $bri->{reason} );
      };
      my $access_current;
      $access_current = rights_map($rights_current);

      ################
      # We need this in the rights file if we changed gfv to bib, or bib rights calc doesnt agree with bib rights in db, or digitization sources dont match 
      if ( $reason_current eq 'bib' and ($gfv_override or $rights_current ne $db_rights or $digitization_source ne $db_dig_source) ) {
        print RIGHTS "$htid\t$rights_current\tbib\tbibrights\t$digitization_source\n";
        $rights_out_cnt++;
        $update_date ne $current_date and do {
          print OUT_RPT "$print_id: bib rights update, 974 sub d changed from $update_date to $current_date\n";

          ############
          # Change date in 974d
          $update_date = $current_date;
          $f974->update('d' => $update_date);
        };
        ($new_rights == 0 and $digitization_source ne $db_dig_source) and do {
          print OUT_RPT "$print_id: bib rights update, dig source changed from $db_dig_source to $digitization_source\n";
        };
        $rights_debug and print DEBUG $br->debug_line($bib_info, $bri), "\n";
      }
      
      #####################  
      # compare bib rights in db with bib rights from current record, report if different
      $compare_rights and do {	# if there exists bib rights in db
        my $bib_access = rights_map($bib_rights);
        my $db_access = rights_map($db_rights);
        #if ($bib_rights ne $db_rights) {		# attribute changes
        if ($bib_access ne $db_access) {		# access changes
          $rights_diff_cnt++;
          print RIGHTS_RPT join("\t", 
            $htid,				# 1
            $bib_key,				# 2
  #          $preferred_record_collection,		# 3	
  #          $current_preferred_record_number, 	# 3
            'current preferred record number omitted', # 3
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
    
      $f974_cnt++;
      
      my $timestamp = $db_timestamp;
      $timestamp or $timestamp = $current_timestamp;

    } # Foreach 974
    $bib->field('974') or do {	# make sure there are 974 fields
      print OUT_DELETE $bib_key, "\n";
      print OUT_RPT "$bib_key ($bibcnt): no unsuppressed 974 fields in record--not written\n";
      $no_974++;
      next RECORD;
    };
    print OUT_JSON MARC::Record::MiJ->to_mij($bib), "\n";
    $outcnt_json++;
  }
    
  # TODO push all these metrics in prometheus
  print OUT_RPT "-----------------------------------------------\n";
  print OUT_RPT "$bibcnt bib records read\n"; 
  #print OUT_RPT "$dup_cid duplicate bib records for cid skipped\n"; 
  print OUT_RPT "$bad_skipped_cnt bad bib records skipped\n"; 
  print OUT_RPT "$bad_out_cnt bad bib records written to bad file\n"; 
  print OUT_RPT "$change_out_cnt changed bib records written to change file\n"; 
  print OUT_RPT "$suppressed_974 suppressed 974 fieids ignored\n";
  print OUT_RPT "$no_974 no unsuppressed 974 fields in record, skipped\n";
  print OUT_RPT "$f974_cnt 974 fields processed\n";
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
  $tracker->finalize;
}

# args: bib record, bib key (001)
sub process_035 {
  # return oclc number
  my $bib = shift;
  my $bib_key = shift;
  my $oclc_num_hash = {};
  my $oclc_num = '';
  my $source = '';
  my ($sub_a, $prefix, $num);
  my $sysnum_separator = '';
  F035:foreach my $field ($bib->field('035')) {
    ($sub_a) = $field->as_string('a') or next F035; 
    $sub_a =~ /(\(oco{0,1}lc\)|ocm|ocn)(\d+)/i and do {
      ($oclc_num) = $2;
      $oclc_num_hash->{$oclc_num + 0}++;
      $sub_a =~ /^(\(oco{0,1}lc\)|ocm|ocn)(\d+)/i or print OUT_RPT "$bib_key: 035 |a $sub_a, oclc number: $oclc_num\n";
      next F035;
    };
  }
  $oclc_num = join(',',sort(keys(%$oclc_num_hash)));
  return $oclc_num;
}

# args: bib record, marc tag, subfields
sub get_bib_data {
  my $bib = shift;
  my $tag = shift; 
  # indicator1
  my $i1 = '';
  # indicator2
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
  my $htid = shift;
  #my ($rights, $reason, $source_code, $timestamp, $rights_note)
  return $rightsDB->GetRightsFromDB($htid); 
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

# Returns hash of non-dollar delete ids to the number of times seen
sub filter_dollar_barcode {	 # check for duplication between uc1 BARCODE and $BARCODE
  my $f974 = shift;
  my $non_dollar_delete = {};
  my $all_ids = {};
  F974:foreach my $f974 (@$f974) {
    my $htid = $f974->as_string('u') or next F974;
    my ($ns, $id) = split(/\./, $htid);
    ($ns eq 'uc1') or next F974; # only uc1 is effected
    $id =~ s/\$//g; # delete the dollar
    my ($b_number) = $id =~ /^b(\d+)$/ or next F974;
    $b_number > 815188 and next F974; # for some reason only small ids are effected
    # we have already seen this id
    $all_ids->{$id} and $non_dollar_delete->{$id}++;
    $all_ids->{$id}++;
  }
  #foreach my $id (sort keys %$non_dollar_delete) { print "$id\n";}
  return $non_dollar_delete;
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

# get source of record from cat field
sub get_bib_source {
  my $bib = shift;
  my $bib_key = shift;
  
  my $cat_field = $bib->field('CAT') or do {
    print STDERR "$bib_key (check_bib): no cat field in record\n";
    return;
  };

  my $bib_source = $cat_field->as_string('a') or do { 
    print STDERR "$bib_key (check_bib): no subfield a in cat field in record\n";
    return;
  };

  return $bib_source;
}

sub check_bib_leader {
  my $bib = shift;
  my $bib_key = shift;
  my $bib_source = shift;

  my $ldr = $bib->leader() or bib_error($bib_source, $bib_key, $bib, "no leader");

  # leader has the wrong length
  $ldr and do {
    length($ldr) == 24 or bib_error($bib_source, $bib_key, $bib, "invalid ldr length");
  };
  # leader has 'delete' set, fix it
  substr($ldr, 5, 1) =~ /d/i and do {
    bib_error($bib_source, $bib_key, $bib, "leader set for delete (recstatus is 'd'), changed to 'c'");
    substr($ldr, 5, 1) = 'c';
    $bib->leader($ldr); 
  }; 
}

sub check_f008 {
  my $bib = shift;
  my $bib_key = shift;
  my $bib_source = shift;

  my $f008 = $bib->field('008') or bib_error($bib_source, $bib_key, $bib, "no 008 field");
  $f008 and do {
    my $f008_data = $f008->as_string();
    length($f008_data) == 40 or do {
      bib_error($bib_source, $bib_key, $bib, "invalid 008 length: " . length($f008_data));
    };
  };
}

sub check_f245 {
  my $bib = shift;
  my $bib_key = shift;
  my $bib_source = shift;

  my @f245 = $bib->field('245') or bib_error($bib_source, $bib_key, $bib, "no 245 field in record");
  if (scalar @f245 == 1) {
    my $f245_data = $f245[0]->as_string('ak') or bib_error($bib_source, $bib_key, $bib, "no subfield ak in 245 field");
  } elsif (scalar @f245 > 1) {
    bib_error($bib_source, $bib_key, $bib, "multiple 245 fields in record"); 
  }
}

# Replaces non-ascii in 00* field with blank
sub remove_nonascii_from_control_fields {
  my $bib = shift;
  my $bib_key = shift;
  my $bib_source = shift;

  foreach my $field ($bib->field('00.')) {
    my $field_str = $field->as_string();
    my $tag = $field->tag();
    $field_str =~ s/[[:^ascii:]]/ /g and do {
      bib_error($bib_source, $bib_key, $bib, "$tag contains non-ascii characters, changed to blank");
      $field->replace_with(MARC::Field->new($tag,$field_str));
    };
  }
}
  
sub check_bib {
  my $bib = shift;
  my $bib_key = shift;
  
  my $bib_source = get_bib_source($bib, $bib_key);

  check_bib_leader($bib, $bib_key, $bib_source);

  check_f008($bib, $bib_key, $bib_source);

  check_f245($bib, $bib_key, $bib_source);

  remove_nonascii_from_control_fields($bib, $bib_key, $bib_source);
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

sub get_bib_errors {
    return \%bib_error;
}

sub load_prefix_map {
  open( PREFIXES, shift);
  my $mapping = {};
  foreach my $line (<PREFIXES>) {
      chomp($line);
      my @rec = split(/\t/, $line);
      $mapping->{$rec[0]} = $rec[1];
  };
  return $mapping;
}

1;

main unless caller;
