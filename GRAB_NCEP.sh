#!/bin/bash
GFS_CUSTOM_PARS='/etc/grib/rostov-on-don.inc'
source ${USER_HOME:=$(getent passwd $(whoami) | cut -d: -f6)}/bin/grib-scriptset/NCEP.inc
if [[ $1 ]]; then
 startDate=$1
 endDate=${2:-$(getLatestDataTS)} 
 nDays=$(( ( $(date -d ${endDate:0:8} +%s) - $(date -d $startDate +%s) )/(24*3600) + 1 ))
 for ((i=0; i<nDays; i++)); do
  YMD=$(date -d "$startDate +${i} days" +%Y%m%d)
  for ((H=0; H<24; H+=6)); do
   HH="$( ((H<10)) && echo -n '0' )${H}"
   doCollectCSV ${YMD}${HH}
  done
 done
else
 doCollectCSV
fi
