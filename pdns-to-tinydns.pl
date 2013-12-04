#!/usr/bin/perl -w
#
# pdns-to-tinydns.pl: a tool to generate a tinydns data.cdb file from a powerdns database.
#
#    Copyright (C) 2013 Max Clark
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

# Configuration
#--
$database = "";
$hostname = "";
$username = "";
$password = "";

# Load necessary perl modules
# --
# use Getopt::Long;
use DBI;

# Usage and help
# --
# sub usage {
# 	print "\n";
# 	print "usage: [*options*]\n";
# 	print "\n";
# 	exit;
# }

# Default values for getopt
# --
# my %opt = ();

# Connect to the DB & prepare queries
# --
my $dbh = DBI->connect("DBI:mysql:database=$database;host=$hostname",
	"$username", "$password", {RaiseError => 1}) || "Couldn't connect to database: " . DBI->errstr;

$domains_sth = $dbh->prepare(q(SELECT id, name
	FROM domains
	ORDER by name)) || "Couldn't prepare statement: " . $dbh->errstr;

$records_sth = $dbh->prepare(q(SELECT name, type, content, ttl, prio
	FROM records
	WHERE type not like 'SOA' and domain_id = ?)) || "Couldn't prepare statement: " . $dbh->errstr;

# Move the old file out of the way and create the filehandle
# --
system("mv /usr/local/tinydns/root/data /usr/local/tinydns/root/data.old");

open DATA, ">/usr/local/tinydns/root/data" or die $!;

# Get the list of domains, loop through them and grab the records
# --
$domains_sth->execute();

while ( @row = $domains_sth->fetchrow_array ) {

	$records_sth->execute($row[0]);

	while ( ( $name, $type, $content, $ttl, $prio ) = $records_sth->fetchrow_array ) {

		$name =~ s/\s//g;
		#$content =~ s/\s//g;
		$ttl =~ s/\s//g;
		$prio =~ s/\s//g;

		$ttl = '86400';

		if ( $type eq "NS" ) {
			print DATA ".$name\:\:$content\:259200\n";
		}
		if ( $type eq "A" ) {
			print DATA "+$name\:$content\:$ttl\n";
		}
		if ( $type eq "CNAME" ) {
			print DATA "C$name\:$content\:$ttl\n";
		}
		if ( $type eq "MX" ) {
			print DATA "\@$name\:\:$content\:$prio\:$ttl\n";
		}
		if ( $type eq "PTR" ) {
			print DATA "\^$name\:$content\:$ttl\n";
		}
		if ( $type eq "TXT" ) {
			$content =~ s/(\W)/sprintf "\\%03o", ord $1/ge;
			print DATA "\'$name\:$content\:$ttl\n";
		}

	}

	$records_sth->finish;

}

# Close and disconnect from the database
#--
$domains_sth->finish;
$dbh->disconnect();

# Read in extra data not present in the database
# --
open EXTRA, "</usr/home/dnsrepl/djbdns/tinydns_data" or die $!;

while (<EXTRA>) {
	next if /^#/;
	print DATA $_;
}

close EXTRA;

close DATA;

# "Make" the .cdb using the tinydns provided Makefile
# --
chdir("/usr/local/tinydns/root");
system("make");
