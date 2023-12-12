FROM ruby:3.2

ARG UNAME=app
ARG UID=1000
ARG GID=1000

RUN apt-get update && apt-get install -y \
  bsd-mailx \
  cpanminus \
  msmtp \
  netcat-traditional \
  perl \
  pigz

RUN cpanm -n  \
  Data::Dumper \
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
  YAML

RUN groupadd -g ${GID} -o ${UNAME}
RUN useradd -m -d /app -u ${UID} -g ${GID} -o -s /bin/bash ${UNAME}
RUN mkdir -p /gems && chown ${UID}:${GID} /gems

ENV ROOTDIR /usr/src/app
ENV BUNDLE_PATH /gems

USER app
COPY . $ROOTDIR
WORKDIR $ROOTDIR

CMD run_process_zephir_incremental.sh
