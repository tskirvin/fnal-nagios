#!/bin/bash -e
## Test Suite for creating new incidents

##############################################################################
### Configuration ############################################################
##############################################################################

. `pwd`/config.sh

##############################################################################
### main () ##################################################################
##############################################################################

echo "(sample)" | nagios-to-snow --type PROBLEM \
    --state DOWN \
    --ci testing_host --servicename testing_svc \
    --subject "fake alert: problem with fake service testing" \
    --omdSite testing --debug
