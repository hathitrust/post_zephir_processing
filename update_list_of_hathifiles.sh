# Generate the list of hathifiles for the website. 
# The daily scripts do this automatically, but very occasionally they need a 
# manual clean up. This is so we don't need to hunt down the appropriate script
# every time.
# run with: 
# sudo -u libadm
eval "$(perl -I/l1/govdocs/zcode/local/lib/perl5 -Mlocal::lib=/l1/govdocs/zcode/local)"
`/htapps/www/sites/www.hathitrust.org/extra_perl/json_filelist.pl >> report.tmp`
