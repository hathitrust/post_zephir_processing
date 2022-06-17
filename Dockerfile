FROM perl:5.34

WORKDIR /usr/src/app

RUN cpanm -n  \
  YAML \
  JSON::XS \
  URI::Escape \
  LWP::Simple \
  MARC::Record \
  MARC::Batch \
  MARC::Record::MiJ \
  MARC::File::XML \
  Exporter \
  Sys::Hostname \
  DBI \
  Data::Dumper \
  MARC \
  MARC::Record::MiJ \
  MARC::File::XML \
  DB_File \
  LWP::Simple \
  XML::LibXML \
  XML::LibXSLT \
  Test::More \
  Test::Output \
  DBD::mysql \
  File::Slurp \
  Data::Dumper
