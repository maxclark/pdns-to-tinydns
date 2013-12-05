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
$tinydns = "/etc/tinydns";

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
system("mv $tinydns/root/data $tinydns/root/data.old");

open DATA, ">$tinydns/root/data" or die $!;

# Get the list of domains, loop through them and grab the records
# --
$domains_sth->execute();

while ( @row = $domains_sth->fetchrow_array ) {

	$records_sth->execute($row[0]);

	while ( ( $name, $type, $content, $ttl, $prio ) = $records_sth->fetchrow_array ) {

		# NAME, TTL and PRIO shouldn't have spaces, if they do strip them.
		# --
		$name =~ s/\s//g;
		$ttl =~ s/\s//g;
		$prio =~ s/\s//g;

		# Set a minimum and maximum TTL value, this does not impact SOA & NS records
		# --
		if ($ttl > 86400) {
			$ttl = '86400';
		}
		elsif ($ttl < 300) {
			$ttl = '300'
		}

		# SOA and NS can be split using "Z" & "&" record types, or combined using just the "."
		# --
		if ( $type eq "SOA" ) {

			# Increase the TTL to 259200
			# --
			$ttl = '259200';

			$content =~ s/([^ ]+) ([^@]+)@([^ ]+) (\d+) (\d+) (\d+) (\d+) (\d+)/$1/;
			$contact = $2 . '.' . $3;
			$serial  = $4;
			$refresh = $5;
			$retry   = $6;
			$expire  = $7;
			$min     = $8;

			$string = 'Z'
				. escapeText( $name ) . ':'
				. escapeText( $content ) . ':'
				. escapeText( $contact ) . ':'
				. $serial . ':'
				. $refresh . ':'
				. $retry . ':'
				. $expire . ':'
				. $min . ':'
				. $ttl;

			print DATA "$string\n";

		}
		elsif ( $type eq "NS" ) {
			# Increase the TTL to 259200
			# --
			$ttl = '259200';

			$string	= '&'
				. escapeText($name) . '::'
				. escapeText($content) . ':'
				. $ttl;

			print DATA "$string\n";
		}
		elsif ( $type eq "A" ) {
			$string = '+'
				. escapeText($name) . ':'
				. escapeText($content) . ':'
				. $ttl;

			print DATA "$string\n";
		}
		elsif ( $type eq "CNAME" ) {
			$string = 'C'
				. escapeText($name) . ':'
				. escapeText($content) . ':'
				. $ttl;

			print DATA "$string\n";
		}
		elsif ( $type eq "MX" ) {
			$string = '@'
				. escapeText($name) . '::'
				. escapeText($content) . ':'
				. $prio . ':'
				. $ttl;

			print DATA "$string\n";
		}
		elsif ( $type eq "PTR" ) {
			$string = '^'
				. escapeText($name) . ':'
				. escapeText($content) . ':'
				. $ttl;

			print DATA "$string\n";
		}
		elsif ( $type eq "TXT" ) {
			$string = "\'"
				. escapeText($name) . ':'
				. escapeText($content) . ':'
				. $ttl;

			print DATA "$string\n";
		}
		elsif ( $type eq "SPF" ) {
			$string = ":"
				. escapeText($name) . ":16:"
            	. characterCount($content)
            	. escapeText($content) . ":"
            	. $ttl;

            print DATA "$string\n";
		}
		elsif ( $type eq "SRV" ) {
			# :sip.tcp.example.com:33:\000\001\000\002\023\304\003pbx\007example\003com\000
			if ( ( $prio >= 0 && $prio <= 65535 ) && ( $weight >= 0 && $weight <= 65535 ) && ( $port >= 0 && $port <= 65535 ) ) {
            	my $target = "";
            	my @chunks = split /\./, $content;
            	foreach my $chunk (@chunks) {
					$target = $target . characterCount($chunk) . $chunk;
            	}
            	$string = ":"
                . escapeText($name) . ":33:"
                . escapeNumber($prio)
                . escapeNumber($weight)
                . escapeNumber($port)
                . $target . "\\000" . ":"
                . $ttl;

                print DATA "$string\n";
			}
			else {
				print "priority, weight or port not within 0 - 65535\n";
			}
		}
		# Not currently supported by the schema, here for reference for future use
		# --
		# elsif ($type eq "NAPTR" ) {
		# 	# :comunip.com:35:\000\012\000\144\001u\007E2U+sip\036!^.*$!sip\072info@comunip.com.br!\000:300
		# 	#                 |-order-|-pref--|flag|-services-|---------------regexp---------------|re-|
		# 	if ( ( $$order >= 0 && $order <= 65535 ) && ( $prefrence >= 0 && $prefrence <= 65535 ) ) {
		# 		$string = ":"
		# 			. escapeText($name) . ":35:"
		# 			. escapeNumber($order)
		# 			. escapeNumber($prefrence)
		# 			. characterCount($flag)
		# 			. $flag
		# 			. characterCount($services)
		# 			. escapeText($services)
		# 			. characterCount($regexp)
		# 			. escapeText($regexp);

		# 		if ( $replacement ne "" ) {
		# 			$result = $result . characterCount($replacement) . escapeText($replacement);
		# 		}

		# 		$string = $string . "\\000:" . $cgi{'ttl'};

		# 		print DATA "$string\n";
		# 	}
		# 	else {
		# 		 print "order or prefrence not within 0 - 65535\n";
		# 	}
		# }
		# elsif ( $type eq "domainKeys" ) {
		# 	# :joe._domainkey.anders.com:16:\341k=rsa; p=MIGfMA0GCSqGSIb3DQ ... E2hHCvoVwXqyZ/MbQIDAQAB
		# 	#                               |lt|  |typ|  |-key----------------------------------------|
		# 	if ( $record{'key'} ne "" ) {
		# 		my $key = $record{'key'};
		# 		$key =~ s/\r//g;
		# 		$key =~ s/\n//g;
		# 		my $line = "k=" . $record{'encryptionType'} . "; p=" . $key;

		# 		$string = ":"
		# 			. escapeText( $record{'domain'} ) . ":16:"
		# 			. characterCount($line)
		# 			. escapeText($line) . ":"
		# 			. $record{'ttl'};

		# 		print DATA "$string\n";
		# 	}
		# 	else {
		# 		print "didn't get a valid key for the key field\n";
		# 	}
		# }
		elsif ( $type eq "AAAA" ) {
			# ffff:1234:5678:9abc:def0:1234:0:0
			# :example.com:28:\377\377\022\064\126\170\232\274\336\360\022\064\000\000\000\000
			if ( $content ne "" && $name ne "" ) {
				$colons = $content =~ tr/:/:/;
				if ($colons < 7) { $content =~ s/::/':' x (9-$colons)/e; }
				( $a, $b, $c, $d, $e, $f, $g, $h ) = split /:/, $content;
				if ( ! defined $h ) {
					print "Didn't get a valid-looking IPv6 address\n";
				}
				else {
					$a = escapeHex( sprintf "%04s", $a );
					$b = escapeHex( sprintf "%04s", $b );
					$c = escapeHex( sprintf "%04s", $c );
					$d = escapeHex( sprintf "%04s", $d );
					$e = escapeHex( sprintf "%04s", $e );
					$f = escapeHex( sprintf "%04s", $f );
					$g = escapeHex( sprintf "%04s", $g );
					$h = escapeHex( sprintf "%04s", $h );

					$string = ":"
						. escapeText($name) . ":28:"
						. "$a$b$c$d$e$f$g$h" . ":"
						. $ttl;

					print DATA "$string\n";
            	}
			}
			else {
				print "didn't get a valid address or domain\n";
			}
    	}
		else {
			print "didn't get a valid record type\n";
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
chdir("$tinydns/root");
system("make");

#--
sub escapeText {
	my $line = pop @_;
	my $out;
	my @chars = split //, $line;

	foreach $char ( @chars ) {
		if ( $char =~ /[\r\n\t: \\\/]/ ) {
			$out = $out . sprintf "\\%.3lo", ord $char;
		}
		else {
			$out = $out . $char;
		}
	}
	return( $out );
}

sub escapeNumber {
	my $number = pop @_;
	my $highNumber = 0;

	if ( $number - 256 >= 0 ) {
		$highNumber = int( $number / 256 );
		$number = $number - ( $highNumber * 256 );
	}
	$out = sprintf "\\%.3lo", $highNumber;
	$out = $out . sprintf "\\%.3lo", $number;

	return( $out );
}

sub escapeHex {
	# takes a 4 character hex value and converts it to two excaped numbers
	my $line = pop @_;
	my @chars = split //, $line;

	$out = sprintf "\\%.3lo", hex "$chars[0]$chars[1]";
	$out = $out . sprintf "\\%.3lo", hex "$chars[2]$chars[3]";

	return( $out );
}

sub characterCount {
	my $line = pop @_;
	my @chars = split //, $line;
	my $count = @chars;

	return( sprintf "\\%.3lo", $count );
}
