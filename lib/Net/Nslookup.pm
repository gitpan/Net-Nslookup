package Net::Nslookup;

# -------------------------------------------------------------------
#   Net::Nslookup - Provide nslookup(1)-like capabilities
#
#   Copyright (C) 2001 darren chamberlain <darren@cpan.org>
#
#   This is free software; you can redistribute it and/or modify it
#   under the same terms as Perl itself.
# 
#   This software is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this software. If not, write to the Free Software
#   Foundation, 675 Mass Ave, Cambridge, MA 02139, USA.
# -------------------------------------------------------------------

=head1 NAME

Net::Nslookup - Provide nslookup(1)-like capabilities

=head1 ABSTRACT

Net::Nslookup provides the capabilities of the standard UNIX command
line tool nslookup(1). Net::DNS is a wonderful and full featured module,
but quite often, all you need is `nslookup $host`.  This module
provides that functionality.

=head1 SYNOPSIS

  use Net::Nslookup;
  my @addrs = nslookup $host;

  my @mx = nslookup(qtype => "MX", domain => "perl.org");

=head1 DESCRIPTION

Net::Nslookup exports a single function, called nslookup.  nslookup
can be used to retrieve A, PTR, CNAME, MX, and NS records.

  my $a  = nslookup(host => "use.perl.org", type => "A");

  my @mx = nslookup(domain => "perl.org", type => "MX");

  my @ns = nslookup(domain => "perl.org", type => "NS");

B<nslookup> takes a hash of options, one of which should be ``term'',
and performs a DNS lookup on that term.  The type of lookup is
determined by the ``type'' (or ``qtype'') argument.

If only a single argument is passed in, the type defaults to ``A'',
that is, a normal A record lookup.

If B<nslookup> is called in a list context, and there is more than one
address, an array is returned.  If B<nslookup> is called in a scalar
context, and there is more than one address, B<nslookup> returns the
first address.  If there is only one address returned (as is usually
the case), then, naturally, it will be the only one returned,
regardless of the calling context.

``domain'' and ``host'' are synonyms for ``term'', and can be used to
make client code more readable.  For example, use ``domain'' when
getting NS records, and use ``host'' for A records; both do the same
thing.

=cut

use strict;
use vars qw($VERSION $DEBUG @EXPORT $res @SEARCH);
use base qw(Exporter);

$VERSION = sprintf("%d.%02d", q$Revision: 1.7 $ =~ /(\d+)\.(\d+)/);
@EXPORT  = qw(nslookup);
$DEBUG   = 0 unless defined $DEBUG;
@SEARCH  = () unless @SEARCH;

use Carp;
use Exporter;
use Net::DNS;

my %_lookups = (
    'a'     => \&_lookup_a,
    'cname' => \&_lookup_a,
    'mx'    => \&_lookup_mx,
    'ns'    => \&_lookup_ns,
);
$_lookups{uc $_} = $_lookups{$_} for (keys %_lookups);

# Import gets called when the module is used.  We take advantage of
# this subroutine to get the search or domain information from the
# /etc/resolv.conf.  See resolv.conf(5) for the syntax of this file
# and a decent explanation of the nuances of the process.
sub import {
    my $class = shift;
    if (@_) {
        # If stuff is passed in, then it should
        # be used as search domains
        @SEARCH = @_;
    } elsif (defined $ENV{'LOCALDOMAIN'}) {
        # No stuff passed in; use $ENV{'LOCALDOMAIN'}, if it exists...
        @SEARCH = split /\s+/, $ENV{'LOCALDOMAIN'}; 
    } else {
        # ...or /etc/resolv.conf, if it exists.
        if (-r "/etc/resolv.conf") {
            open RESOLV, "/etc/resolv.conf"
                or warn "Can't open /etc/resolv.conf: $!";
            @SEARCH = split /\s+/, (grep /^(domain|search)/, <RESOLV>)[-1];
            close RESOLV or die "Can't close /etc/resolv.conf: $!";

            shift @SEARCH if @SEARCH;
        }
    }
    ($DEBUG) && carp("Using search path: @SEARCH");
    $class->export_to_level(1, @EXPORT);
}

sub nslookup {
    $res ||= Net::DNS::Resolver->new;
    return unless @_;

    my %options;
    my @answers;

    #
    # One argument calls to nslookup can be turned into
    # a more generic four argument (canonical) form.
    #
    return nslookup(type => "A", term => $_[0]) if (@_ == 1);

    #
    # Any non-hash cases will be incorrent usage at
    # this point. Rather than die, return undef.
    #
    return if (@_ % 2);

    #
    # Now, we have a valid hash.
    #
    %options = @_;

    #
    # Some reasonable defaults.
    #
    $options{'term'} ||= $options{'host'} || $options{'domain'} || return;
    $options{'type'} ||= $options{'qtype'} || "A";

    return unless defined $_lookups{$options{'type'}};
    $_lookups{$options{'type'}}->($options{'term'}, \@answers);

    return $answers[0] if (@answers == 1);
    return (wantarray) ? @answers : $answers[0];
}

sub _lookup_a ($\@) {
    my ($term, $answers) = @_;
    my (@terms, $query);

    # Terms that are fully qualified to the origin (end with a .)
    # and numeric terms (PTR lookups) are not subjected to the
    # search path; everything else is.
    if ($term =~ /\.$/ || $term !~ /[^0-9.]/) {
        @terms = ($term);
    } else {
        # XXX Is this correct?  Can any lookup be suffixed by "."?
        @terms = map "$term.$_", ("", @SEARCH);
    }

    for (@terms) {
        ($DEBUG) && carp("Lookup at ``$_''");
        $query = $res->search($_);
        last if defined $query;
    }

    return unless defined $query;

    $DEBUG && carp("Performing 'A' lookup on `$term'");
    foreach my $rr ($query->answer) {
        if ($rr->type eq "A") {
            push @{$answers}, $rr->address;
        }
        if ($rr->type eq "PTR") {
            push @{$answers}, $rr->ptrdname;
        }
    }
}

sub _lookup_mx ($\@) {
    my ($term, $answers) = @_;

    $DEBUG && carp("Performing 'MX' lookup on `$term'");
    my @mx = mx($res, $term);
    for my $rr (@mx) {
        push @{$answers}, nslookup(type => "A", host => $rr->exchange);
    }
}

sub _lookup_ns ($\@) {
    my ($term, $answers) = @_;
    $DEBUG && carp("Performing 'NS' lookup on `$term'");

    my $query = $res->search($term, "NS") || return;
    for my $rr ($query->answer) {
        push @{$answers}, nslookup(type => "A", host => $rr->nsdname);
    }
}

1;
__END__

=head1 CONTROLLING SEARCH DOMAINS

Similar to nslookup, Net::Nslookup will try to complete host names
that do no appear to be fully qualified.  There are three ways to
specify a search path: first, by passing arguments to the import()
method (called when the module is used):

  use Net::Nslookup qw(perl.org perl.com);

There can be as many domains as you need; they are searched in order,
and the search stops as soon as a match is found.

The second way to set a search path is by setting the environment
variable LOCALDOMAIN to a space-separated list of domains; see
resolv.conf(5) for details.

Finally, ``search'' or ``domain'' entries in /etc/resolv.conf are
honored, using the same rules as nslookup.  The man page for
resolv.conf specifies that the last occurance of either domain or
search is the one that is used; search can be a space-separated list
of domains, similar to the LOCALDOMAIN environment variable.

=head1 DEBUGGING

Set $Net::Nslookup::DEBUG to a true value to get debugging messages
carped to STDERR.

=head1 FUTURE DIRECTIONS

Eventually, this module should be able to work without having Net::DNS
installed; currently, Net::Nslookup's functionality is dependent upon
that module.

=head1 TODO

=over 4

=item *

Support for TXT and SOA records.

=back

=head1 AUTHOR

darren chamberlain <darren@cpan.org>

