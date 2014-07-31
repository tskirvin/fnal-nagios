Name:           fnal-nagios
Summary:        Libraries and scripts to interact with Nagios at FNAL
Version:        0
Release:        2%{?dist}
Packager:       Tim Skirvin <tskirvin@fnal.gov>
Group:          Applications/System
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
Source0:        %{name}-%{version}-%{release}.tar.gz
BuildArch:      noarch

Requires:       perl perl-YAML fnal-snow perl-Monitoring-Livestatus
BuildRequires:  rsync
Vendor:         FNAL
License:        BSD
Distribution:   CMS
URL:            http://www.fnal.gov/

%description
Libraries and scripts to interact with the nagios/check_mk services 
used at various Fermi National Accelerator Laboratory groups, as well as 
interact with the local Service Now interface.

%prep

%setup -c -n %{name}-%{version}-%{release}

%build
# Empty build section added per rpmlint

%install
if [[ $RPM_BUILD_ROOT != "/" ]]; then
    rm -rf $RPM_BUILD_ROOT
fi

rsync -Crlpt ./etc ${RPM_BUILD_ROOT}
rsync -Crlpt ./usr ${RPM_BUILD_ROOT}
rsync -Crlpt ./srv ${RPM_BUILD_ROOT}

mkdir -p ${RPM_BUILD_ROOT}/usr/share/perl5/vendor_perl
rsync -Crlpt ./lib/ ${RPM_BUILD_ROOT}/usr/share/perl5/vendor_perl

mkdir -p ${RPM_BUILD_ROOT}/usr/share/man/man8
for i in `ls usr/sbin`; do
    pod2man --section 8 --center="System Commands" usr/sbin/${i} \
        > ${RPM_BUILD_ROOT}/usr/share/man/man8/${i}.8 ;
done

mkdir -p ${RPM_BUILD_ROOT}/usr/share/man/man3
pod2man --section 3 --center="Perl Documentation" lib/FNAL/Nagios.pm \
        > ${RPM_BUILD_ROOT}/usr/share/man/man3/FNAL::Nagios.3
pod2man --section 3 --center="Perl Documentation" lib/FNAL/Nagios/Incident.pm \
        > ${RPM_BUILD_ROOT}/usr/share/man/man3/FNAL::Nagios::Incident.3

%clean
# Adding empty clean section per rpmlint.  In this particular case, there is 
# nothing to clean up as there is no build process

%files
%config(noreplace) /etc/fnal/nagios.yaml
%config(noreplace) /etc/nagios/conf.d/snow.cfg
/usr/sbin/*
/usr/share/man/man3/*
/usr/share/man/man8/*
/usr/share/perl5/vendor_perl/FNAL/*
/srv/monitor/nagios-incidents/.HOLD

%changelog
* Mon Jul 23 2014   Tim Skirvin <tskirvin@fnal.gov>   0-2
- nagios-backend fixes to actually (at least partially) work

* Mon Jul 23 2014   Tim Skirvin <tskirvin@fnal.gov>   0-1
- initial packaging
