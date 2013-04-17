#!/bin/bash

####
#
#Execution time for 1 day: 2m 35s
#
slf="${0##*/}"

source ${0%/*}/GRIB2DEF.inc

flDontUseGridConv=0
while getopts 's: d: g: Gx' key; do
 case $key in
  x) set -x		  ;;
  s) grb2Path="$OPTARG"   ;;
  d) csvPath="$OPTARG"    ;;
  g) GRID_BOUND="$OPTARG" ;;
  G) flDontUseGridConv=1  ;;
  \?|*) : ;;
 esac
done
shift $((OPTIND-1))

getDateCmdArg $@

csvPath="${csvPath:-$GFS_COOKED_CSV}/$DATE"
grb2Path="${grb2Path:-$GFS_RAW_NAMOS}/$DATE"

[[ $GRID_BOUND ]]; (( flDontUseGridConv|=$? ))

mkdir -p "$csvPath"
cd       "$grb2Path"

for GRB2_FILE in $(ls -1 *.grb2); do
    unset PID2CSV; declare -A PID2CSV
    while read -r GFS_PAR_AT_LVL; do
     CSV_FILE=gfs_4_$(sed -r 's/^gfs_4_//; s/\.grb2$//' <<<"$GRB2_FILE")_$(echo "$GFS_PAR_AT_LVL" | cut -d: -f4,5 | sed -r 's%\s+%_%g; s%:%-%g').csv
     
     [[ -f $CSV_FILE && $(stat -c %s $CSV_FILE) -gt 0 ]] && continue
     
     if (( flDontUseGridConv )); then
      ( wgrib2 -i $grb2Path/$GRB2_FILE -spread           ${csvPath}/$CSV_FILE        &>>$grb2Path.log <<<"$GFS_PAR_AT_LVL" ) &      
     else
      ( wgrib2 -i $grb2Path/$GRB2_FILE -lola $GRID_BOUND ${csvPath}/$CSV_FILE spread &>>$grb2Path.log <<<"$GFS_PAR_AT_LVL" ) &
     fi
     PID2CSV[$!]="${csvPath}/$CSV_FILE"
    done < <(wgrib2 ${grb2Path}/$GRB2_FILE)
    for pid in ${!PID2CSV[@]}; do
     wait $pid 2>/dev/null
     (( $? )) && rm -f "${PID2CSV[$pid]}"
    done
done
