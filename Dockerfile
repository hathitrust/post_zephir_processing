FROM perl:5.38

RUN apt-get update && apt-get install -y \
  bsd-mailx \
  msmtp \
  netcat \
  pigz

RUN cpanm -n  \
  Data::Dumper \
  DBD::mysql \
  DB_File \
  DBI \
  Devel::Cover \
  Devel::Cover::Report::Coveralls \
  Exporter \
  File::Slurp \
  https://github.com/hathitrust/progress_tracker.git@v0.9.0 \
  JSON::XS \
  LWP::Simple \
  MARC \
  MARC::Batch \
  MARC::File::XML \
  MARC::Record \
  MARC::Record::MiJ \
  Sys::Hostname \
  Test::More \
  Test::Output \
  URI::Escape \
  XML::LibXML \
  XML::LibXSLT \
  YAML

ENV ROOTDIR /usr/src/app

COPY . $ROOTDIR
WORKDIR $ROOTDIR

CMD run_process_zephir_incremental.sh
