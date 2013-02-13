#!/bin/bash
AREA_ID="${1,,}"; AREA_ID=${AREA_ID%.inc}
USER_HOME="$(getent passwd $(whoami) | cut -d: -f6)"
CONF="$USER_HOME/conf/${AREA_ID}.inc"
[[ -f $CONF ]] || { 
 echo "No such config $CONF"
 exit 1
}
export GFS_CUSTOM_PARS="$CONF"
source $USER_HOME/bin/NCEP.inc
doCollectCSV
