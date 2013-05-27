#!/bin/bash
slf="${0##*/}"
unset DEBUG
source /opt/scripts/functions/debug.func
source /opt/scripts/functions/parex.inc
log_open /var/log/grib/grab_ncep.log
ID='rostov-on-don'
while getopts 'xTA:' key; do
 case $key in
  A) ID="$OPTARG" ;;
  x) export DEBUG=1; set -x ;; 
  T) flTestOut=1 ;;
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
 startDate=$1; shift
 endDate=${1:-$(getLatestDataTS)}; shift
 if [[ $@ ]]; then
  hours="$@"
 else
  hours='{00..18..6}'
 fi
 nDays=$(( ( $(date -d ${endDate:0:8} +%s) - $(date -d $startDate +%s) )/(24*3600) + 1 ))
 for ((i=0; i<nDays; i++)); do
  YMD=$(date -d "$startDate +${i} days" +%Y%m%d)
  for hint in $hours; do
   for H in $(eval "echo $hint"); do
    push_task <<<"${flTestOut:+echo} doCollectCSV ${YMD}${H}"
   done
  done
 done
 wait4_all_gone
else
 doCollectCSV
fi
