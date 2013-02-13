#!/bin/bash -x
source ~/bin/NCEP.inc
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
