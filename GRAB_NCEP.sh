#!/bin/bash
slf="${0##*/}"
source /opt/scripts/functions/debug.func
log_open /var/log/grib/grab_ncep.log
ID='rostov-on-don'
while getopts 'xA:' key; do
 case $key in
  A) ID="$OPTARG" ;;
  x) flDebug=1; set -x ;; 
  \?|*) fatal_ "Unknown key passed to me: $key"; exit 1 ;;
 esac
done
shift $((OPTIND-1))

GFS_CUSTOM_PARS="/etc/grib/$ID.inc"
[[ -f $GFS_CUSTOM_PARS && -r $GFS_CUSTOM_PARS ]] || {
 error_ "Cant read GFS_CUSTOM_PARS=$GFS_CUSTOM_PARS"
 exit 1
}

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
