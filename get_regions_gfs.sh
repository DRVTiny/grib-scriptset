#!/bin/bash -x
for Region in EuropeanRussia Siberia DalniyVostok; do
 GFS_CUSTOM_PARS="/etc/grib/RF-${Region}.inc"
 [[ -f $GFS_CUSTOM_PARS && -r $GFS_CUSTOM_PARS ]] || continue
 source ${USER_HOME:=$(getent passwd $(whoami) | cut -d: -f6)}/bin/grib-scriptset/NCEP.inc
 doCollectCSV
 if [[ -d $GFS_CSV_PATH ]]; then
  for bd in $GFS_CSV_PATH $GFS_RAW_PATH; do
   dirs2del="$(ls -l $bd | awk '$1 ~ /^d/  {print $NF}' | egrep '^[0-9]{8}$' | sort -rn | sed 1d)"
   if [[ $dirs2del ]]; then
    for d in $dirs2del; do
     rm -rf $GFS_CSV_PATH/$d
    done
   fi
  done
 fi
done
