FROM perl:5.38

RUN apt-get update && apt-get install -y \
  bsd-mailx \
  msmtp \
  pigz \
  ruby-dev

RUN cpanm -n  \
  Data::Dumper \
  Date::Manip \
  DBD::MariaDB \
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
  YAML \
  YAML::XS

ENV ROOTDIR /usr/src/app

COPY . $ROOTDIR
WORKDIR $ROOTDIR

ENV BUNDLE_PATH /gems
ENV RUBYLIB /usr/src/app/lib
RUN gem install bundler
RUN bundle config --global silence_root_warning 1
RUN bundle install

CMD run_process_zephir_incremental.sh
