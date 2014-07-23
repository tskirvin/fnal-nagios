package FNAL::Nagios;

=head1 NAME

FNAL::Nagios - tool suite for interacting with Nagios

=head1 SYNOPSIS

  use FNAL::Nagios;

  our $CONFIG = FNAL::Nagios->load_yaml ($CONFIG_FILE);
  our $SN = FNAL::Nagios->connect_to_sn ($CONFIG);

=head1 DESCRIPTION

FNAL::Nagios provides a tool suite 

=cut

##############################################################################
### Configuration ############################################################
##############################################################################

our $CONFIG_FILE = '/etc/fnal/nagios.yaml';

## If set, we will print degugging information to STDERR.
our $DEBUG = 0;

## Used by error_mail, this needs to be stored before the scripts will start
## modifying it.
our @ARGS_ORIG = "$0 @ARGV";

##############################################################################
### Declarations #############################################################
##############################################################################

use strict;
use warnings;

use Class::Struct;
use Data::Dumper;
use Exporter;
use FNAL::SNOW;
use MIME::Lite;
use YAML::Syck;

our @ISA       = qw/Exporter/;
our @EXPORT    = qw//;
our @EXPORT_OK = qw/debug error_mail set_config/;

use vars qw/$SN $CONFIG/;

##############################################################################
### Subroutines ##############################################################
##############################################################################

=head1 FUNCTIONS

=over 4

=item ack (ARGS)

Acknowledge a host or service problem using external_command().  Recognized
fields in ARGS:

   comment      Text of the acknowledgement.  Required.
   host         Which host is associated with the problem?  Required.
   svc          Which service (if any)?
   user         Which user ack'd the problem?

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

=item downtime (ARGS)

Schedule Nagios downtime for a host or service using external_command().  
Recognized fields in ARGS:

    comment     Text for the downtime.  Required.
    host        Hostname.  Required.
    hours       How many hours will this be down?  Defaults to 0.
    service     Service.
    start       When should this start (in seconds-since-epoch)?  
                Defaults to the current timestamp.
    user        Who asked for this downtime?  

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
    push @debug, "command line:", "  @ARGS_ORIG", '';

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

=item schedule_next (ARGS)

Schedule the next time that Nagios will check a host or service, using
external_command().  Recognized fields in ARGS: 

    comment     Text for the downtime.  Required.
    host        Hostname.  Required.
    minutes     How many minutes from now should we schedule this next
                check?  Defaults to 0 (read: immediately).
    start       When should this start (in seconds-since-epoch)?  
                Defaults to the current timestamp.
    service     Service name.
    user        User requesting the check.

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
    my $time = $start + $at;

    my $cmd;
    if ($host && $svc) {
        $cmd = sprintf ("[%s] SCHEDULE_FORCED_SVC_CHECK;%s;%s",
            $start, $host, $svc);
    } elsif ($host) {
        $cmd = sprintf ("[%s] SCHEDULE_FORCED_HOST_CHECK;%s", 
            $start, $host);
    } else { return 'bad usage; must set either host or service' }

    return external_command ($cmd, $time, $user);
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

=item snowAck (INCIDENT, ARGS)

Acknowledge an incident.  This consists of:

    * Updating 'assigned_to' to the person who performed the acknowledgement,
      and setting the 'incident_state' to '2' ('Work In Progress').
    * Creating a new comment journal entry with the text.

I<INCIDENT> is an B<FNAL::Nagios::Incident> object with an included incident
number.  Valid options for the ARGS hash:

   user     User that did the acknowledgement.
   text     Text of the acknowledgement.

Returns an error if there is one, or undef on success.

=cut

sub snowAck {
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

=item snowCreate (INCIDENT, ARGS)

Creates a new incident.  This consists of:

    * Create the ticket with B<tkt_create()>.
    * Create a new work_notes entry with links to the original Nagios
      incident.

I<INCIDENT> is an B<FNAL::Nagios::Incident> object with included host/service
names.  Valid options for the ARGS hash:

    ticket  Hashref containing the key/value pairs of all of the fields
            necessary to create the ticket.  Required.

Returns an error if there is one, or undef on success.

=cut

sub snowCreate {
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

=item snowRecovery (INCIDENT, ARGS)

Resolves an existing incident.  This consists of:

    * Close the incident with appropriate 'closed_by', 'close_code',
      'close_notes' fields, and 'incident_state' to '6' ('Resolved')
     
I<INCIDENT> is an B<FNAL::Nagios::Incident> object with an included incident   
number.  Valid options for the ARGS hash:

    text    Text for the close message.

Returns an error if there is one, or undef on success.

=cut

sub snowRecovery {
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
    } else {
        return 'no incident number';
    }
    return;
}

=item snowReset (INCIDENT, ARGS)

Resets an existing incident.  This consists of:

    * Re-opens the incident with 'incident_state' to '1' ('Open')
     
I<INCIDENT> is an B<FNAL::Nagios::Incident> object with an included incident   
number.  Valid options for the ARGS hash:

    text    Text for the reopen message.

Returns an error if there is one, or undef on success.

=cut

sub snowReset {
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


=item usernameByName (NAME)

Looks up the username of a given I<NAME>, as defined as "the part before the
@fnal.gov".  This may be better put into FNAL::SNOW some day.

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

The configuration is stored in I</etc/fnal/nagios.yaml>.  This file is
YAML-formatted, and should contain at least the following fields:

=over 2

=item cachedir

This directory will be used to store B<FNAL::Nagios::Incident> objects.

=item nagios

=over 2

=item ack

These should be set in any scripts that use this data.

=over 2

=item author

Who sent the ACK?

=item comment

Text assicated with the ACK.

=back

=item cmdPipe

Nagios lets us send commands back to the service by dropping text into a
specific file.  This is the name of that file.

=item errorMail

Configuration for how the emails will look that are sent on error.

=over 2

=item to

Who do the errors go to?

=item from

Who do the errors come from?

=item subjectPrefix

Goes at the start of the subject line.

=back

=item livestatus

This module assumes that you are using Livestatus to query Nagios for
information regarding its current state.  

=over 2

=item default

Default location of the named pipe, if the F<site> is I<default>.

=item prefix, suffix

If we are using style 'check_mk', we will look for the named pipe in 
the file I<prefix>/F<site>/I<suffix>.

=back

=item site

Used when writing up check_mk style URLs, this should be set to the equivalent
of $ENV{OMD_SITE} by any scripts that care about such things.

=item style

What type of nagios service is this?  Valid choices: 'check_mk' or 'nagios'.
This is used to decide how to write up longer URLs.

=item url

Default URL for connecting to this nagios instance.  This is used as a 
template for longer URLs, and you do not need the trailing '/'.

=back

=item snowConfig

Location of the B<FNAL::SNOW::Config> configuration yaml file.

=item ticket

This should contain a list of default values for tickets created by this 
suite.  Feel free to add whichever fields you want, but taking them out
may be dangerous.

=back

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
