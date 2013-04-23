#!/bin/bash
declare -A slf=([NAME]="${0##*/}" [PATH]="${0%/*}")
source ~/bin/GRIB2DEF.inc

startDate="$(date +%Y)-01-01"
pthFilterFile=~/bin/filters/fire-fcast.grep
fnFilter=''
flSkipIfExists=0
pthRawGrib2='/store/GRIB/raw/GFS4/EXH'
pthCookedCSV='/store/GRIB/cooked/GFS4/EXH/csv'
unset flTestOut
mode='all'
while getopts 's: d: b: e: f: D: i: g: m: ETx' key; do
 case $key in
  b) startDate="$OPTARG"  	;;
  e) endDate="$OPTARG"    	;;
  s) pthRawGrib2="$OPTARG"    	;;
  d) pthCookedCSV="$OPTARG"    	;; 
  i) DATA_ID="$OPTARG"		;;
  f) pthFilterFile="$OPTARG" 	;;
  D) fnFilter="$OPTARG"		;;
  g) gridBounds="$OPTARG" 	;;  
  m) mode="${OPTARG,,}"   	;;
  E) flSkipIfExists=1     	;;
  T) flTestOut=1          	;;
  x) set -x; flDebug=1    	;;
  \?|*) exit 1            	;;
 esac
done
shift $((OPTIND-1))

if [[ $DATA_ID ]]; then
 pthRawGrib2="/store/GRIB/raw/GFS4/${DATA_ID}"
 pthCookedCSV=${pthRawGrib2/\/raw\//\/cooked\/}
fi

[[ ${endDate=$(getLatestDay | sed -r 's%([0-9]{4})([0-9]{2})([0-9]{2})%\1-\2-\3%')} ]] || exit 99

[[ $pthFilterFile =~ /|\. ]] || pthFilterFile="${FILTER_PATH}/${pthFilterFile}.grep" 

[[ -f $pthFilterFile ]] || exit 101

[[ $startDate =~  ^20[0-9]{2}-(0[0-9]|1[0-2])-([0-2][0-9]|3[01])$ && $endDate =~ ^20[0-9]{2}-(0[0-9]|1[0-2])-([0-2][0-9]|3[01])$ ]] || exit 102

nDays=$(( ( $(date -d $endDate +%s) - $(date -d $startDate +%s) )/(24*3600) + 1 ))

if [[ ${gridBounds:0:1} == '@' ]]; then
 flRawGridConv=' '
 gridBounds=${gridBounds:1}
fi

cmd='eval'
[[ $flTestOut ]] && cmd='echo'

GRIB2GET_="GRIB2GET.sh ${flDebug+-x }-d ${pthRawGrib2}${flRawGridConv+ -g \"$gridBounds\"}${fnFilter:+ -D \"$fnFilter\"} -f ${pthFilterFile} -E"
GRIB2CSV_="GRIB2CSV.sh ${flDebug+-x }-s ${pthRawGrib2} -d ${pthCookedCSV} ${fnFilter:+ -D \"$fnFilter\" }${flRawGridConv:- -g \"$gridBounds\"}"

for ((i=0; i<nDays; i++)); do
 curDate=$(date -d "$startDate +${i} day" +%Y-%m-%d)
 { [[ -d $pthCookedCSV/$curDate ]] && (( flSkipIfExists )); } && continue
 [[ $mode == 'all' || $mode == 'grb2' ]] && \
  $cmd "${GRIB2GET_} ${curDate}"
 [[ $mode == 'all' || $mode == 'csv' ]] && \
  $cmd "${GRIB2CSV_} ${curDate}"
done
