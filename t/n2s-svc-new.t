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
    --ciName testing_host --serviceName testing_svc \
    --subject "fake alert: problem with fake service testing" \
    --omdSite testing --debug
