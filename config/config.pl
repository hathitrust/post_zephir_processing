sub get_rights_user{ return 'ht_rights' };
sub get_rights_password{ return 'ht_rights' };
sub get_rights_host{ return 'mariadb' };
sub get_rights_db{ return 'ht' };
use File::Basename;
sub get_us_cities_db{ return dirname(__FILE__) . '/../data/us_cities.db'};
1;
