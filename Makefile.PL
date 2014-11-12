use ExtUtils::MakeMaker;

WriteMakefile(
    NAME          => 'FNAL::Nagios',
    DISTNAME      => 'fnal-nagios',
    dist          => { COMPRESS => 'gzip', SUFFIX => 'gz' },
    VERSION_FROM  => 'lib/FNAL/Nagios.pm',
    AUTHOR        => 'Tim Skirvin <tskirvin@fnal.edu>',
    PREREQ_PM     => {
        'FNAL::SNOW'             => '1.00',
        'Monitoring::Livestatus' => '0.74',
        'YAML'                   => '0.70'
    },
);
