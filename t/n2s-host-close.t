#!/bin/bash -e
## Test Suite for creating new incidents

##############################################################################
### Configuration ############################################################
##############################################################################

. `pwd`/config.sh

##############################################################################
### main () ##################################################################
##############################################################################

echo "(sample)" | nagios-to-snow --type RECOVERY \
    --ci testing --state DOWN \
    --subject "fake alert: problem with fake host testing" \
    --omdSite testing --debug
