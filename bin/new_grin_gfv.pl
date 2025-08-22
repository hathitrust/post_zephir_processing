#!/usr/bin/env perl

# Does things in 2 steps.
# Each step consists of running a set of queries,
# and sending an email about what was done.
#
# Step 1:
# Updates ic/bib and und/bib rows to pdus/gfv in rights_current
# if they have viewability 'VIEW_FULL' GRIN and are not marked as CLAIMED and are not Keio.
# CLAIMED items are items with the CLAIMED flag is set, items where the rights holder has given permission
# to Google to make the item VIEW_FULL. That permission does not extend to HathiTrust.
# We don't do it for Keio because there are items that are PD in Japan that are not PD in the US (e.g. icus)

# Step 2:
# Updates pdus/gfv rows in rights_current records
# with their previous attr&reason
# if they no longer have viewability 'VIEW_FULL' in GRIN.

use strict;
use warnings;

use lib "$ENV{ROOTDIR}/perl_lib";

use Date::Manip qw(ParseDate UnixDate);
use Getopt::Long;
use Mail::Mailer;
use ProgressTracker;
use YAML::XS;

use Database;
use grin_gfv;

my $noop         = undef; # set with --noop
my $mailer       = undef;

# config
my $config_dir   = $ENV{CONFIG_DIR} || '/usr/src/app/config';
my $config_yaml  = "$config_dir/rights.yml";
my $config       = YAML::XS::LoadFile($config_yaml);
my $rights_dir   = $config->{rights}->{rights_dir};

GetOptions(
    # skip update queries, emails, log file & tracker
    'noop=s' => \$noop,
);

#### Step 1: UPDATE ITEMS TO FULL VIEW ####
my $tracker = ProgressTracker->new();
$tracker->start_stage("set_pdus_gfv") unless $noop;

my $grin_gfv = grin_gfv->new;
my $updates = $grin_gfv->updates_to_gfv;

# Loop over the relevant items and update their attr/reason
foreach my $update (@$updates) {
    unless ($noop) {
        $grin_gfv->write_update_to_gfv($update);
        $tracker->inc();
    }
}

# Send first email
unless ($noop) {
    $mailer = new_mailer("New ic/und but VIEW_FULL volumes");
    print $mailer $grin_gfv->updates_to_gfv_report;
    $mailer->close() or warn("Couldn't send message: $!");
}

#### Step 2: REVERT FORMERLY VIEW_FULL ITEMS ####
$tracker->start_stage("revert_pdus_gfv") unless $noop;

# Open file for which to record reverted barcodes
my $barcode_log = sprintf(
    '%s/barcodes_%s_revert_gfv_feed',
    $rights_dir,
    UnixDate(ParseDate("now"), '%Y-%m-%d_%H-%M-%S')
);
open(my $fh, ">>", $barcode_log) or die("can't open $barcode_log: $!");

my $reversions = $grin_gfv->reversions_from_gfv;
foreach my $reversion (@$reversions) {
    unless ($noop) {
        print $fh "$reversion->{namespace}.$reversion->{id}\n";
        # update item in rights_current with the old attr/reason
        $grin_gfv->write_reversion_from_gfv($reversion);
        $tracker->inc();
    }
}
close($fh);

unless ($noop) {
    # Send the second email and we're done
    $mailer = new_mailer("Old pdus/gfv volumes no longer VIEW_FULL");
    print $mailer $grin_gfv->reversions_from_gfv_report;
    $mailer->close() or warn("Couldn't send message: $!");
}

$tracker->finalize() unless $noop;

# The 2 emails sent only differ in subject and body,
# so we can do everything else using the same template.
sub new_mailer {
    my $subject = shift;
    my $mailer  = new Mail::Mailer;
    my $to_addr = join(
        ', ',
        split(' ', $ENV{'TO_ADDRESSES'})
    );

    my $email = {
        'From'    => $ENV{'FROM_ADDRESS'},
        'Subject' => $subject,
        'To'      => $to_addr
    };

    $mailer->open($email);
}
