#!/usr/bin/env perl

use strict;
use blib;
use vars qw(%opts);

use Net::Nslookup;
use Getopt::Std;

getopt('d', \%opts);

use constant A  => "64.28.67.80";
use constant MX => (qw|209.85.157.220 216.246.96.102|);
use constant NS => (qw|198.246.0.4 207.8.52.206 198.7.0.1|);

END { print "not ok\n" unless $::loaded; }
BEGIN { $| = 1; print "1..4\n"; }

$::loaded = 1;
print "ok 1\n";


{
    my $a = nslookup("use.perl.org");
    my $ok = ($a eq A) ? "" : "not ";
    print STDERR "\t`$a'\n" if exists $opts{'d'};
    print "${ok}ok 2\n";
}

{
    my $mx = nslookup(qtype => "MX", domain => "perl.org");
    my $ok = (grep /^$mx$/, MX) ? "" : "not ";
    print STDERR "\t`$mx'\n" if exists $opts{'d'};
    print "${ok}ok 3\n";
}

{
    my $ns = nslookup(qtype => "NS", domain => "perl.org");
    my $ok = (grep /^$ns$/, NS)  ? "" : "not ";
    print STDERR "\t`$ns'\n" if exists $opts{'d'};
    print "${ok}ok 4\n";
}
