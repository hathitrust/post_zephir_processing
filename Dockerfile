FROM ruby:3.4

ENV ROOTDIR=/usr/src/app
ENV HOME=/usr/src/app

# Install Debian packages
RUN apt-get update && apt-get install -y \
    bsd-mailx \
    cpanminus \
    curl \
    git \
    libcrypt-ssleay-perl \
    libdate-manip-perl \
    libdbd-mariadb-perl \
    libdevel-cover-perl \
    libjson-xs-perl \
    libmarc-file-mij-perl \
    libmarc-perl \
    libmarc-record-perl \
    libmarc-xml-perl \
    libmariadb-dev \
    libnet-ssleay-perl \
    libtest-output-perl \
    libwww-perl \
    libxml-libxml-perl \
    libyaml-libyaml-perl \
    msmtp-mta \
    perl \
    pigz \
    ruby-dev

# Install perl modules that we cannot get with apt-get
RUN cpanm --notest \
    Devel::Cover::Report::Coveralls \
    https://github.com/hathitrust/progress_tracker.git@v0.11.1

COPY . $ROOTDIR
WORKDIR $ROOTDIR

# Ruby setup
ENV BUNDLE_PATH=/gems
ENV RUBYLIB=/usr/src/app/lib
RUN bundle config --global silence_root_warning 1
RUN bundle install

CMD ["run_process_zephir_incremental.sh"]
