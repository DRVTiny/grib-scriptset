#!/bin/bash
shopt -s extglob
slf=${0##*/}

eval_dinv () { 
 local d fd ld days month year
 IFS='.' read days month year <<<"$1"
 if [[ ! $year ]]; then
  year=$month
  month=$days
  days='1-'$(date -d "${year}${month}01+1 month-1 day" +%d)
 fi
 if [[ $days =~ - ]]; then
  fD=${days%-*}; fD=${fD##*(0)}
  lD=${days##*-*(0)}
  ((fD>lD)) && { d=$fD; fD=$lD; lD=$d; }
  for ((d=$fD; d<=$lD; d++)); do
   echo ${year}${month}$(printf '%02g' $d)
  done
 else
  echo ${year}${month}$(printf '%02g' ${days##*(0)})
 fi 
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

source /opt/scripts/functions/config.func

unset flTestOutCmds flResetSourcePath flParallelExec

TEMP_DIR='/tmp'
DATA_ID='Rostov-On-Don'
nPredictHours=120
pthStationsINI="$HOME/conf/areas.ini"

while getopts 'yshxCTi: P: m: e: d: f: b:' k; do
 case $k in
  h) doShowUsage; exit 0      ;;
  x) set -x                   ;;
  T) flTestOutCmds=1          ;;
  s) flResetSourcePath=1      ;;
  d) TEMP_DIR="${OPTARG%/}"   ;;
  b) dblocks0="$OPTARG"	      ;;
  i) DATA_ID="${OPTARG// /_}"
     DATA_ID="${DATA_ID//\//:}"
                              ;;
  m) mode="${OPTARG,,}"       ;;
  e) emailTO="$OPTARG"	      ;;
  P) nPredictHours="$OPTARG"  ;;
  f) pthStationsINI="$OPTARG" ;;
  C) flRemoveCSV=1	      ;;
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

if [[ -f $pthStationsINI && -r $pthStationsINI ]]; then
 eval "$(read_ini $pthStationsINI)"
else
 echo "INI file $pthStationsINI is not accessible by me" >&2
 exit 1
fi

baseDir="$TEMP_DIR/$DATA_ID"
if [[ -d $baseDir ]]; then
 rm -rf $baseDir/*
else
 mkdir $baseDir
fi

if [[ $flTestOutCmds ]]; then
 cmd='cat -'
else
 cmd="parallel eval '${HOME}/bin/point_forecast'"
fi


{
 for meteoStationID in ${!INIdimensions[@]}; do
  mkdir -p $baseDir/$meteoStationID
  POINT_FORECAST="${flTestOutCmds+$HOME/bin/point_forecast}${flResetSourcePath+ -s /store/GRIB/cooked/GFS4/${DATA_ID}}${mode+ -m $mode} %DEST% -n -H ${nPredictHours} '$(sqr_points ${INIdimensions[$meteoStationID]})'"
  for dblock in ${INIdblocks[$meteoStationID]-${INIdblocks[default]:-$dblocks0}}; do
   mkdir -p $baseDir/$meteoStationID/$dblock
   POINT_FORECAST="${POINT_FORECAST/\%DEST\%/-d $baseDir/$meteoStationID/$dblock}"
   for day in $(eval_dinv $dblock); do
    echo "${POINT_FORECAST} $day 0"
   done
  done
 done
} | $cmd

(( flTestOutCmds )) && exit 0

[[ $flRemoveCSV ]] && find "${baseDir%/}/" -type f -name '*.csv' -delete

if [[ $emailTO ]]; then
 cd "$TEMP_DIR"
 zip -r $DATA_ID{.zip,/}
 if [[ $emailTO =~ / ]]; then
  subj=$(doMacroSub "${emailTO#*/}")
  emailTO=${emailTO%%/*}
 else
  subj="See meteoreport inside (ID=${DATA_ID})"
 fi
 mailfile.pl -f ${DATA_ID}.zip -d $emailTO -T "$subj"
 rm -f ${DATA_ID}.zip
fi
