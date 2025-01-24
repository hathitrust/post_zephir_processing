#!/usr/bin/env perl

use strict;
use warnings;

use lib "$ENV{ROOTDIR}/perl_lib";

use Date::Manip;
use DBI;
use Getopt::Long;
use Pod::Usage;
use ProgressTracker;
use YAML::XS;

use Database;

# Set up precedence. New rights with >= precedence are allowed to override.
# PRIORITY_MAN is special - a note must be set.
my $PRIORITY_BIB       = 1;
my $PRIORITY_GFV       = 2;
my $PRIORITY_COPYRIGHT = 3;
my $PRIORITY_ACCESS    = 4;
my $PRIORITY_MAN       = 5;
my $exit               = 0;

my $priorities = {
    $PRIORITY_BIB       => [qw(ic/bib und/bib pd/bib pdus/bib)],
    $PRIORITY_GFV       => [qw(pdus/gfv)],
    $PRIORITY_COPYRIGHT => [qw(ic/unp pd/ncn pdus/ncn pdus/crms pd/ren pdus/ren
                               ic/ren und/nfi pd/cdpp ic/cdpp pdus/cdpp ic/add pdus/add pd/add pd/exp
                               icus/gatt icus/ren op/ipma ic/ipma und/ipma und/ren ic/crms pd/crms
                               und/crms)],
    $PRIORITY_ACCESS    => [qw(ic-world/con und-world/con nobody/pvt cc-by-3.0/con
                               cc-by-4.0/con cc-by-nd-3.0/con cc-by-nd-4.0/con orph/ddd orphcand/ddd
                               cc-by-nc-3.0/con cc-by-nc-4.0/con cc-by-sa-3.0/con cc-by-sa-4.0/con
                               cc-by-nc-nd-3.0/con cc-by-nc-nd-4.0/con cc-by-nc-sa-3.0/con
                               cc-by-nc-sa-4.0/con cc-zero/con pd/con)],
    $PRIORITY_MAN       => [qw(pd/man pdus/man ic-world/man und-world/man ic/man
                               nobody/man nobody/del pd-pvt/pvt supp/supp cc-by-3.0/man cc-by-4.0/man
                               cc-by-nd-3.0/man cc-by-nd-4.0/man cc-by-nc-3.0/man cc-by-nc-4.0/man
                               cc-by-sa-3.0/man cc-by-sa-4.0/man cc-by-nc-nd-3.0/man cc-by-nc-nd-4.0/man
                               cc-by-nc-sa-3.0/man cc-by-nc-sa-4.0/man cc-zero/man)],
};

# prepared statements
my $dbh              = undef;
my $insert_sth       = undef;
my $attr_sth         = undef;
my $reason_sth       = undef;
my $source_sth       = undef;
my $queue_update_sth = undef;

# Command line args
my $data               = 0;
my $note               = undef;
my $new_source_cmdline = 'null';
my $force_override     = 0;
my $mock_tracker       = 0;

# read config from yaml
my $config_dir  = $ENV{CONFIG_DIR} || '/usr/src/app/config';
my $config_yaml = "$config_dir/rights.yml";
my $config      = YAML::XS::LoadFile($config_yaml);
my $archive     = $config->{rights}->{archive};
my $rights_dir  = $config->{rights}->{rights_dir};

# allow overriding some of the vars set by yaml config
# with commandline options.
GetOptions(
    'data=s'          => \$data,
    'archive=s'       => \$archive,
    'rights_dir=s'    => \$rights_dir,
    'note=s'          => \$note,
    'source=s'        => \$new_source_cmdline,
    'force-override!' => \$force_override,
    'mock-tracker!'   => \$mock_tracker,
) or pod2usage();

# pass in --mock-tracker to disable ProgressTracker (for dev/test purposes).
my $tracker = $mock_tracker ? MockTracker->new() : ProgressTracker->new(report_interval => '10000');

my $thisprog = 'populate_rights_data';
print "$thisprog -INFO- START: " . CORE::localtime() . "\n";

if ($force_override and not defined $note) {
    print "You must provide a note (with --note) with the --force-override option.\n";
    exit 1;
}

if ($force_override) {
    print <<EOT ;

You have selected the --force-override option. This option will allow you to
override any rights with any other rights (for example, reverting a temporary
manual override to bib-determined rights). This option will export a "barcodes"
file so that Zephir will see these items as updated.

You have 10 seconds to abort (press Ctrl-C) before these rights are loaded.

EOT

    for (my $i = 0; $i < 10; $i++) {
        print STDERR '.';
        sleep 1;
    }
    print STDERR "\n";
}

my $user = `whoami`;
chomp($user);

# Structure to keep track of results - which records were created.
my %results;

# Build list of rights data files
# Rights files had better be tab-delimited CSV files with no header lines or comments

if ($data && ! -e $data) {
    print "$thisprog -ERR- Could not find input file $data\n";

    exit(1);
}

my @rights_files = ();
if (! $data) {
    @rights_files = glob("$rights_dir/*.rights");
} else {
    push @rights_files, $data;
}

if (@rights_files) {
    $dbh = Database::get_rights_rw_dbh();
    prepare_statements();

    foreach my $file (@rights_files) {
        process_file($file);
    }

    $insert_sth->finish();
    $dbh->disconnect();

    # Print results
    print "Results:\n";
    # TODO: Export these result metrics -- right now we only export a metric for lines processed
    if(defined $results{'inserted'}) {
        print "  Rows inserted: " . @{$results{'inserted'}} . "\n";
    }
    if ($force_override) {
        export_barcodes($results{'inserted'})
    }
    if (defined $results{'skipped'}) {
        print "  Items skipped (manually set): " . @{$results{'skipped'}} . "\n";
        foreach (@{$results{'skipped'}}) {
            print "\t$_\n";
        }
    }
    if (defined $results{'already_in_db'}) {
        print "  Items skipped (already in database with same attribute and reason): " . @{$results{'already_in_db'}} . "\n";
        foreach (@{$results{'already_in_db'}}) {
            print "\t$_\n";
        }
    }
    print "$thisprog -INFO- Done\n";
} else {
    print "$thisprog -INFO- No rights files to process.\n";
}
$tracker->finalize;

sub prepare_statements {
    # Prepare SQL statements
    my $replace_sql = "REPLACE INTO rights_current (namespace, id, attr, reason, source, access_profile, user, note) VALUES (?, ?, ?, ?, ?, ?, ?, ?)";
    $insert_sth     = $dbh->prepare($replace_sql) || die("$thisprog -ERR- Database error: " . $dbh->errstr());

    my $reason_sql = "SELECT name FROM reasons WHERE id = (SELECT reason FROM rights_current WHERE namespace = ? AND id = ?)";
    $reason_sth    = $dbh->prepare($reason_sql) || die ("$thisprog -ERR- Database error: " . $dbh->errstr());

    my $attr_sql = "SELECT name FROM attributes WHERE id = (SELECT attr FROM rights_current WHERE namespace = ? AND id = ?)";
    $attr_sth    = $dbh->prepare($attr_sql) || die("$thisprog -ERR- Database error: " . $dbh->errstr());

    my $source_sql = "SELECT name FROM sources WHERE id = (SELECT source FROM rights_current WHERE namespace = ? AND id = ?)";
    $source_sth    = $dbh->prepare($source_sql) || die("$thisprog -ERR- Database error: " . $dbh->errstr());

    # To consider moving this to an event-based thing at some point, but for
    # now we reach our tendrils into somebody else's database table...
    my $queue_update_sql = "UPDATE ht.feed_queue SET status = 'done' WHERE
    namespace = ? and id = ? AND status = 'rights'";
    $queue_update_sth    = $dbh->prepare($queue_update_sql) || die("$thisprog -ERR- Database error: " . $dbh->errstr());
}

sub process_file {
    my $file = shift;

    # Open input file, Loop through lines of input file
    open(IN, '<:encoding(UTF-8)', $file) or die("$thisprog -ERR- Could not open $file for reading: $!");
    while (my $line = <IN>) {
        process_rights_line($line);
        $tracker->inc();
    }
    close(IN);

    if ($archive) {
        # After populating rights database from *.rights file(s),
        # move file(s) to archive directory.

        my $cmd = "cp $file $archive";
        if (!$data) {
            $cmd = "mv $file $archive";
        }

        if (my $res = `$cmd`) {
            die("Error moving/copying rights file to archive: $res");
        }
    }
}

sub process_rights_line {
    my $line = shift;

    chomp($line);

    # get rid of trailing tab
    $line =~ s/\t$//;

    # Format of line had better be:
    #
    #   namespace.barcode attribute reason username source note
    #
    # ... where any of those fields can contain the string
    # /null/i to default to default values.
    # Also, the line could contain less than those fields,
    # like just 'barcode attribute reason username',
    # in which case 'source' will be the default value.

    my ($namespace_and_barcode, $new_attr, $new_reason, $uniqname, $new_source, $new_note) = split("\t", $line);

    if (defined $namespace_and_barcode && $namespace_and_barcode !~ /\bnull\b/i) {
        $namespace_and_barcode =~ s/\"//g;
    } else {
        die("namespace and barcode missing from input: $namespace_and_barcode");
    }

    # The ? is needed right where it is in the regex below
    # (greedy matching - so the namespace will be everything up to the first period).
    $namespace_and_barcode =~ /(.+?)\.(.+)/ || die("Invalid namespace/barcode: $namespace_and_barcode");
    my $namespace = $1;
    my $barcode   = $2;

    my $attribute;
    if (defined $new_attr && $new_attr !~ /\bnull\b/i) {
        $new_attr =~ s/\"//g;

        # Make sure attribute is a valid attribute in the db
        my $hr = $dbh->selectcol_arrayref("SELECT id FROM attributes WHERE name = '$new_attr'");
        if (! defined $$hr[0]) {
            die("Invalid attribute: $attribute ($barcode)");
        } else {
            $attribute = $$hr[0];
        }
    } else {
        die("attribute missing from input");
    }

    my $reason;
    if (defined $new_reason && $new_reason !~ /\bnull\b/i) {
        $new_reason =~ s/\"//g;

        # Make sure reason is a valid reason in the db
        my $hr = $dbh->selectcol_arrayref("SELECT id FROM reasons WHERE name = '$new_reason'");
        if (! defined $$hr[0]) {
            die("Invalid reason: $new_reason ($barcode)");
        } else {
            $reason = $$hr[0];
        }
    } else {
        # default:
        $new_reason = 'bib';
        my $hr      = $dbh->selectcol_arrayref("SELECT id FROM reasons WHERE name = '$new_reason'");
        $reason     = $$hr[0];
    }

    if (defined $uniqname && $uniqname !~ /\bnull\b/i) {
        $uniqname =~ s/\"//g;

        if ($uniqname =~ /\W/) {
            die("Invalid user: $uniqname for $namespace.$barcode");
        }

        $user = $uniqname;
    } else {
        # the default was set above
    }

    my $source;
    my $access_profile;
    if (defined $new_source_cmdline && $new_source_cmdline !~ /\bnull\b/i) {
        # source on command line trumps source in input file
        $new_source = $new_source_cmdline;
    }

    if (defined $new_source && $new_source !~ /\bnull\b/i) {
        $new_source =~ s/\"//g;

        # Make sure source is a valid value in the db
        my $hr = $dbh->selectrow_arrayref("SELECT id, access_profile FROM sources WHERE name = '$new_source'");
        if (! defined $$hr[0]) {
            die("Invalid source: $new_source ($barcode)");
        } else {
            $source         = $$hr[0];
            $access_profile = $$hr[1];
        }
    } else {
        # Default source should be whatever the source value was
        # in any previous rights db rows for this ID, or 'google'
        my $hr = $dbh->selectrow_arrayref(
            "SELECT source, access_profile FROM rights_current WHERE namespace = '$namespace' AND id = '$barcode'"
        );

        if (! defined $$hr[0]) {
            $source         = 1; # 'google'
            $access_profile = 2;
        } else {
            $source         = $$hr[0];
            $access_profile = $$hr[1];
        }
    }

    if (defined $new_note && $new_note !~ /\bnull\b/i) {
        if (defined $note && $note && $note ne $new_note) {
            die("Command-line note conflicts with .rights note ($barcode)");
        }
    } else {
        $new_note = $note;
    }

    my ($old_attr, $old_reason, $old_source) = get_old_rights($namespace, $barcode);
    my $do_insert = 0;

    if (defined $old_reason && defined $old_attr) {
        # If the new reason, attribute and source are the same as the most
        # recent ones, ignore at this point.
        if ( ($new_reason eq $old_reason) && ($new_attr eq $old_attr) ) {
            # Update if the source is different, but the attribute and reason are the same
            # or if a note was provided
            if (
                (defined $new_source and $new_source ne 'null' and $new_source ne $old_source)
                or (defined $new_note and $new_note)
                or ($uniqname eq 'crms' or $uniqname eq 'crmsworld')
            ) {
                $do_insert = 1;
            } else {
                set_queue_done($namespace, $barcode);
                push @{$results{'already_in_db'}}, "$namespace.$barcode";
                next;
            }
        } else {
            $do_insert = should_update_rights(
                $namespace,
                $barcode,
                $old_attr,
                $old_reason,
                $old_source,
                $new_attr,
                $new_reason,
                $new_source,
                $new_note
            );
        }
    } else {
        # No rights in the db yet for this barcode so just insert whatever we have here
        $do_insert = 1;
    }

    # Insert new row with most recent rights data
    if ($do_insert) {
        eval {
            $insert_sth->execute(
                $namespace,
                $barcode,
                $attribute,
                $reason,
                $source,
                $access_profile,
                $user,
                $new_note
            ) or die("$thisprog -ERR- Database error: " . $dbh->errstr());
        };
        if ($@) {
            warn($@);
        } else {
            push @{$results{'inserted'}}, "$namespace.$barcode";
            set_queue_done($namespace, $barcode);
        }
    } else {
        push @{$results{'skipped'}}, "$namespace.$barcode";
        set_queue_done($namespace, $barcode);
        next;
    }
}

sub get_old_rights {
    my ($namespace, $barcode) = @_;

    # Determine if a row already exists for this barcode.
    # Get reason from most recent rights data:
    $reason_sth->execute($namespace, $barcode) || die("$thisprog -ERR- Database error: " . $dbh->errstr());
    my $hr         = $reason_sth->fetchrow_hashref();
    my $old_reason = $$hr{'name'} || undef;
    $reason_sth->finish();

    # Get attribute from most recent rights data:
    $attr_sth->execute($namespace, $barcode) || die("$thisprog -ERR- Database error: " . $dbh->errstr());
    $hr          = $attr_sth->fetchrow_hashref();
    my $old_attr = $$hr{'name'} || undef;
    $attr_sth->finish();

    # Get source from most recent rights data:
    $source_sth->execute($namespace, $barcode) || die("$thisprog -ERR- Database error: " . $dbh->errstr());
    $hr            = $source_sth->fetchrow_hashref();
    my $old_source = $$hr{'name'} || undef;
    $source_sth->finish();

    return ($old_attr, $old_reason, $old_source);
}

sub should_update_rights {
    my (
        $namespace,
        $barcode,
        $old_attr,
        $old_reason,
        $old_source,
        $new_attr,
        $new_reason,
        $new_source,
        $new_note
    ) = @_;

    my $do_insert = 0;

    # $old_reason -> Most recent reason
    # $new_reason -> New reason

    # Does the old one or the new one win?
    my $old_priority = get_priority($old_attr, $old_reason);
    my $new_priority = get_priority($new_attr, $new_reason);

    # Make sure we were able to determine the priority
    if (not defined $old_priority) {
        warn("Unknown old rights $old_attr/$old_reason for $namespace.$barcode");
        $exit      = 1;
        $do_insert = 0;
    }
    if (not defined $new_priority) {
        warn("Unknown new rights $new_attr/$new_reason for $namespace.$barcode");
        $exit      = 1;
        $do_insert = 0;
    }
    if (defined $old_priority and defined $new_priority) {
        if ($force_override) {
            $do_insert = 1;
        } elsif (
            ($old_reason eq 'gfv' or $new_reason eq 'gfv') and
            ($old_reason eq 'bib' or $new_reason eq 'bib')
        ) {
            # handle pdus/gfv precedence
            ($exit, $do_insert) = gfv_overrides(
                $namespace,
                $barcode,
                $old_attr,
                $old_reason,
                $new_attr,
                $new_reason
            );
        } elsif ($new_priority >= $old_priority) {
            $do_insert = 1;
        } else {
            # new priority is too low; ignore
            $do_insert = 0;
        }

        if ($new_priority == $PRIORITY_MAN && not defined $new_note) {
            warn("$new_attr/$new_reason requested for $namespace.$barcode but note not provided");
            $exit      = 1;
            $do_insert = 0;
        }
    }

    return $do_insert;
}

sub get_priority {
    my ($attr, $reason) = @_;

    my $code     = "$attr/$reason";
    my $toreturn = undef;

    while (my ($priority, $codes) = each %$priorities) {
        if (grep {$_ eq $code} @$codes) {
            warn("$attr/$reason has two priorities ($priority and $toreturn)??") if defined $toreturn;
            $exit     = 1;
            $toreturn = $priority
        }
    }

    if (not defined $toreturn) {
        warn("Unknown code $attr/$reason");
        $exit = 1;
    }

    return $toreturn;
}

# returns $exit, $do_insert
# rules for gfv override is complicated
# pdus/gfv should override ic/bib and und/bib but not pd/bib or pdus/bib
# pd/bib and pdus/bib should override pdus/gfv
# all bibs should override each other
sub gfv_overrides {
    my (
        $namespace,
        $barcode,
        $old_attr,
        $old_reason,
        $new_attr,
        $new_reason
    ) = @_;

    # pd/bib and pdus/bib override pdus/gfv
    if ($old_attr eq 'pdus' and $old_reason eq 'gfv') {
        if ($new_reason eq 'bib' and ($new_attr eq 'pd' or $new_attr eq 'pdus')) {
            return (0, 1); # use new rights - pd/bib, pdus/bib overrides pdus/gfv
        } elsif ($new_reason eq 'bib' and ($new_attr eq 'ic' or $new_attr eq 'und')) {
            return (0, 0); # ignore new rights
        } else {
            warn("unknown new attr/reason: $old_attr/$old_reason, new: $new_attr/$new_reason for $namespace.$barcode");
            return (1, 0);
        }

    } elsif ($new_attr eq 'pdus' and $new_reason = 'gfv') {
        if ($old_reason eq 'bib' and ($old_attr eq 'ic' or $old_attr eq 'und')) {
            return (0, 1); # use new rights - pdus/gfv overrides ic/bib and und/bib
        } elsif ($old_reason eq 'bib' and ($old_attr eq 'pd' or $old_attr eq 'pdus')) {
            return (0, 0); # ignore new rights
        } else {
            warn("unknown old attr/reason: $old_attr/$old_reason, new: $new_attr/$new_reason for $namespace.$barcode");
            return (1, 0);
        }

    } else {
        warn("gfv but not pdus?? old: $old_attr/$old_reason, new: $new_attr/$new_reason for $namespace.$barcode");
        return (1, 0);
    }
}

sub set_queue_done {
    my $namespace = shift;
    my $barcode   = shift;

    $queue_update_sth->execute($namespace, $barcode);
}

sub export_barcodes {
    my $htids = shift;

    my $barcode_log = sprintf(
        '%s/barcodes_%s_override_feed',
        $rights_dir,
        UnixDate(ParseDate("now"), '%Y-%m-%d_%H-%M-%S')
    );
    open(my $fh, ">>", $barcode_log) or die("can't open $barcode_log: $!");

    foreach my $htid (@$htids) {
        print $fh $htid, "\n";
    }
}


=head1 NAME

populate_rights_data.pl

=head1 SYNOPSIS

perl populate_rights_data.pl [ --data=file | --rights_dir=dir ]
            --archive=archive_dir

=head2 OPTIONS

  Data load location:

    --data=file gives the full path to the file to load rights from

    --rights_dir=directory gives the path to a directory with rights
                 files to load; populate_rights will load all the
                 *.rights files in that directory.

    --archive=archive_dir gives the path to a directory where the
                 loaded .rights files will be saved.

  Other options:

    --note="Note" populates the notes field in the database with the
              given note for each loaded rights entry.

    --source=source forces the source for all loaded rights to the
              given source, for example "UMP".

    --force-override allows any rights to be loaded, ignoring the
              normal precedence rules. WARNING: Use this option with
              extreme care.

    --mock-tracker forces $tracker into a MockTracker object
              that does nothing, for dev/test purposes.

=head1 DESCRIPTION

This script uses the '*.rights' file to populate the rights database, then
moves the '*.rights' file to $rights_archive. The script lists the number
of records that were loaded and prints the info for any rights that were
not loaded, either because the rights were not valid or the rights already
existed in the database.

The script also updates the tracking database to indicate that the rights
have been successfully loaded for the given volumes.

rights files are tab-separated files in the following format:

namespace id attr reason [user [source [note]]]

where namespace.id is the HathiTrust ID of the volume; attr, reason
and source are a attribute, reason and source code as listed in the
rights database; and user is the user ID of the user responsible
for generating the rights. Note can be, but is not restricted to,
Jira ticket number.

=cut

package MockTracker;

# When you are running in an environment where you cannot use
# ProgressTracker, pass --mock-tracker to use this mock class
# instead.


sub new {
    my $class = shift;
    my $self  = {};
    print "MockTracker->new\n";
    bless($self, $class);
}

sub finalize {
    print "MockTracker->finalize\n";
}

sub inc {
    print "MockTracker->inc\n";
}
