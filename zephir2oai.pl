#!/usr/local/bin/perl

use open qw( :encoding(UTF-8) :std );
use strict;
use File::Basename;
use Getopt::Std;
use MARC::Record;
use MARC::Batch;
use MARC::File::MiJ;
use MARC::Record::MiJ;
use MARC::File::XML;
use XML::LibXML;
use XML::LibXSLT;

my $prgname = basename($0);

sub usage {
  my $msg = shift;
  $msg and $msg = " ($msg)";
  return"usage: $prgname -f from_date (YYYYMMDD) -i infile -d delete_file -o outbase [-s max_filesize]$msg\n";
};

our ($opt_f, $opt_i, $opt_o, $opt_d, $opt_s);
getopts('f:i:o:d:s:');

$opt_f or die usage("from_date not specified");
my $from_date = $opt_f;
my ($from_year, $from_month, $from_day) = $from_date =~ /^(\d{4})(\d{2})(\d{2})$/ or die usage("invalid format for from date: $from_date\n");
my $from_date = join('-', $from_year, $from_month, $from_day) . 'D' . 'T00:00:00Z';
print "from_date is $from_date\n";

$opt_i or die usage("infile not specified");
my $infile = $opt_i;
$opt_d or die usage("delete file not specified");
my $delete_file = $opt_d;

$opt_o or die usage("outbase not specified");
my $outfile_base = $opt_o;

my $max_filesize = 0;
$opt_s and do {
  $opt_s =~ /^\d+$/ or die usage("maximum filesize must be numeric: $opt_s");
  $max_filesize = $opt_s;
};

my $response_date = getDate(time());	
my $metadata_prefix = "marc21";

my $oai_xml_header = <<EOF;
<OAI-PMH xmlns="http://www.openarchives.org/OAI/2.0/" 
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" 
         xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/ http://www.openarchives.org/OAI/2.0/OAI-PMH.xsd">
<responseDate>$response_date</responseDate>
<request verb="ListRecords" from="$from_date" metadataPrefix="$metadata_prefix">http://mirlyn-aleph.lib.umich.edu/OAI</request>
<ListRecords>
EOF

my $oai_xml_footer = <<EOF;
</ListRecords>
</OAI-PMH>
EOF

my $xml_max_filesize = $max_filesize - length($oai_xml_header) - length($oai_xml_footer);
my $xml_file_seq = '00';
my $xml_curr_filename = '';
my $xml_curr_size = 0;

sub open_new_xml_file {
  if ($max_filesize)  {
    $xml_file_seq++;
    $xml_curr_filename = $outfile_base . "_oaimarc_" . $xml_file_seq . ".xml";
    print STDERR "current xml file: $xml_curr_filename\n ";
  } else {
    $xml_curr_filename = $outfile_base . "_oaimarc.xml";
  }
  open(OUTXML, ">$xml_curr_filename") or die "can't open xml output file $xml_curr_filename: $!"; binmode(OUTXML, ":utf8");
  print OUTXML $oai_xml_header;
  $xml_curr_size = 0;
}

sub close_current_xml_file {
  #$xml_curr_size and do {
    print OUTXML $oai_xml_footer;
    close(OUTXML);
  #};
}


my $infile_open = $infile;
$infile =~ /\.gz$/ and do {
  $infile_open = "unpigz -c $infile |";
  print "infile $infile is compressed, using pigz to process: $infile_open\n";
  $infile =~ s/\.gz$//;
};
open(IN,"$infile_open") or die "can't open $infile for input: $!\n";
binmode(IN);

my $delete_file_open = $delete_file;
$delete_file =~ /\.gz$/ and do {
  $delete_file_open = "unpigz -c $delete_file |";
  print "delete file $delete_file is compressed, using pigz to process: $delete_file_open\n";
  $delete_file =~ s/\.gz$//;
};
open(DELETE,"$delete_file_open") or die "can't open $delete_file_open for input: $!\n";
binmode(DELETE);

#open(OUT_OAIMARC, ">$out_oaimarc_file") or die "can't open $out_oaimarc_file for output: $!";
open_new_xml_file();
#open(OUT_OAIDC, ">$out_oaidc_file") or die "can't open $out_oaidc_file for output: $!";

# delete alpha tags
my @delete_field_tags = ( 'CID', 'HOL', 'DAT', 'FMT', 'HOL', 'CAT', 'COM', '856');
my $delete_field_tags = join('|', @delete_field_tags);

  #xsi:schemaLocation="http://www.loc.gov/MARC21/slim http://www.loc.gov/standards/marcxml/schema/MARC21slim.xsd"
my $add_namespace_stylesheet = <<'EOF';
<xsl:stylesheet 
  version="1.0" 
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform" 
  xmlns:marc="http://www.loc.gov/MARC21/slim">

 <xsl:output omit-xml-declaration="yes" indent="yes"/>

 <xsl:template match="node()|@*">
  <xsl:copy>
   <xsl:apply-templates select="node()|@*"/>
  </xsl:copy>
 </xsl:template>

 <xsl:template match="*">
  <xsl:element name="marc:{name()}" namespace="http://www.loc.gov/MARC21/slim"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.loc.gov/MARC21/slim http://www.loc.gov/standards/marcxml/schema/MARC21slim.xsd">
    <xsl:copy-of select="namespace::*"/> 
    <xsl:apply-templates select="node()|@*"/>
  </xsl:element>
 </xsl:template>

</xsl:stylesheet>
EOF

my $parser = new XML::LibXML;
my $xslt       = XML::LibXSLT->new();

my $styleDoc   = $parser->parse_string( $add_namespace_stylesheet ) or die "can't parse stylesheet string";
my $stylesheet = $xslt->parse_stylesheet( $styleDoc ) or die "can't parse stylesheet";

#my $styleDC2MarcSheet = $xslt->parse_stylesheet_file("MARC21slim2OAIDC.xsl");

my $reccnt = 0; my $outcnt = 0;
my $delete_cnt = 0; my $delete_out_cnt = 0;
  
my $record;

my $exit = 0;
$SIG{INT} = sub { $exit = 1 };

my $recID;

delete: while (my $delete_line = <DELETE> ) {
  chomp $delete_line;
  next unless $delete_line;
  $delete_cnt++;
  my $recID = $delete_line;
  my $delete_record = delete_record($recID, $from_date);
  $delete_record and do {
    $delete_out_cnt++;
    #print OUT_OAIMARC $delete_record, "\n" ;
    write_record($delete_record);
  };
}

record: while (my $record_line = <IN> ) {
  $exit and do {
    print "exitting due to signal\n";
    last record;
  };
  $reccnt++;
  $reccnt % 1000 == 0 and print "processing record $reccnt\n";
  #$reccnt % 100000 == 0 and last record;
  #next record unless $reccnt >= 413236;
  chomp($record_line);
  # parse line
  $record_line =~ /\n/ and do {
    print STDERR "$reccnt: newline in record\n";
  };
  eval { $record = MARC::Record::MiJ->new($record_line); };
  $@ and do {
    print "problem processing json line $reccnt\n";
    warn $@;
    next record;
  };

  $recID = $record->field('001')->as_string() or die "$reccnt: no bib key\n";

  my $datestamp = get_update($record);
  substr($datestamp, 0, 10) ne substr($from_date, 0, 10) and do {	# weird--shouldn't occur--tlp
    #print "$recID: $datestamp, from_date is $from_date\n";
    $datestamp = $from_date;
  };

  update_record($record);
  #my $marcxml_record = MARC::File::XML::record( $record );
  #my $marcxml_record = $record->as_xml();
  my $marcxml_record = $record->as_xml_record();
#print $marcxml_record, "\n";
  my $marcxml_record = addMarcNamespace($marcxml_record);
#print $marcxml_record, "\n";
#exit;
  #my $dc_record = marc2dc($marcxml_record);
  my $oaimarc_record = join('',
    "<record>\n<header>\n<identifier>oai:HathiTrust:MIU01-",
    $recID,
    "</identifier>\n<datestamp>",
    $datestamp,
    "</datestamp>\n<setSpec>MDP</setSpec>\n</header>\n<metadata>\n",
    $marcxml_record,
    "</metadata>\n</record>\n"
    );
  #print OUT_OAIMARC $oaimarc_record;
  write_record($oaimarc_record);
  $outcnt++;
}

close_current_xml_file();
#write_oai_footer(\*OUT_OAIMARC);
#write_oai_footer(\*OUT_OAIDC);

print "$prgname--@ARGV\n";
print "$reccnt bib records records read\n";
print "$delete_cnt delete records records read\n";
print "$outcnt bib records written\n";
print "$delete_out_cnt delete records written\n";
print "\n";

sub write_record {
  my $record = shift;
  my $l = length( $record );
  $max_filesize and $xml_curr_size + $l > $xml_max_filesize and do {
    close_current_xml_file();
    open_new_xml_file();
  };
  print OUTXML $record;
  $xml_curr_size += $l;
  return;
}

sub update_record {
  my $record = shift;
  foreach my $field ($record->field($delete_field_tags)) {
    #print "$recordID ($in_cnt): deleting field:"  . outputField($field) . "\n";
    $record->delete_field($field);
  }
  foreach my $field ($record->field('974')) {
    my $htid = $field->as_string('u');
    $htid or do {
      print STDERR "$recID: no subfield u in 974, field deleted\n";
      $record->delete_field($field);
      next;
    };
    $field->update('u' => "http://hdl.handle.net/2027/" . $htid);
    $field->add_subfields('x', 'eContent');
    $field->{_tag} = "856";
  }
}

sub printMarc {
  my $record = shift;
  my $filehandle = shift;
  if (!defined($filehandle)) { $filehandle = \*STDOUT; }
  my @fields = $record->fields();

  ## print out the tag, the indicators and the field contents
  print $filehandle "LDR ",$record->leader(),"\n";
  foreach my $field (@fields) {
    print $filehandle $field->tag(), " ";
    if ($field->tag() lt '010') { print $filehandle "   ",$field->data; }
    else {
      print $filehandle $field->indicator(1), $field->indicator(2), " ";
      my @subfieldlist = $field->subfields();
      foreach my $sfl (@subfieldlist) {
        print $filehandle "|".shift(@$sfl).shift(@$sfl);
      }
    }
    print $filehandle "\n";
  }
  return;
}

sub get_update {
  my $record = shift;
#005    20130211000000.0

  my $update = convert_005_date($record->field('005')->as_string());
  DAT:foreach my $field ($record->field('DAT')) {
    $field->indicator(1) == 0 and do {
      #DAT 0  |a20130211174459.0|b20130211000000.0
      my $suba = convert_005_date($field->as_string('a'));
      $suba and $suba gt $update and $update = $suba;
      my $subb = convert_005_date($field->as_string('b'));
      $subb and $subb gt $update and $update = $subb;
      next DAT;
    };
    $field->indicator(1) == 1 and do {
      #DAT 1  |a20130216053816.0|b2013-12-07T00:01:26Z
      my $suba = convert_005_date($field->as_string('a'));
      $suba and $suba gt $update and $update = $suba;
      my $subb = $field->as_string('b');
      $subb and $subb gt $update and $update = $subb;
      next DAT;
    };
    $field->indicator(1) == 2 and do {
      #DAT 2  |a2013-01-30T17:30:33Z|b2013-12-06T23:30:03Z
      my $suba = $field->as_string('a');
      $suba and $suba gt $update and $update = $suba;
      my $subb = $field->as_string('b'); 
      $subb and $subb gt $update and $update = $subb;
      next DAT;
    };
  }
  F974:foreach my $field ($record->field('974')) {
    #974    |bMIU|cMIU|d20131207|slit-dlps-dc|umdp.39015025977722|z1828 Sep-1829 Sep|rpd
    my $subd = $field->as_string('d');
    $subd and do {
      my $subd_date = convert_005_date($subd . '000000.0');
      $subd_date gt $update and $update = $subd_date;
    };
  }
  return $update;
} 

sub convert_datestamp { 	# yyyy-mm-ddThhmmssZ -> yyyymmddhhmmss.0
  my $datestamp = shift;
  my ($year, $month, $day, $hour, $min, $sec) = $datestamp =~ /(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})Z/;
  #return join('', $year, $month, $day, $hour, $min, $sec) . '.0';
  return join('-', $year, $month, $day) . 'T' . join(':', $hour, $min, $sec) . 'Z';
}

sub convert_005_date { 	# yyyymmddhhmmss.0 -> yyyy-mm-ddThhmmssZ 
  my $datestamp = shift;
  my ($year, $month, $day, $hour, $min, $sec) = $datestamp =~ /(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})\./;
  return join('-', $year, $month, $day) . 'T' . join(':', $hour, $min, $sec) . 'Z';
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

sub addMarcNamespace  {	# add marc: namespace to marcxml record
  my $source_xml_string = shift;

  my $remove_ns_url = 'xmlns="http://www.loc.gov/MARC21/slim"';
  $source_xml_string =~ s/$remove_ns_url//g;

  my $bad_url = 'http://www.loc.gov/ standards/';
  my $fix_url = 'http://www.loc.gov/standards/';
  $source_xml_string =~ s/$bad_url/$fix_url/g;

  my $source = $parser->parse_string($source_xml_string);
  my $results = $stylesheet->transform( $source );

  my $source_with_ns = $stylesheet->output_as_chars( $results );
  return $source_with_ns;
}

#sub marc2dc  {	# convert marcxml to oaidc
#  my $source_xml_string = shift;
#
#  my $source = $parser->parse_string($source_xml_string);
#  my $results    = $styleDC2MarcSheet->transform( $source );
#  return $stylesheet->output_as_chars( $results );
#}

sub getDate {
  my $inputDate = shift;
  if (!defined($inputDate)) { $inputDate = time; }
  my ($ss,$mm,$hh,$day,$mon,$yr,$wday,$yday,$isdst) = localtime($inputDate);
  my $year = $yr + 1900;
  $mon++;
  #my $fmtdate = sprintf("%4.4d-%2.2d-%2.2d",$year,$mon,$day);
  #my $fmtdate = sprintf("%4.4d%2.2d%2.2d",$year,$mon,$day);
  my $fmtdate = sprintf("%4.4d-%2.2d-%2.2dT%2.2d:%2.2d:%2.2dZ",$year,$mon,$day,$hh, $mm, $ss);
  return $fmtdate;
}

sub delete_record {
  my $recID = shift;
  my $from_date = shift;
  return join('',
    "<record>\n<header status=\"deleted\">\n<identifier>oai:HathiTrust:MIU01-",
    $recID,
    "</identifier>\n<datestamp>",
    $from_date,
    "</datestamp>\n<setSpec>MDP</setSpec>\n</header>\n</record>\n");
}
