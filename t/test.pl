#!/usr/bin/perl

use strict;
use warnings;
use File::Basename;
BEGIN {push @INC, dirname(__FILE__)};

use File::Slurp;
use Test::More;
use Data::Dumper;

use postZephir;

my $bib = MARC::Record::MiJ->new(read_file("test_record.json"));
my $bib_key = $bib->field('001')->as_string();

is($bib_key, "000000012", 'bib key extraction');

# process_035
my ($oclc_num, $sdr_num_hash) = postZephir::process_035($bib, $bib_key);

is($oclc_num, "604", 'oclc number extraction');

# SDR Nums were used for the Hathifiles, and a report that no one actually reads
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

# get_bib_data()
# pulls strings from specified MARC field
my $title = postZephir::get_bib_data($bib, '245', 'abc');
is($title, 'MMPI; research developments and clinical applications. Edited by James Neal Butcher', 'title');
# indicators matter
my $title = postZephir::get_bib_data($bib, '24510', 'abc');
is($title, 'MMPI; research developments and clinical applications. Edited by James Neal Butcher', 'title');
my $title = postZephir::get_bib_data($bib, '24501', 'abc');
is($title, '', 'title');

# GetRights()

# GetRightsDBM()

# filter_dollar_barcode()

# outputField()

# getDate()

# clean_json_line()

# rights_map()

# check_bib()

# bib_error()

# get_current_preferred_record_number()

# get_hathi_bib_record_solr()

# getCollectionTable()

# setup_htrc_output()

# htrc_output()

# write_htrc_record()

done_testing();
