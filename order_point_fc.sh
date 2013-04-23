#!/bin/bash
slf=${0##*/}

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
 local lat_u="$1"
 local lat_d=$(( ${lat_u/./}-5 ))
 local lon_l="$2"
 local lon_r=$(( ${lon_l/./}+5 ))
 lat_d=${lat_d%?}.${lat_d:$((${#lat_d}-1)):1}
 lon_r=${lon_r%?}.${lon_r:$((${#lon_r}-1)):1}
 echo "$lon_l,$lat_u $lon_r,$lat_u $lon_l,$lat_d $lon_r,$lat_d"
 return 0
}

doShowUsage () {
 cat <<EOF
Usage:
 $slf [ -i DATA_ID ] [-d DEST_PATH ] [-e EMAIL_REPORT_TO ] [-m MODE=(standart|extended)] [-P PREDICT_HOURS] [ -T ] [-s] [-x]
EOF
 return 0
}

unset flTestOutCmds flResetSourcePath flParallelExec

TEMP_DIR='/tmp'
DATA_ID='Rostov-On-Don'
nPredictHours=120

while getopts 'yshxTi: P: m: e: d:' k; do
 case $k in
  h) doShowUsage; exit 0      ;;
  x) set -x                   ;;
  T) flTestOutCmds=1          ;;
  s) flResetSourcePath=1      ;;
  d) TEMP_DIR="${OPTARG%/}"   ;;
  i) DATA_ID="${OPTARG// /_}"
     DATA_ID="${DATA_ID//\//:}"
                              ;;
  m) mode="${OPTARG,,}"       ;;
  e) emailTO="$OPTARG"	      ;;
  P) nPredictHours="$OPTARG"  ;;
  y) (( $(fgrep processor /proc/cpuinfo | wc -l) > 1 )) && flParallelExec=1 ;;
  \?|*) doShowUsage; exit 1      ;;
 esac
done
shift $((OPTIND-1))

[[ $mode ]] && { [[ $mode =~ (standart|extended) ]] || { 
 echo 'Mode must be "standart" or "extended"!'; doShowUsage; exit 1
                                                       }
               }

[[ $flTestOutCmds && $flParallelExec ]] && {
 echo 'You cant specify both -y and -T!'
 doShowUsage
 exit 1
}


declare -A dblocks ul_point

 dblocks[default]='1-29.02.2012'
 
# dblocks[RostovOnDon]='11-17.05.2012 1-7.07.2012'
#ul_point[RostovOnDon]='47.5 39.5'

# dblocks[Remontnoe]='05.2012 06.2012 07.2012 08.2012'
#ul_point[Remontnoe]='47.0 43.5'

# dblocks[Kazanskaya]='5-11.08.2012'
#ul_point[Kazanskaya]='50.0 41.0'

# dblocks[Millerovo]='18-21.08.2012'
#ul_point[Millerovo]='49.0 40.0'

# dblocks[Taganrog]='05.2012 06.2012 07.2012 08.2012'
#ul_point[Taganrog]='47.5 38.5'

# dblocks[Konstantinovsk]='05.2012 06.2012 07.2012 08.2012'
#ul_point[Konstantinovsk]='48.0 41.0'
 dblocks[Tsimlyansk]='03.2012'
ul_point[Tsimlyansk]='48.0 42.0'

baseDir="$TEMP_DIR/$DATA_ID"
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
    cat <<EOF
${flTestOutCmds+$HOME/bin/point_forecast}${flResetSourcePath+ -s /store/GRIB/cooked/GFS4/${DATA_ID}}${mode+ -m $mode} -n -d $baseDir/$meteoStationID/$dblock -H $nPredictHours '$(sqr_points ${ul_point[$meteoStationID]})' $day 0
EOF
   done   
  done
 done
} | $cmd

if [[ $emailTO && -d $DATA_ID ]]; then
 cd $TEMP_DIR
 zip -r $DATA_ID{.zip,/}
 mailfile.pl -f ${DATA_ID}.zip -d $emailTO -T "Meteoreport inside (ID=${DATA_ID})"
fi
