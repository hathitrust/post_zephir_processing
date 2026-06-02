#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Data::Dumper;
use File::Temp qw(tempdir);
use POSIX qw(strftime);
use Test2::Bundle::Extended;
use Test2::Tools::Spec;
use Test2::Tools::Compare;
use Test::Exception;
# use Test::More;

use lib "$ENV{ROOTDIR}/perl_lib";
use lib "$ENV{ROOTDIR}/bin";
use Database;
use grin_gfv;

require "populate_rights_data.pl";

# numerical constants corresponding to various rights values
use constant {
  ATTR_PD => 1,
  ATTR_IC => 2,
  ATTR_PDUS => 9,
  ATTR_NOBODY => 8,

  REASON_BIB => 1,
  REASON_MAN => 5,

  SOURCE_GOOGLE => 1,
  SOURCE_IA => 4,

  ACCESS_PROFILE_OPEN => 1,
  ACCESS_PROFILE_GOOGLE => 2

};

my $dbh = Database::get_rights_rw_dbh;

# These are used by `write_reversion_from_gfv` and `write_reversion_from_gfv` describe, as well as `load_test_fixtures`
my $rights_current_sql = "INSERT INTO rights_current (namespace, id, attr, reason, source, access_profile, user) VALUES (?, ?, ?, ?, ?, ?, 'defaultuser')";
my $rights_current_sth = $dbh->prepare($rights_current_sql);

my $feed_grin_sth = $dbh->prepare("INSERT INTO feed_grin (namespace, id, scan_date) VALUES (?,?,?)");

sub joinline {
  return join("\t", @_) . "\n";
}

sub test_process_rights_line {
  process_rights_line(joinline(@_));
}

# Clean up any previously failed describe

describe "populate_rights_data.pl" => sub {

  before_all "prepare statement" => sub { 
    prepare_statements(); 
    load_tables();
  };

  before_each "clean up database" => sub {
    $dbh->do("DELETE FROM rights_current");
    $dbh->do("DELETE FROM feed_grin");
  };

  describe "should_update_rights" => sub {

    sub should_update {

      my ($old_attr, $old_reason, $new_attr, $new_reason, $note) = @_;

      should_update_rights(
        "prtest","testitem",
        $old_attr,$old_reason,"open",
        $new_attr,$new_reason,"open",
        $note);
    }

    sub expect_update {
      ok(should_update(@_));
    }

    sub expect_no_update {
      ok(!should_update(@_));
    }

    it "bib overrides bib" => sub { expect_update('pd','bib','ic','bib'); };
    it "copyright overrides bib" => sub { expect_update('ic','bib','pd','ren'); };
    it "bib doesn't override copyright" => sub { expect_no_update('pd','ren','ic','bib') };
    it "access overrides copyright" => sub { expect_update('ic','ren','cc-by-4.0','con') };
    it "copyright doesn't override access" => sub { expect_no_update('cc-by-4.0','con','ic','ren') };
    it "man with note overrides man" => sub { expect_update('nobody','man','pd','man','test note') };
    it "man without note doesn't override bib" => sub { expect_no_update('nobody','man','pd','bib') };
    it "access doesn't override man" => sub { expect_no_update('nobody','man','cc-by-4.0','con') };

    describe "gfv overrides" => sub {
      it "pdus/gfv overrides ic/bib" => sub { expect_update('ic','bib','pdus','gfv') };
      it "pdus/gfv overrides und/bib" => sub { expect_update('und','bib','pdus','gfv') };
      it "pdus/gfv does not override pd/bib" => sub { expect_no_update('pd','bib','pdus','gfv') };
      it "ic/bib does not override pdus/gfv" => sub { expect_no_update('pdus','gfv','ic','bib') };
      it "und/bib does not override pdus/gfv" => sub { expect_no_update('pdus','gfv','und','bib') };
      it "pd/bib overrides pdus/gfv" => sub { expect_update('pdus','gfv','pd','bib') };
      it "pdus/bib overrides pdus/gfv" => sub { expect_update('pdus','gfv','pdus','bib') };
    };

  };

  describe "process_rights_line" => sub {

    it "requires attr" => sub {
      dies_ok { process_rights_line("prtest.123456") };
      like $@, qr(attribute missing);
    };

    it "requires valid id" => sub {
      dies_ok { test_process_rights_line("not_an_id","pd","bib","testuser","google") };
      like $@, qr(Invalid namespace/barcode);
    };

    it "requires valid attr" => sub {
      dies_ok { test_process_rights_line("prtest.123456","not_attr","bib","testuser","google") };
      like $@, qr(Invalid attribute);
    };

    it "requires valid reason" => sub {
      dies_ok { test_process_rights_line("prtest.123456","pd","not_reason","testuser","google") };
      like $@, qr(Invalid reason);
    };

    it "requires valid source" => sub {
      dies_ok { test_process_rights_line("prtest.123456","pd","bib","testuser","not_source") };
      like $@, qr(Invalid source);
    };

    it "requires source if not previously loaded" => sub {
      dies_ok { test_process_rights_line("prtest.123456","pd","bib") };
      like $@, qr(Missing source);
    };

    it "loads bib rights for something not there" => sub {
      test_process_rights_line("prtest.newitem","pd","bib","testuser","google");

      my $rights = $dbh->selectrow_arrayref("SELECT attr, reason FROM rights_current WHERE namespace = 'prtest' and id = 'newitem'");

      is([ATTR_PD, REASON_BIB],$rights);
    };

    it "doesn't update rights with same attr/reason/source" => sub {
      $rights_current_sth->execute("prtest","samevals",ATTR_PD, REASON_BIB, SOURCE_GOOGLE, ACCESS_PROFILE_GOOGLE);

      # add it with a different user, shouldn't reload
      test_process_rights_line("prtest.samevals","pd","bib","newuser","google");

      my ($user) = $dbh->selectrow_array("SELECT user FROM rights_current WHERE namespace = 'prtest' and id = 'samevals'");
      is("defaultuser", $user);
    };

    it "retains source if not given & rights previously loaded" => sub {
      $rights_current_sth->execute("prtest","keepsource",ATTR_PD, REASON_BIB, SOURCE_IA, ACCESS_PROFILE_OPEN);

      test_process_rights_line("prtest.keepsource","ic","bib");
      my $rights = $dbh->selectrow_arrayref("SELECT attr, reason, source FROM rights_current WHERE namespace = 'prtest' and id = 'keepsource'");

      is([ATTR_IC, REASON_BIB, SOURCE_IA], $rights);
    };

    it "new source updates access profile (as specified in sources)" => sub {
      # pd/bib/google/google
      $rights_current_sth->execute("prtest","newsource",ATTR_PD, REASON_BIB, SOURCE_GOOGLE, ACCESS_PROFILE_GOOGLE);

      test_process_rights_line("prtest.newsource","pd","bib","testuser","ia");
      my ($access_profile) = $dbh->selectrow_array("SELECT access_profile FROM rights_current WHERE namespace = 'prtest' and id = 'newsource'");

      is(ACCESS_PROFILE_OPEN, $access_profile);
    };

  };

  describe "get_old_rights" => sub {

    it "gets old attribute, reason, source" => sub {
      # pd/bib/google/google
      $rights_current_sth->execute("prtest","oldrights",ATTR_PD, REASON_BIB, SOURCE_GOOGLE, ACCESS_PROFILE_GOOGLE);

      my ($old_attr, $old_reason, $old_source) = get_old_rights("prtest", "oldrights");
      is("pd",$old_attr);
      is("bib",$old_reason);
      is("google",$old_source);
    };

    it "returns undef if there are no rights" => sub {
      my ($old_attr, $old_reason, $old_source) = get_old_rights("prtest", "nonexistent");

      is(undef,$old_attr);
      is(undef,$old_reason);
      is(undef,$old_source);
    }
  };

  describe "data loading/integration" => sub { 
    my $tempdir;

    before_all "set up temp dir" => sub {
      $tempdir = tempdir( "/tmp/populate-rights-test-XXXXXX", CLEANUP => 1 );
      mkdir("$tempdir/rights");
      mkdir("$tempdir/archive");
    };

    it "loads files in rights_dir" => sub {
      open(my $rights, ">", "$tempdir/rights/testfile1.rights");
      print $rights joinline("prtest.loadfile","pd","bib","testuser","google");
      close($rights);
    
      my $res = qx(perl -w bin/populate_rights_data.pl --rights_dir=$tempdir/rights --archive=$tempdir/archive 2>&1);
      # 0 (ok) exit code
      ok(!$?); 
      ok($res =~ /Rows inserted: 1/m);
    
      my ($count) = $dbh->selectrow_array("SELECT count(*) FROM rights_current WHERE namespace = 'prtest' and id = 'loadfile'");
    
      is(1,$count);
      ok(!-e "$tempdir/rights/testfile1.rights");
      ok(-e "$tempdir/archive/testfile1.rights");
    };
    
    it "accepts --data for individual file; processes all lines" => sub {
      open(my $rights, ">", "$tempdir/testfile2.rights");
      print $rights joinline("prtest.procfile1","ic","bib","testuser","ia");
      print $rights joinline("prtest.procfile2","pd","bib","testuser","google");
      close($rights);
    
      my $res = qx(perl -w bin/populate_rights_data.pl --data=$tempdir/testfile2.rights --archive=$tempdir/archive 2>&1);
      # 0 (ok) exit code
      ok(!$?); 
      ok($res =~ /Rows inserted: 2/m);
    
      my ($count) = $dbh->selectrow_array("SELECT count(*) FROM rights_current WHERE namespace = 'prtest' and id in ('procfile1','procfile2')");
    
      is(2,$count);
    };

    it "bails out when encountering invalid data" => sub {
      open(my $rights, ">", "$tempdir/testfile3.rights");
      print $rights joinline("prtest.goodline1","ic","bib","testuser","ia");
      print $rights "badline\n";
      print $rights joinline("prtest.goodline2","pd","bib","testuser","google");
      close($rights);
    
      my $res = qx(perl -w bin/populate_rights_data.pl --data=$tempdir/testfile3.rights --archive=$tempdir/archive 2>&1);
      # nonzero exit code (error)
      ok($?);
      ok($res =~ /Invalid namespace\/barcode/);
    
      # Should have loaded goodline1, but not goodline2 (since it bailed out after badline)
      my ($count) = $dbh->selectrow_array("SELECT count(*) FROM rights_current WHERE namespace = 'prtest' and id = 'goodline1'");
      is(1,$count);
      
      ($count) = $dbh->selectrow_array("SELECT count(*) FROM rights_current WHERE namespace = 'prtest' and id = 'goodline2'");
      is(0,$count);
    };

    it "force-override requires note" => sub {
      open(my $rights, ">", "$tempdir/testfile4.rights");
      print $rights joinline("prtest.override1","pd","bib","testuser","ia");
      close($rights);
    
      my $res = qx(perl -w bin/populate_rights_data.pl --force-override --data=$tempdir/testfile4.rights --archive=$tempdir/archive 2>&1);
      # nonzero exit code (error)
      ok($?);
      ok($res =~ /must provide a note/m);
    
      # Should not have loaded anything
      my ($count) = $dbh->selectrow_array("SELECT count(*) FROM rights_current WHERE namespace = 'prtest' and id = 'override1'");
      is(0,$count);
    };

    
    it "force-override allows bib to override man & exports barcodes" => sub {
      # preload 'man' rights
      # nobody/man/google/google
      $rights_current_sth->execute("prtest","override2",ATTR_NOBODY, REASON_MAN, SOURCE_GOOGLE, ACCESS_PROFILE_GOOGLE);

      open(my $rights, ">", "$tempdir/testfile5.rights");
      print $rights joinline("prtest.override2","pd","bib","testuser","ia");
      close($rights);
    
      my $res = qx(perl -w bin/populate_rights_data.pl --force-override --note="override note" --data=$tempdir/testfile5.rights --archive=$tempdir/archive --rights_dir=$tempdir/rights 2>&1);

      # zero exit code (success)
      ok(!$?) or print STDERR $res;
      ok($res =~ /Rows inserted: 1/m);
    
      # Should have loaded 
      my ($count) = $dbh->selectrow_array("SELECT count(*) FROM rights_current WHERE namespace = 'prtest' and id = 'override2'");
      is(1,$count);

      my @override_feed_barcodes = glob("$tempdir/rights/barcodes_*_override_feed");

      is(1,scalar @override_feed_barcodes);

      open(my $fh, "<", $override_feed_barcodes[0]);
      my $line = <$fh>;
      is($line,"prtest.override2\n");
    };
  };

  describe "access profile for Google-scanned harvard material" => sub {

    sub expect_access_profile {
      my $id = shift;
      my $expected_access_profile = shift;

      my ($actual_access_profile) = $dbh->selectrow_array("SELECT access_profile FROM rights_current WHERE namespace = 'hvd' and id = ?",{},$id);

      is($expected_access_profile,$actual_access_profile);
    }

    describe "scan_date before 2025-03-24" => sub {
      it "sets profile to open for pd" => sub {
        $feed_grin_sth->execute("hvd","testitem1","2010-01-01 00:00:00");

        test_process_rights_line("hvd.testitem1","pd","bib","testuser","google");

        expect_access_profile("testitem1",ACCESS_PROFILE_OPEN);
      };

      it "updates profile for item that was ic and is now pd" => sub {
        $feed_grin_sth->execute("hvd","testitem2","2010-01-01 00:00:00");
        $rights_current_sth->execute("hvd","testitem2",ATTR_IC, REASON_BIB, SOURCE_GOOGLE, ACCESS_PROFILE_GOOGLE);

        test_process_rights_line("hvd.testitem2","pd","bib","testuser","google");

        expect_access_profile("testitem2", ACCESS_PROFILE_OPEN);
      };

      it "updates profile for item that was pd and is now ic" => sub {
        $feed_grin_sth->execute("hvd","testitem2_1","2010-01-01 00:00:00");
        $rights_current_sth->execute("hvd","testitem2_1",ATTR_PD, REASON_BIB, SOURCE_GOOGLE, ACCESS_PROFILE_OPEN);

        test_process_rights_line("hvd.testitem2_1","ic","bib","testuser","google");

        expect_access_profile("testitem2_1", ACCESS_PROFILE_GOOGLE);
      };

      it "updates profile for pd item" => sub {
        $feed_grin_sth->execute("hvd","testitem3","2010-01-01 00:00:00");
        $rights_current_sth->execute("hvd","testitem3",ATTR_PD, REASON_BIB, SOURCE_GOOGLE, ACCESS_PROFILE_GOOGLE);
        test_process_rights_line("hvd.testitem3","pd","bib","testuser","google");

        expect_access_profile("testitem3", ACCESS_PROFILE_OPEN);
      };

      it "sets profile to open for pdus" => sub {
        $feed_grin_sth->execute("hvd","testitem4","2010-01-01 00:00:00");

        test_process_rights_line("hvd.testitem4","pdus","bib","testuser","google");

        expect_access_profile("testitem4", ACCESS_PROFILE_OPEN);
      };

      it "sets profile to google for ic" => sub {
        $feed_grin_sth->execute("hvd","testitem5","2010-01-01 00:00:00");

        test_process_rights_line("hvd.testitem5","ic","bib","testuser","google");

        expect_access_profile("testitem5", ACCESS_PROFILE_GOOGLE);
      };

    };

    describe "scan_date after 2025-03-24" => sub {
      it "sets profile to google for pd" => sub {
        $feed_grin_sth->execute("hvd","testitem6","2026-01-01 00:00:00");
        $rights_current_sth->execute("hvd","testitem6",ATTR_PD, REASON_BIB, SOURCE_GOOGLE, ACCESS_PROFILE_OPEN);

        test_process_rights_line("hvd.testitem6","pd","bib","testuser","google");

        expect_access_profile("testitem6", ACCESS_PROFILE_GOOGLE);
      };

      it "sets profile to google for pdus" => sub {
        $feed_grin_sth->execute("hvd","testitem7","2026-01-01 00:00:00");
        $rights_current_sth->execute("hvd","testitem7",ATTR_PD, REASON_BIB, SOURCE_GOOGLE, ACCESS_PROFILE_OPEN);

        test_process_rights_line("hvd.testitem7","pdus","bib","testuser","google");

        expect_access_profile("testitem7", ACCESS_PROFILE_GOOGLE);
      };

      it "keeps profile google for ic" => sub {
        $feed_grin_sth->execute("hvd","testitem8","2026-01-01 00:00:00");
        $rights_current_sth->execute("hvd","testitem8",ATTR_IC, REASON_BIB, SOURCE_GOOGLE, ACCESS_PROFILE_GOOGLE);

        test_process_rights_line("hvd.testitem8","ic","bib","testuser","google");

        expect_access_profile("testitem8", ACCESS_PROFILE_GOOGLE);
      };
    };

    it "sets profile to google if item is not in feed_grin" => sub {
      test_process_rights_line("hvd.testitem9","pd","bib","testuser","google");

      expect_access_profile("testitem9", ACCESS_PROFILE_GOOGLE);
    }

  };

};

done_testing();
