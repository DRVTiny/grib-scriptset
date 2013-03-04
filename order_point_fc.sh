#!/bin/bash
source /opt/scripts/functions/parex.inc

eval_dinv () { 
 local d days month year
 IFS='.' read days month year <<<"$1"
 if [[ ! $year ]]; then
  year=$month
  month=$days
  days='1-'$(date -d "${year}${month}01+1 month-1 day" +%d)
 fi
 for ((d=${days%-*}; d<=${days#*-}; d++)); do
  echo ${year}${month}$(printf '%02g' $d)
 done
 return 0
}

sqr_points () {
 local lat_u="$1" lon_l="$2"
 local lat_d=$(bc <<<"$lat_u-0.5")
 local lon_r=$(bc <<<"$lon_l+0.5")
 echo "$lat_u,$lon_l $lat_u,$lon_r $lat_d,$lon_l $lat_d,$lon_r"
 return 0
}

DATA_ID='ROSTOV2012_Thunder'
nPredictHours=120
doShowUsage () {
 cat <<EOF
Usage:
 ${0##*/} [ -i DATA_ID ] [ -T | -y ] [-s] [-P PREDICT_HOURS] 
EOF
 return 0
}

unset flTestOutCmds flResetSourcePath flParallelExec
while getopts 'ysDTi: P:' k; do
 case $k in
  D) set -x                  ;;
  T) flTestOutCmds=1         ;;
  s) flResetSourcePath=1     ;;
  i) DATA_ID="$OPTARG"       ;;
  P) nPredictHours="$OPTARG" ;;
  y) (( $(fgrep processor /proc/cpuinfo | wc -l) > 1 )) && flParallelExec=1 ;;
  *) doShowUsage; exit 1     ;;
 esac
done
shift $((OPTIND-1))

[[ $flTestOutCmds && $flParallelExec ]] && {
 echo 'You cant specify both -y and -T!'
 doShowUsage
 exit 1
}

declare -A dblocks ul_point

 dblocks[default]='11.2012'
 
# dblocks[RostovOnDon]='05.2012 06.2012 07.2012 08.2012'
ul_point[RostovOnDon]='47.5 39.5'

# dblocks[Remontnoe]='05.2012 06.2012 07.2012 08.2012'
ul_point[Remontnoe]='47.0 43.5'

# dblocks[Kazanskaya]='05.2012 06.2012 07.2012 08.2012'
ul_point[Kazanskaya]='50.0 41.0'

# dblocks[Millerovo]='05.2012 06.2012 07.2012 08.2012'
ul_point[Millerovo]='49.0 40.0'

# dblocks[Taganrog]='05.2012 06.2012 07.2012 08.2012'
ul_point[Taganrog]='47.5 38.5'

# dblocks[Konstantinovsk]='05.2012 06.2012 07.2012 08.2012'
ul_point[Konstantinovsk]='48.0 41.0'



baseDir="/tmp/$DATA_ID"
if [[ -d $baseDir ]]; then
 rm -rf $baseDir/*
else
 mkdir $baseDir
fi

unset wait4pids

if [[ $flTestOutCmds ]]; then
 cmd='cat -'
else
 cmd="parallel eval '${HOME}/bin/point_forecast'"
fi

{
 for meteoStationID in ${!ul_point[@]}; do
  mkdir -p $baseDir/$meteoStationID
  for dblock in ${dblocks[$meteoStationID]-${dblocks[default]}}; do
   mkdir -p $baseDir/$meteoStationID/$dblock
   for day in $(eval_dinv $dblock); do
    for pp in $(sqr_points ${ul_point[$meteoStationID]}); do
     echo "${flTestOutCmds+$HOME/bin/point_forecast}${flResetSourcePath+ -s /store/GRIB/cooked/GFS4/${DATA_ID}} -n -d $baseDir/$meteoStationID/$dblock -H $nPredictHours ${pp/,/ } $day 0"
    done
   done   
  done
 done
} | $cmd
