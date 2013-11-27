#!/bin/bash
doShowUsage () {
 cat <<EOF
Usage:
 ${slf[NAME]} [ -i DATA_ID ] [-d DEST_PATH ] [-e EMAIL_REPORT_TO ] [-a PointsFile ][-m MODE=(standart|extended)] [-P PREDICT_HOURS] [ -T ] [-s] [-x]
EOF
 return 0
}

set +H
shopt -s extglob
declare -A slf=([NAME]=${0##*/} [PATH]=${0%/*})

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

source /opt/scripts/functions/config.func || exit 1500
source /opt/scripts/functions/dates.inc || exit 1500

unset flTestOutCmds flResetSourcePath flParallelExec

TEMP_DIR='/tmp'
nPredictHours=120
pthStationsINI="$HOME/conf/areas.ini"

while getopts 'yShxCTi: s: P: m: e: d: f: b: a:' k; do
 case $k in
  h) doShowUsage; exit 0      ;;
  x) set -x                   ;;
  T) flTestOutCmds=1          ;;
  s) pthCookedCSVs="$OPTARG"  ;;
  S) flResetSourcePath=1      ;;
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
  a) pthPointsFile="$OPTARG"  ;;
  y) (( $(fgrep processor /proc/cpuinfo | wc -l) > 1 )) && flParallelExec=1 ;;
  \?|*) doShowUsage; exit 1      ;;
 esac
done
shift $((OPTIND-1))

if [[ -f $pthPointsFile ]]; then
 while read -r l; do
  IFS=';' fld=($l)
  ed=$(date -d "$(date +%Y)${fld[0]##*.}${fld[0]%%.*}" +%Y%m%d)
  sd=$(date -d "$ed -3 days" +%Y%m%d)
  echo ./point_forecast.pl -b $sd -e $ed --view-mode h --view-excl 'WDIR,WIND,dayTmin,dayTmax,APCP12' --maxh 72 ${fld[1]},${fld[2]}
 done <$pthPointsFile
 exit 0
fi

[[ $mode ]] && { [[ $mode =~ (standart|extended) ]] || { 
 echo 'Mode must be "standart" or "extended"!'; doShowUsage; exit 1
                                                       }
               }

[[ $flTestOutCmds && $flParallelExec ]] && {
 echo 'You cant specify both -y and -T!'
 doShowUsage
 exit 1
}

if (( flResetSourcePath )); then
 [[ $pthCookedCSVs ]] && {
  echo 'You cant specify both -s and -S!' >&2
  doShowUsage
  exit 1
 }
 [[ $DATA_ID ]] || {
  echo 'You MUST specify -i when using -S (because source path will be reseted based on the value specified with the "-i" key)' >&2
  exit 1
 }
 pthCookedCSVs="/store/GRIB/cooked/GFS4/${DATA_ID}"
fi

if [[ $pthCookedCSVs && ! -d $pthCookedCSVs ]]; then
 echo "Source path ($pthCookedCSVs) is invalid" >&2
 exit 1
fi

if [[ -f $pthStationsINI && -r $pthStationsINI ]]; then
 eval "$(read_ini $pthStationsINI)"
else
 echo "INI file $pthStationsINI is not accessible by me" >&2
 exit 1
fi

baseDir="$TEMP_DIR/${DATA_ID:=MeteoReport}"
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
  unset src
  src=${pthCookedCSVs:-${INIsource[$meteoStationID]:=${INIsource[default]}}}
  POINT_FORECAST="${flTestOutCmds+$HOME/bin/point_forecast} ${src:+-s $src} ${mode+ -m $mode} %DEST% -n -H ${nPredictHours} '$(sqr_points ${INIdimensions[$meteoStationID]})'"
  dblocks="${INIdblocks[$meteoStationID]:-${INIdblocks[default]:-$dblocks0}}"
  for dblock in ${dblocks//;/ }; do
   mkdir -p $baseDir/$meteoStationID/$dblock
   cmdPOINT_FORECAST="${POINT_FORECAST//%DEST%/-d $baseDir/$meteoStationID/$dblock}"
   for day in $(dinv $dblock); do
    echo "${cmdPOINT_FORECAST} $day 0"
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
