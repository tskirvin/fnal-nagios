Name:           fnal-nagios
Summary:        Libraries and scripts to interact with Nagios at FNAL
Version:        0
Release:        1%{?dist}
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

rsync -Crlpt ./usr ${RPM_BUILD_ROOT}

%clean
# Adding empty clean section per rpmlint.  In this particular case, there is 
# nothing to clean up as there is no build process

%files
/usr/lib64/nagios/plugins/check_nexsan

%changelog
* Mon Jul 07 2014   Tim Skirvin <tskirvin@fnal.gov>   0-1
- initial packaging
