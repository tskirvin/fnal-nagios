package FNAL::Nagios::Incident;

=head1 NAME

FNAL::Nagios::Incident - data files for tracking nagios/SN incidents

=head1 SYNOPSIS

  use FNAL::Nagios::Incident;

  my $i1 = FNAL::Nagios::Incident->create ('testing')
    or die "could not create new incident for 'testing'";
  $i1->incident('INC0000000000001');
  $i1->write or die "could not write\n";

  my $i2 = FNAL::Nagios::Incident->read ('testing')
    or die "could not open existing incident for 'testing'";
  $i2->ack('yes');
  $i2->write or die "could not write\n";

  my $i3 = FNAL::Nagios::Incident->read ('testing')
    or die "could not open existing incident for 'testing'";
  $i3->unlink or die "failed to unlink: $@\n";

=head1 DESCRIPTION

FNAL::Nagios::Incident manages data files for tracking Nagios incidents and
their relaion to Service Now.  It 

=head1 DATA STRUCTURE

This object is a B<Class::Stuct> object with the following fields:

    ack         Is this incident ack'd in Nagios?  
    filename    Where is this incident written/going to be written?
    incident    Incident number
    site        OMD_SITE value for this incident
    sname       'host:svc:id' or 'host'

F<sname> requiers a bit of explanation.  If this is a host alert, then we only
need the hostname; if it's a service alert, we need the hostname, service name,
and (if available) the ID of previous alerts (an ID, defaults to 0).

=cut

##############################################################################
### Configuration ############################################################
##############################################################################

our $BASEDIR = '/srv/monitor/snow-incidents';

##############################################################################
### Declarations #############################################################
##############################################################################

use strict;
use warnings;

use Class::Struct;
use YAML::Syck;

struct 'FNAL::Nagios::Incident' => {
    'ack'      => '$',
    'filename' => '$',
    'incident' => '$',
    'site'     => '$',
    'sname'    => '$',
};

##############################################################################
### Subroutines ##############################################################
##############################################################################

=head1 FUNCTIONS

Not listed: the getter/setter and initialization functions associated with
B<Class::Struct>.

=over 4

=item create (SVCNAME)

Create a new object based on the name I<SVCNAME>, which should either match
F<host|svcname|id> or F<host>.  Sets the filename and sname, and returns the
new object.

=cut

sub create {
    my ($self, $sname) = @_;
    unless (ref $self) { $self = $self->new }
    my $file = join ('/', $BASEDIR, "${sname}.incident");
    $self->filename ($file);
    $self->sname ($sname);
    return $self;
}

=item host

Get the hostname of the alert out of B<sname()>.

=cut

sub host {
    my ($self) = @_;
    my ($host, $service, $id) = split (':', $self->sname);
    return $host;
}

=item id

Get the ID of the alert out of B<sname()>.

=cut

sub id {
    my ($self) = @_;
    my ($host, $service, $id) = split (':', $self->sname);
    return $id;
}

=item print 

Creates a printable string summarizing the content of this object.  Returns
either an array of the lines joined with newlines, or the array itself.

=cut

sub print {
    my ($self) = @_;
    my @return;
    push @return, sprintf (
        "%15s  Host: %-14.14s  Service: %-14.14s  Site: %-10s",
        $self->incident || '(unknown)', 
        $self->host     || '', 
        $self->service  || '()', 
        $self->site     || '(default)');
    push @return, sprintf (" Filename: %s", $self->filename);
    push @return, sprintf (" %s", FNAL::Nagios->nagios_url 
        ($self->host, $self->service));
    return wantarray ? @return : join ("\n", @return, '');
}

=item read

Read in an existing object, and returns the object.

=cut

sub read {
    my $self = create (@_);
    my $file = $self->filename;
    open (IN, '<', $file)
        or ( warn "could not read $file: $@\n" && return undef );
    while (my $line = <IN>) {
        chomp $line;
        if ($line =~ /^ACK=(.*)$/)   { $self->ack ($1) }
        if ($line =~ /^INC=(.*)$/)   { $self->set_incident ($1) }
        if ($line =~ /^SITE=(.*)$/)  { $self->site ($1) }
        if ($line =~ /^SNAME=(.*)$/) { $self->sname ($1) }
    }
    close IN;

    return $self;
}

=item read_dir (DIR)

Create a FNAL::Nagios::Incident object for each matching file in I<DIR>.
Return the array of objects.

=cut

sub read_dir {
    my ($self, $dir) = @_;
    opendir (my $dh, $dir) or die "could not open $dir: $@\n";
    my @files = grep { /\.incident$/ } readdir $dh;
    closedir $dh;
    my @incidents;
    foreach my $file (@files) {
        my ($f) = $file =~ /^(.*).incident$/;
        my $inc = $self->read ($f);
        push @incidents, $inc if $inc;
    }
    return @incidents;
}

=item service

Get the service name of the alert out of B<sname()>.

=cut

sub service {
    my ($self) = @_;
    my ($host, $service, $id) = split (':', $self->sname);
    return $service;
}

=item set_incident

Set the incident number of the object to the full, long-incident name string.
This is necessary because we will occasionally just use the short name of the 
incident number (e.g. '1' instead of 'INC000000000001').

=cut

sub set_incident {
    my ($self, $number) = @_;
    unless (ref $self) { $self = $self->new }
    $self->incident (_incnumber_long($number));
    return $self->incident;
}

=item unlink

Remove the file.

=cut

sub unlink {
    my ($self) = @_;
    unless (ref $self) { $self = $self->read (@_) }
    unlink $self->filename;
}

=item write

Write out the file.

=cut

sub write {
    my ($self) = @_;
    my $file = $self->filename;
    open (OUT, '>' . $file) or die "could not write to $file: $@\n";
    print OUT sprintf ("ACK=%s\n",   ($self->ack || ''));
    print OUT sprintf ("INC=%s\n",   ($self->incident || ''));
    print OUT sprintf ("SITE=%s\n",  ($self->site || ''));
    print OUT sprintf ("SNAME=%s\n", ($self->sname || ''));
    close OUT;
    chmod 0600, $file;
    return 1;
}

=back

=cut

##############################################################################
### Internal Subroutines #####################################################
##############################################################################

sub _incnumber_short {
    my ($inc) = @_;
    $inc =~ s/^(INC)?0+//;
    return $inc;
}

sub _incnumber_long {
    my ($incident) = @_;
    my ($number) = $incident =~ /^(?:INC)?(\d+)$/;
    unless ($number) { return undef }
    return sprintf ("INC%012d", $number);
}

##############################################################################
### Final Documentation ######################################################
##############################################################################

=head1 REQUIREMENTS

B<Class::Struct>

=head1 SEE ALSO

B<nagios-to-snow>, B<snow-to-nagios>

=head1 AUTHOR

Tim Skirvin <tskirvin@fnal.gov>, based on code by Tyler Parsons
<tyler.parsons-fermilab@dynamicpulse.com>

=head1 LICENSE

Copyright 2014, Fermi National Accelerator Laboratory

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself.

=cut

1;
