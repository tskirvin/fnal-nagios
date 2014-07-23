package FNAL::Nagios;

=head1 NAME

FNAL::Nagios -

=head1 SYNOPSIS

  use FNAL::Nagios;

  our $CONFIG = FNAL::Nagios->load_yaml ($CONFIG_FILE);
  our $SN = FNAL::Nagios->connect_to_sn ($CONFIG);

=head1 DESCRIPTION

=cut

##############################################################################
### Configuration ############################################################
##############################################################################

our $BASEDIR = '/srv/monitor/snow-incidents';
our $CONFIG_FILE = '/etc/snow/nagios.yaml';

our $DEBUG = 0;
our @ARGS_ORIG = @ARGV;

use vars qw/$SN $CONFIG/;

##############################################################################
### Declarations #############################################################
##############################################################################

use strict;
use warnings;

use Class::Struct;
use Data::Dumper;
use Exporter;
use MIME::Lite;
use FNAL::SNOW;
use YAML::Syck;

our @ISA       = qw/Exporter/;
our @EXPORT    = qw//;
our @EXPORT_OK = qw/debug error_mail set_config/;

##############################################################################
### Subroutines ##############################################################
##############################################################################

=head1 FUNCTIONS

=over 4

=item ack 

=cut

sub ack {
    my (%args) = @_;

    my $comment = $args{'comment'} || return 'must set comment';
    my $host    = $args{'host'}    || return 'must set host';
    my $svc     = $args{'service'} || '';
    my $user    = $args{'user'}    || '*unknown*';

    my $cmd;
    if ($host && $svc) {
        $cmd = sprintf ("[%s] ACKNOWLEDGE_SVC_PROBLEM;%s;%s",
            time, $host, $svc);
    } elsif ($host) {
        $cmd = sprintf ("[%s] ACKNOWLEDGE_HOST_PROBLEM;%s", time, $host);
    } else { return 'bad usage; must set either host or svc' }

    return external_command ($cmd, 1, 1, 1, $user, $comment);
}

=item connect_to_sn (CONFIG)

Creates the Service Now object if we don't already have it.  This includes
connecting to the server.

=cut

sub connect_to_sn {
    my ($config) = @_;
    $config ||= FNAL::Nagios->load_yaml ($CONFIG_FILE);

    if ($SN && ref $SN) {
        debug ("Already connected to Service Now");
    } else {
        my $snow_config = $config->{snowConfig};

        debug ("Creating FNAL::SNOW object from '$snow_config'");
        $SN = FNAL::SNOW->init (
            'config_file' => $snow_config, 'debug' => $DEBUG);

        debug ("Connecting to SN at " . $SN->config_hash->{servicenow}->{url});
        $SN->connect or die "could not connect to SN\n";
        $CONFIG = $config;
    }
    return $SN;
}

=item debug (MSG)

Print a debugging message to STDERR if $DEBUG is set. 

=cut

sub debug { if ($DEBUG) { warn "@_\n" } }

=item downtime ()

[...]

=cut

sub downtime {
    my (%args) = @_;

    my $comment = $args{'comment'} || return 'must set comment';
    my $host    = $args{'host'}    || return 'must set host';

    my $hours   = $args{'hours'}   || 0;
    my $start   = $args{'start'}   || time;
    my $svc     = $args{'service'} || '';
    my $user    = $args{'user'}    || '*unknown*';

    my $duration = $hours * 3600;

    my $cmd;
    if ($host && $svc) {
        $cmd = sprintf ("[%s] SCHEDULE_SVC_DOWNTIME;%s;%s",
            $start, $host, $svc);
    } elsif ($host) {
        $cmd = sprintf ("[%s] SCHEDULE_HOST_DOWNTIME;%s", $start, $host);
    } else { return 'bad usage; must set either host or service' }

    return external_command ($cmd, $start, $start + $duration, 1, 0, 
        $duration, $user, $comment );
}

=item error_mail (SUBJECT, BODY, ERROR)

Send an error email, based on $CONFIG->{errorMail} and the passed in values.

=cut

sub error_mail {
    my ($subject, $body, $errorText) = @_;

    my @debug;
    push @debug, "=====[ DEBUG ]=====";
    push @debug, "command line:", "  $0 @ARGS_ORIG", '';

    my $save = $Data::Dumper::Indent;
    $Data::Dumper::Indent = 1;
    push @debug, "config object (created by Data::Dumper): ",
        Dumper ($CONFIG), '';
    $Data::Dumper::Indent = $save;

    push @debug, "=====[ /DEBUG ]=====";

    my @text;
    push @text, "=====[ TEXT ]=====";
    foreach (split "\n", $body) {
        chomp;
        push @text, $_;
    }
    push @text, "=====[ /TEXT ]=====";

    my $prefix = $CONFIG->{nagios}->{errorMail}->{subjectPrefix};

    my $msg = MIME::Lite->new (
        Subject => "[$prefix] $subject",
        From    => $CONFIG->{errorMail}->{from},
        To      => $CONFIG->{errorMail}->{to},
        Data    => join ("\n", $errorText, '', @text, '', @debug, ''),
    );

    if ($DEBUG) {
        $msg->print (\*STDOUT);
    } else {
        $msg->send;
        print $errorText, "\n";
    }

    exit -1;
}

=item external_command (COMMAND)

Write out a command to the external nagios command pipe.  This is a named 
pipe that takes pre-formatted commands, and doesn't return anything (which is
annoying).

Dies if we can't write to the pipe for some reason (usually because we don't
have permissions), returns undef otherwise.

=cut

sub external_command {
    my (@command) = @_;
    my $cmd = join (';', @command);
    my $pipe = $CONFIG->{nagios}->{cmdPipe};
    open (CMD, "> $pipe") or die "could not write to $pipe: $@\n";
    print CMD "$cmd\n";
    close CMD;
    return undef;
}

=item load_yaml I<FILE>

Load a configuration file object from a YAML file.  Dies if we can't open
the file for some reason.

=cut

sub load_yaml {
    my ($self, $file) = @_;
    $file ||= $CONFIG_FILE;
    my $yaml = YAML::Syck::LoadFile ($file);
    unless ($yaml) { die "could not open $file: $@\n" }
    $CONFIG = $yaml;
    return $yaml;
}

=item nagios_url (HOST, SVC)

Returns a URL pointing at given host/service pair based on the contents of the
F<nagios> configuration section.

=cut

sub nagios_url {
    my ($self, $host, $svc) = @_;
    unless ($CONFIG) { $self->load_yaml }
    my $config  = $CONFIG;
    my $urlbase = $config->{nagios}->{url};
    my $site    = $config->{nagios}->{site};

    if (lc $config->{nagios}->{style} eq 'check_mk') {
        return $svc ? _nagios_url_cmk_svc  ($urlbase, $site, $host, $svc)
                    : _nagios_url_cmk_host ($urlbase, $site, $host);
    } else {
        return $svc ? _nagios_url_extinfo_svc  ($urlbase, $site, $host, $svc)
                    : _nagios_url_extinfo_host ($urlbase, $site, $host);
    }
}

=item incidentAck (INCIDENT, ARGS)

=cut

sub incidentAck {
    my ($incident, %args) = @_;
    my $text  = $args{'text'} || 'unknown text';
    my $user  = $args{'user'} || 'unknown user';
    if (my $number = $incident->incident) {
        debug "Incident '$number': acknowledging";
        $SN->tkt_update ($number,
            'assigned_to'    => $user,
            'incident_state' => '2',
        ) or return 'error on incident update';
        $SN->tkt_update ($number,
            'type'     => 'comments',
            'comments' => _make_notes (
                'Acked in Nagios by', $user,
                'Nagios comment',     $text,
            )
        ) or return 'error on journal update';
    } else {
        return 'no incident number';
    }
    return;
}

=item incidentCreate (INCIDENT, ARGS)

=cut

sub incidentCreate {
    my ($incident, %args) = @_;
    my $ticket  = $args{'ticket'}  || return 'no ticket';

    debug ("Creating new entry in Service Now");
    my $number = $SN->tkt_create ('incident', %{$ticket});
    return 'unable to create ticket' unless $number;

    my $url = FNAL::Nagios->nagios_url ($incident->host, $incident->service);

    $SN->tkt_update ($number, 
        'type'       => 'work_notes',
        'work_notes' => _make_notes (
            'URL'         => "<a href='$url' target='_blank'>$url</a>",
            'Nagios Site' => $incident->site || ''
        )
    );

    return $number;
}

=item incidentRecovery (INCIDENT, ARGS)

=cut

sub incidentRecovery {
    my ($incident, %args) = @_;
    my $text = $args{'text'} || 'unknown text';
    if (my $number = $incident->incident) {
        debug ("Updating '$number' on Service Now");
        $SN->tkt_update ($number,
            'closed_by'      => $CONFIG->{ticket}->{caller_id},
            'close_code'     => 'Other (must describe below)',
            'close_notes'    => $text,
            'incident_state' => '6',
        ) or return 'error on incident update';

        debug ("Adding work_notes entry to '$number'");
        $SN->tkt_update ($number,
            'type'       => 'work_notes',
            'work_notes' => _make_notes ('Automated Message', $text)
        ) or return 'error on journal update';
    } else {
        return 'no incident number';
    }
    return;
}

sub incidentReset {
    my ($incident, %args) = @_;
    my $text = $args{'text'} || 'unknown text';
    if (my $number = $incident->incident) {
        debug ("Updating '$number' on Service Now");
        $SN->tkt_update ($number, {
              'incident_state' => '1',
              'watch_list'     => $CONFIG->{ticket}->{watch_list}
        }) or return 'error on incident update';

        debug ("Adding comments entry to '$number'");
        $SN->tkt_update ($number, {
            'type'       => 'comments',
            'work_notes' => $text
        }) or return 'error on journal update';
    } else {
        return 'no incident number';
    }
    return;
}

=item schedule_next ()

[...]

=cut

sub schedule_next {
    my (%args) = @_;

    my $comment = $args{'comment'} || return 'must set comment';
    my $host    = $args{'host'}    || return 'must set host';

    my $minutes = $args{'minutes'} || 0;
    my $start   = $args{'start'}   || time;
    my $svc     = $args{'service'} || '';
    my $user    = $args{'user'}    || '*unknown*';

    my $at = $minutes * 60;

    my $cmd;
    if ($host && $svc) {
        $cmd = sprintf ("[%s] SCHEDULE_FORCED_SVC_CHECK;%s;%s",
            $start, $host, $svc);
    } elsif ($host) {
        $cmd = sprintf ("[%s] SCHEDULE_FORCED_HOST_CHECK;%s", 
            $start, $host);
    } else { return 'bad usage; must set either host or service' }

    return external_command ($cmd, $start, $user);
}

=item set_config (FIELD [, FIELD [, FIELD [, FIELD]]], VALUE)

Update the valies in $CONFIG.  The final argument is the value to be set; the
first (up to 4) are the levels deep of update to make.  This is pretty hack-y,
but it's good as a helper function.

=cut

sub set_config {
    if    (scalar (@_) < 2)  { die "too few arguments in set_config: $@\n"; }
    elsif (scalar (@_) == 2) {
       $CONFIG->{$_[0]} = $_[1];
    }
    elsif (scalar (@_) == 3) {
       $CONFIG->{$_[0]}->{$_[1]} = $_[2];
    }
    elsif (scalar (@_) == 4) {
       $CONFIG->{$_[0]}->{$_[1]}->{$_[2]} = $_[3];
    }
    elsif (scalar (@_) == 5) {
       $CONFIG->{$_[0]}->{$_[1]}->{$_[2]}->{$_[3]} = $_[4];
    }
    else                     { die "too many arguments in set_config: $@\n"; }
}

=item usernameByName (name)

=cut

sub usernameByName {
    my ($name) = @_;
    return unless $name;

    debug ("looking up user '$name' in sys_user");
    my @entries = $SN->users_by_username ($name);
    if (scalar @entries > 1) {
        debug ("too many matches for 'sys_user' '$name'");
        return undef
    } elsif (scalar @entries < 1) {
        debug ("no matches for 'sys_user' '$name'");
        return undef;
    }
    my $email = $entries[0]->{'dv_email'};
    my ($username) = ($email =~ /(.*)@.*/);
    return $username;
}

=back

=cut

##############################################################################
### Internal Subroutines #####################################################
##############################################################################

sub _error_usage { die "@_\n" }

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

### _make_notes (MSG)
# Generate a formatted error message for text fields in SN.

sub _make_notes {
    my @return;
    while (@_) { push @return, sprintf ("<b>%s</b>: %s", shift, shift) }
    return "[code]<br />" . join('<br />', @return) . "[/code]"
}

sub _nagios_url_extinfo_host {
    my ($base_url, $omd_site, $host) = @_;
    return join ('/', $base_url, "cgi-bin", "extinfo.cgi?type=1&host=${host}")
}

sub _nagios_url_extinfo_svc {
    my ($base_url, $omd_site, $host, $svc) = @_;
    return join ('/', $base_url, "cgi-bin",
        "extinfo.cgi?type=2&host=${host}&service=${svc}");
}

sub _nagios_url_cmk_host {
    my ($base_url, $omd_site, $host) = @_;
    return join ('/', $base_url, $omd_site, "check_mk",
        "index.py?start_url=view.py?view_name=hoststatus&site=&host=${host}");
}

sub _nagios_url_cmk_svc {
    my ($base_url, $omd_site, $host, $svc) = @_;
    return join ('/', $base_url, $omd_site, "check_mk",
        "index.py?start_url=view.py?view_name=service&host=${host}&service=${svc}");
}

##############################################################################
### Final Documentation ######################################################
##############################################################################

=head1 CONFIGURATION FILE 

[...]

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
