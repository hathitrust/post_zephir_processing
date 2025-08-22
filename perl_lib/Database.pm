package Database;

use strict;
use warnings;
use utf8;

# Shared utility for read-only connection to Rights DB (via views in ht database)
# or, for populate_rights_data.pl, read-write access to the Rights DB directly.

use DBI;

my $DB_ENV = {
  'ht_ro' => [
    'MARIADB_HT_RO_USERNAME',
    'MARIADB_HT_RO_PASSWORD',
    'MARIADB_HT_RO_DATABASE',
    'MARIADB_HT_RO_HOST'
  ],
  'rights_rw' => [
    'MARIADB_RIGHTS_RW_USERNAME',
    'MARIADB_RIGHTS_RW_PASSWORD',
    'MARIADB_RIGHTS_RW_DATABASE',
    'MARIADB_RIGHTS_RW_HOST'
  ],
};

sub get_ht_ro_dbh {
    return _get_dbh('ht_ro');
}

sub get_rights_rw_dbh {
    return _get_dbh('rights_rw');
}

sub _get_dbh {
    my $database_option = shift;

    my ($dbuser, $passwd, $dbname, $hostname) = map { $ENV{$_}; } @{$DB_ENV->{$database_option}};
    my $extra_params = {
        'RaiseError' => 1,
    };

    my $dbh = DBI->connect(
        "DBI:MariaDB:$dbname:$hostname",
        $dbuser,
        $passwd,
        $extra_params
    );

    return $dbh;
}

1;
