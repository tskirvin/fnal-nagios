package FNAL::Nagios::Incident;

=head1 NAME

FNAL::Nagios::Incident - 

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut

##############################################################################
### Configuration ############################################################
##############################################################################

our $BASEDIR = '/srv/monitor/snow-incidents';

our $SN = undef;

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

=over 4

=item ack

=item create

=cut

sub create {
    my ($self, $sname) = @_;
    unless (ref $self) { $self = $self->new }
    my $file = join ('/', $BASEDIR, "${sname}.incident");
    $self->filename ($file);
    $self->sname ($sname);
    return $self;
}

=item filename

=item host

[...]

=cut

sub host {
    my ($self) = @_;
    my ($host, $service, $id) = split (':', $self->sname);
    return $host;
}

=item incident

=item print 

=cut

sub print {
    my ($self) = @_;
    my @return;
    push @return, sprintf ("%15s  Host: %-14.14s  Service: %-14.14s  Site: %-10s",
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

=cut

sub service {
    my ($self) = @_;
    my ($host, $service, $id) = split (':', $self->sname);
    return $service;
}

=item set_incident

=cut

sub set_incident {
    my ($self, $number) = @_;
    unless (ref $self) { $self = $self->new }
    $self->incident (_incnumber_long($number));
    return $self->incident;
}

=item sname

=item unlink

=cut

sub unlink {
    my ($self) = @_;
    unless (ref $self) { $self = $self->read (@_) }
    unlink $self->filename;
}

=item write

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

B<snow-alert-create>

=head1 AUTHOR

Tim Skirvin <tskirvin@fnal.gov>, based on code by Tyler Parsons
<tyler.parsons-fermilab@dynamicpulse.com>

=head1 LICENSE

Copyright 2014, Fermi National Accelerator Laboratory

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself.

=cut

1;
