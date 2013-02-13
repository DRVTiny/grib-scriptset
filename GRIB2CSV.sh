#!/bin/bash -x

####
#
#Execution time for 1 day: 2m 35s
#

source ${0%/*}/GRIB2DEF.inc
while getopts 's: d: g:' key; do
 case $key in
  s) grb2Path="$OPTARG" ;;
  d) csvPath="$OPTARG"  ;;
  g) GRID_BOUND="$OPTARG" ;;
  \?|*) : ;;
 esac
done
shift $((OPTIND-1))
getDateCmdArg $@
csvPath="${csvPath:-$GFS_COOKED_CSV}/$DATE"
grb2Path="${grb2Path:-$GFS_RAW_NAMOS}/$DATE"
mkdir -p $csvPath
touch    $csvPath/daily.csv.grep
cd "$grb2Path"
for GRB2_FILE in $(ls -1 *.grb2 | fgrep -v -f ${csvPath}/daily.csv.grep); do
    echo "$GRB2_FILE" >>  $csvPath/daily.csv.grep
    while read -r GFS_PAR_AT_LVL; do
     CSV_FILE=$(sed -r 's/^gfs_4_//; s/\.grb2$//' <<<"$GRB2_FILE")_$(echo "$GFS_PAR_AT_LVL" | cut -d: -f4,5 | sed -r 's%\s+%_%g; s%:%-%g').csv
     wgrib2 $grb2Path/$GRB2_FILE -i -lola $GRID_BOUND ${csvPath}/$CSV_FILE spread &>>$grb2Path.log <<<"$GFS_PAR_AT_LVL"
    done < <(wgrib2 ${grb2Path}/$GRB2_FILE)
done
