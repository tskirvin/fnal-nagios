# FNAL::Nagios - tool suite to interact with Nagios at FNAL

Various organizations within the Fermi National Accelerator Laboratory
(FNAL) use Nagios for internal host and service monitoring.  These scripts
and libraries provide an interface between these Nagios configurations and
our local Service Now service (see https://github.com/tskirvin/fnal-snow
for more details).

The primary goal of this tool suite is to provide a way for Nagios to
create tickets in our local ticketing system (Service Now) associated with
Host or Service outages.  When the problem is cleared, the tickets will be
automatically closed.  This suite does include some related tools.

Much of this work depends on Monitoring::Livestatus:

    http://search.cpan.org/dist/Monitoring-Livestatus/

-------------------------------------------------------------------------------

# Installation

## From RPM

FNAL::Nagios is distributed internally as an RPM.  I don't really know how
to distribute it in a way that makes my local policy folks happy right now
(to the point, I don't know about releasing the prereq RPMs).

A sample .spec file is included.

## From Source

Right now, the code is at:

    https://github.com/tskirvin/fnal-nagios

This should *probably* work:

    perl Makefile.PL
    make
    make install

You'll need the following Perl prerequisites:

* FNAL::SNOW - https://github.com/tskirvin/fnal-snow
* Monitoring::Livestatus - http://search.cpan.org/dist/Monitoring-Livestatus/
* YAML - http://search.cpan.org/dist/YAML/

## Configuration

A sample configuration file is provided in `etc/fnal/nagios.yaml'.  This
is designed for our local configuration, and will need some work.  See
`man FNAL::Nagios` for details.

A sample Nagios configuration is included in `etc/nagios/conf.d/snow.cfg`.

Nagios itself should have Livestatus configured.  The configuration should look 
something like:

    broker_module=/usr/lib64/check_mk/livestatus.o /var/run/nagios/rw/live

This is provided by the `check-mk-livestatus` rpm on our systems; you'll
have to find the equivalent on non-RHEL systems.

-------------------------------------------------------------------------------

# Scripts

## nagios-backend

`nagios-backend` provides a command-line interface to a variety of nagios
administration commands, specifically:

* ack - acknowledge host/service alerts
* downtime - schedule host/service downtimes
* schedule - schedule the next time a host/service is checked

## nagios-report

`nagios-report` creates a human-readable report on current Nagios issues
affecting your server.  

## nagios-to-snow, snow-to-nagios

`nagios-to-snow` is used to create and manage Incidents in Service Now
associated with PROBLEM, ACK, and RECOVERY actions.  A list of open
incidents is stored in a central directory.  This is meant to be invoked
by host and/or service alets.

`snow-to-nagios` is used to query Service Now and report its findings back
to Nagios.  It should be invoked via cron.

-------------------------------------------------------------------------------

# API

The above scripts depend on the `FNAL::Nagios` perl library.  This library
is probably useful for other purposes.
