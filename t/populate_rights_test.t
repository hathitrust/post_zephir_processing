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

my $dbh = Database::get_rights_rw_dbh;

# These are used by `write_reversion_from_gfv` and `write_reversion_from_gfv` tests, as well as `load_test_fixtures`
my $rights_current_sql = "INSERT INTO rights_current (namespace, id, attr, reason, source, access_profile, user) VALUES (?, ?, ?, ?, ?, ?, 'defaultuser')";
my $rights_current_sth = $dbh->prepare($rights_current_sql);

sub delete_rights_current_prtest {
  $dbh->prepare("DELETE FROM rights_current WHERE namespace = 'prtest'")->execute;
}

# Clean up any previously failed tests

describe "populate_rights_data.pl" => sub {

  before_all "prepare statement" => sub { prepare_statements(); };
  before_each "clean up" => sub { delete_rights_current_prtest; };

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

    # arguments: namespace, id, old

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
    };

  };

  describe "process_rights_line" => sub {

    it "requires attr" => sub {
      dies_ok { process_rights_line("prtest.123456") };
      like $@, qr(attribute missing);
    };

    it "requires valid id" => sub {
      dies_ok { process_rights_line("not_an_id\tpd\tbib\ttestuser\tgoogle\n") };
      like $@, qr(Invalid namespace/barcode);
    };

    it "requires valid attr" => sub {
      dies_ok { process_rights_line("prtest.123456\tnot_attr\tbib\ttestuser\tgoogle\n") };
      like $@, qr(Invalid attribute);
    };

    it "requires valid reason" => sub {
      dies_ok { process_rights_line("prtest.123456\tpd\tnot_reason\ttestuser\tgoogle\n") };
      like $@, qr(Invalid reason);
    };

    it "requires valid source" => sub {
      dies_ok { process_rights_line("prtest.123456\tpd\tbib\ttestuser\tnot_source\n") };
      like $@, qr(Invalid source);
    };

    it "requires source if not previously loaded" => sub {
      dies_ok { process_rights_line("prtest.123456\tpd\tbib\n") };
      like $@, qr(Missing source);
    };

    it "loads bib rights for something not there" => sub {
      process_rights_line("prtest.newitem\tpd\tbib\ttestuser\tgoogle\n");

      my $rights = $dbh->selectrow_arrayref("SELECT attr, reason FROM rights_current WHERE namespace = 'prtest' and id = 'newitem'");

      # numerical values for pd/bib
      is([1,1],$rights);
    };

    it "doesn't update rights with same attr/reason/source" => sub {
      # pd/bib/google/google -- sets user to 'defaultuser' by default
      $rights_current_sth->execute("prtest","samevals","1","1","1","2");

      # add it with a different user, shouldn't reload
      process_rights_line("prtest.samevals\tpd\tbib\tnewuser\tgoogle");

      my $user = $dbh->selectrow_arrayref("SELECT user FROM rights_current WHERE namespace = 'prtest' and id = 'samevals'");
      is(["defaultuser"], $user);
    };

    it "retains source if not given & rights previously loaded" => sub {
      # pd/bib/ia/open
      $rights_current_sth->execute("prtest","keepsource","1","1","4","1");

      process_rights_line("prtest.keepsource\tic\tbib");
      my $rights = $dbh->selectrow_arrayref("SELECT attr, reason, source FROM rights_current WHERE namespace = 'prtest' and id = 'keepsource'");

      # ic/bib/ia
      is([2,1,4],$rights);
    };

    it "new source updates access profile (as specified in sources)" => sub {
      # pd/bib/google/google
      $rights_current_sth->execute("prtest","newsource","1","1","1","2");

      process_rights_line("prtest.newsource\tpd\tbib\ttestuser\tia");
      my $access_profile = $dbh->selectrow_arrayref("SELECT access_profile FROM rights_current WHERE namespace = 'prtest' and id = 'newsource'");

      # access profile open
      is([1],$access_profile);
    };

  };

  describe "get_old_rights" => sub {

    it "gets old attribute, reason, source" => sub {
      # pd/bib/google/google
      $rights_current_sth->execute("prtest","oldrights","1","1","1","2");

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
      print $rights "prtest.loadfile\tpd\tbib\ttestuser\tgoogle\n";
      close($rights);
    
      my $res = qx(perl -w bin/populate_rights_data.pl --rights_dir=$tempdir/rights --archive=$tempdir/archive 2>&1);
      # 0 (ok) exit code
      ok(!$?); 
      ok($res =~ /Rows inserted: 1/m);
    
      my $count = $dbh->selectrow_arrayref("SELECT count(*) FROM rights_current WHERE namespace = 'prtest' and id = 'loadfile'");
    
      is([1],$count);
      ok(!-e "$tempdir/rights/testfile1.rights");
      ok(-e "$tempdir/archive/testfile1.rights");
    };
    
    it "accepts --data for individual file; processes all lines" => sub {
      open(my $rights, ">", "$tempdir/testfile2.rights");
      print $rights "prtest.procfile1\tic\tbib\ttestuser\tia\n";
      print $rights "prtest.procfile2\tpd\tbib\ttestuser\tgoogle\n";
      close($rights);
    
      my $res = qx(perl -w bin/populate_rights_data.pl --data=$tempdir/testfile2.rights --archive=$tempdir/archive 2>&1);
      # 0 (ok) exit code
      ok(!$?); 
      ok($res =~ /Rows inserted: 2/m);
    
      my $count = $dbh->selectrow_arrayref("SELECT count(*) FROM rights_current WHERE namespace = 'prtest' and id in ('procfile1','procfile2')");
    
      is([2],$count);
    };

    it "bails out when encountering invalid data" => sub {
      open(my $rights, ">", "$tempdir/testfile3.rights");
      print $rights "prtest.goodline1\tic\tbib\ttestuser\tia\n";
      print $rights "badline\n";
      print $rights "prtest.goodline2\tpd\tbib\ttestuser\tgoogle\n";
      close($rights);
    
      my $res = qx(perl -w bin/populate_rights_data.pl --data=$tempdir/testfile3.rights --archive=$tempdir/archive 2>&1);
      # nonzero exit code (error)
      ok($?);
      ok($res =~ /Invalid namespace\/barcode/);
    
      # Should have loaded goodline1, but not goodline2 (since it bailed out after badline)
      my $count = $dbh->selectrow_arrayref("SELECT count(*) FROM rights_current WHERE namespace = 'prtest' and id = 'goodline1'");
      is([1],$count);
      
      $count = $dbh->selectrow_arrayref("SELECT count(*) FROM rights_current WHERE namespace = 'prtest' and id = 'goodline2'");
      is([0],$count);
    };

    it "force-override requires note" => sub {
      open(my $rights, ">", "$tempdir/testfile4.rights");
      print $rights "prtest.override1\tpd\tbib\ttestuser\tia\n";
      close($rights);
    
      my $res = qx(perl -w bin/populate_rights_data.pl --force-override --data=$tempdir/testfile4.rights --archive=$tempdir/archive 2>&1);
      # nonzero exit code (error)
      ok($?);
      ok($res =~ /must provide a note/m);
    
      # Should not have loaded anything
      my $count = $dbh->selectrow_arrayref("SELECT count(*) FROM rights_current WHERE namespace = 'prtest' and id = 'override1'");
      is([0],$count);
    };

    
    it "force-override allows bib to override man & exports barcodes" => sub {
      # preload 'man' rights
      # nobody/man/google/google
      $rights_current_sth->execute("prtest","override2","8","5","1","2");

      open(my $rights, ">", "$tempdir/testfile5.rights");
      print $rights "prtest.override2\tpd\tbib\ttestuser\tia\n";
      close($rights);
    
      my $res = qx(perl -w bin/populate_rights_data.pl --force-override --no-wait --note="override note" --data=$tempdir/testfile5.rights --archive=$tempdir/archive --rights_dir=$tempdir/rights 2>&1);

      # zero exit code (success)
      ok(!$?) or print STDERR $res;
      ok($res =~ /Rows inserted: 1/m);
    
      # Should have loaded 
      my $count = $dbh->selectrow_arrayref("SELECT count(*) FROM rights_current WHERE namespace = 'prtest' and id = 'override2'");
      is([1],$count);

      my @override_feed_barcodes = glob("$tempdir/rights/barcodes_*_override_feed");

      is(1,scalar @override_feed_barcodes);

      open(my $fh, "<", $override_feed_barcodes[0]);
      my $line = <$fh>;
      is($line,"prtest.override2\n");
    };
  };

};

done_testing();
