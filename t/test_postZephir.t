#!/usr/bin/env perl

use strict;
use warnings;
use File::Basename;
BEGIN {push @INC, dirname(__FILE__)};

use Fcntl;
use File::Slurp;
use Test::More;
use Test::Output;
use Data::Dumper;
use DB_File;

BEGIN {push @INC, dirname(__FILE__) . "/.."};
use postZephir;


my $bib = MARC::Record::MiJ->new(read_file("t/fixtures/test_record.json"));
my $bib_key = $bib->field('001')->as_string();
is($bib_key, "000000012", 'bib key extraction');
my ($oclc_num, $sdr_num_hash) = postZephir::process_035($bib, $bib_key);
is($oclc_num, "604", 'oclc number extraction');


# SDR Nums were used for the Hathifiles, and a report that no one actually reads
subtest "sdr_nums" => sub {
  my %expected_sdr_nums = (
            'nbb' => '.990000000120106381',
            'umlaw' => '.990000000120106381',
            'nrlf' => 'GLAD84523971-B',
            'umprivate' => '.990000000120106381',
            'umbus' => '.990000000120106381',
            'umdcmp' => '.990000000120106381',
            'gwla' => '.990000000120106381',
            'umdb' => '.990000000120106381',
            'inrlf' => 'GLAD84523971-B'
          );
  is($sdr_num_hash->{'nbb'}, $expected_sdr_nums{'nbb'}, 'sdr num hash');
  is($sdr_num_hash->{'umlaw'}, $expected_sdr_nums{'umlaw'}, 'sdr num hash');
  is($sdr_num_hash->{'nrlf'}, $expected_sdr_nums{'nrlf'}, 'sdr num hash');
  is($sdr_num_hash->{'umprivate'}, $expected_sdr_nums{'umprivate'}, 'sdr num hash');
  is($sdr_num_hash->{'umbus'}, $expected_sdr_nums{'umbus'}, 'sdr num hash');
};

subtest "get_bib_data()" => sub {
  # pulls strings from specified MARC field
  my $title = postZephir::get_bib_data($bib, '245', 'abc');
  is($title, 'MMPI; research developments and clinical applications. Edited by James Neal Butcher', 'title');
  # indicators matter
  $title = postZephir::get_bib_data($bib, '24510', 'abc');
  is($title, 'MMPI; research developments and clinical applications. Edited by James Neal Butcher', 'title');
  $title = postZephir::get_bib_data($bib, '24501', 'abc');
  is($title, '', 'title');
};

# GetRights()

# GetRightsDBM()

subtest "filter_dollar_barcode()" => sub {
  # Checks for duplication between uc1 BARCODE and $BARCODE
  # This may no longer be a "thing"
  my $dollar_bib = MARC::Record::MiJ->new(read_file("t/fixtures/dollar_barcode_record.json"));
  my @f974 = $dollar_bib->field('974');
  is(scalar @f974, 3, "dollar bib starts with three 974s");
  my $deleted = postZephir::filter_dollar_barcode(\@f974);
  is(scalar keys %$deleted, 1, "returns hash of ids to remove => counts");
  is($deleted->{'b444627'}, 1, "duplicate barcode is in filter_dollar_barcode hash");
};

subtest "getDate()" => sub {
  # Formats the given seconds since epoch as YYYY-MM-DD
  like(postZephir::getDate(), qr/20\d\d\d\d\d\d/, "Formats date");
  my $yesterday = 1654457620; # 2022-06-05
  is(postZephir::getDate($yesterday), "20220605", "Formats date");
};

# clean_json_line()

subtest "rights_map()" => sub {
  # maps certain rights values to "allow" or deny"
  my @allow_attrs = qw(pd pdus cc-by-3.0 cc-by-nd-3.0 cc-by-nc-nd-3.0 cc-by-nc-3.0 cc-by-nc-sa-3.0 cc-by-sa-3.0 cc-zero cc-by-4.0 cc-by-nd-4.0 cc-by-nc-nd-4.0 cc-by-nc-4.0 cc-by-nc-sa-4.0 cc-by-sa-4.0 ic-world und-world);
  foreach my $attr (@allow_attrs) {
    is(postZephir::rights_map($attr), "allow", "rights_map => allow");
  }
  my @deny_attrs = qw(ic op orph und nobody orphcand icus pd-pvt supp);
  foreach my $attr (@deny_attrs) {
    is(postZephir::rights_map($attr), "deny", "rights_map => deny");
  }
};

subtest "check_bib()" => sub {
  # Takes bib_record and bib_key
  my $bib_source = $bib->field('CAT')->as_string('a');
  subtest "1. errors and returns if no CAT field" => sub {
    my $catless = $bib->clone();
    $catless->delete_field($catless->field('CAT'));
    stderr_is {postZephir::check_bib($catless, $bib_key) } "$bib_key (check_bib): no cat field in record\n", "no cat";
  };

  subtest "#2. errors and returns if no CAT subfield a" => sub {
    my $catAless = $bib->clone();
    $catAless->field('CAT')->delete_subfield(code => 'a');
    stderr_is {postZephir::check_bib($catAless, $bib_key) } "$bib_key (check_bib): no subfield a in cat field in record\n", "no CAT subfield a";
  };

  subtest "#3. reports bib error if no leader" => sub {
    my $leaderless = $bib->clone();
    #$leaderless->delete_fields('leader');
    delete($leaderless->{_leader});
    postZephir::check_bib($leaderless);
    is(postZephir::get_bib_errors->{"$bib_source:no leader"}, 1, "errors without leader");
  };

  subtest "#4. reports bib error leader is invalid length" => sub {
    my $shortleader = $bib->clone();
    $shortleader->leader('abc');
    postZephir::check_bib($shortleader);
    is(postZephir::get_bib_errors->{"$bib_source:invalid ldr length"}, 1, "invalid ldr length");
  };

  subtest "#5. fixes leader if it has recstatus delete and reports bib_error" => sub {
    my $leaderfix = $bib->clone();
    my $bad_ldr = $leaderfix->leader;
    substr($bad_ldr, 5, 1) = 'd';
    $leaderfix->leader($bad_ldr);
    postZephir::check_bib($leaderfix);
    is(substr($leaderfix->leader, 5, 1), "c", "fix bad leader");
    is(postZephir::get_bib_errors->{"$bib_source:leader set for delete (recstatus is 'd'), changed to 'c'"}, 1, "fix bad leader");
  };

  subtest "#6. reports bib_error if no 008" => sub {
    my $f008less = $bib->clone();
    $f008less->delete_field($f008less->field('008'));
    postZephir::check_bib($f008less);
    is(postZephir::get_bib_errors->{"$bib_source:no 008 field"}, 1, "no 008 field");
  };

  subtest "#7. reports bib_error if 008 is invalid length" => sub {
    my $f008invalid = $bib->clone();
    $f008invalid->field('008')->replace_with(MARC::Field->new('008', 'invalid'));
    postZephir::check_bib($f008invalid);
    is(postZephir::get_bib_errors->{"$bib_source:invalid 008 length: 7"}, 1, "invalid 008 field");
  };

  subtest "#8. reports bib_error if no 245" => sub {
    my $f245less = $bib->clone();
    $f245less->delete_field($f245less->field('245'));
    postZephir::check_bib($f245less);
    is(postZephir::get_bib_errors->{"$bib_source:no 245 field in record"}, 1, "no 245");
  };

  subtest "#9. reports bib_error if 245 does not have subfields ak" => sub {
    my $f245akless = $bib->clone();
    $f245akless->field('245')->delete_subfield(code => 'a');
    postZephir::check_bib($f245akless);
    is(postZephir::get_bib_errors->{"$bib_source:no subfield ak in 245 field"}, 1, "no 245ak");
  };

  subtest "#10. reports bib_error if multiple 245s" => sub {
    my $f245multi = $bib->clone();
    $f245multi->add_fields($f245multi->field('245')->clone());
    postZephir::check_bib($f245multi);
    is(postZephir::get_bib_errors->{"$bib_source:multiple 245 fields in record"}, 1, "multi 245s");
  };

  subtest "#11. changes non-ascii in 00* fields to blank, reports bib_error" => sub {
    my $nonascii = $bib->clone();
    $nonascii->field('008')->replace_with(MARC::Field->new('008', 'non_こんにちは_ascii'));
    postZephir::check_bib($nonascii);
    is(postZephir::get_bib_errors->{"$bib_source:008 contains non-ascii characters, changed to blank"}, 1, "blanks non-ascii in 00* fields");
    is($nonascii->field('008')->as_string, 'non_               _ascii', "blanks non-ascii in 00* fields");
  };
};

subtest "load_prefix_map" => sub {
  my $mapping = postZephir::load_prefix_map("$ENV{ROOTDIR}/data/sdr_num_prefix_map.tsv");
  is($mapping->{'innc'}, 'nnc', 'loads the prefix mapping');
};

# bib_error()
# Takes bib_source from CAT$a, bib_key, bib_record, error_msg
# Increments bib_error hash for key: bib_source:error_msg
# prints to the OUT_RPT
# prints a special line to OUT_RPT, increments bad_out_cnt and bib_line if bib_source matches MIU. There doesn't appear to be a reason to do this.

# get_hathi_bib_record_solr()

# get_current_preferred_record_number()

subtest "getCollectionTable()" => sub {
  my $rightsDB = rightsDB->new();
  my $collection_table = postZephir::getCollectionTable( $rightsDB );
  is($collection_table->{"IBC"}->{'content_provider'}, 'Boston College', "getCollectionTable retrieves content_provider_code");
};

#my %RIGHTS;
#tie %RIGHTS, "DB_File", "t/fixtures/rights_dbm", O_RDONLY, 0644, $DB_BTREE;
# TODO: figure out connection to dev maria so this can be tested

done_testing();
