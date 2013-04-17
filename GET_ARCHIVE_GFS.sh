#!/bin/bash
source ~/bin/GRIB2DEF.inc

startDate="$(date +%Y)-01-01"
pthFilterFile=~/bin/filters/fire-fcast.grep
fnFilter=''
flSkipIfExists=0
pthTemp='/store/GRIB/raw/GFS4/EXH'
pthDest='/store/GRIB/cooked/GFS4/EXH/csv'
unset flTestOut
mode='all'
while getopts 'T: d: b: e: f: D: g: sx m:' key; do
 case $key in
 b) startDate="$OPTARG" ;;
 e) endDate="$OPTARG" ;;
 d) pthDest="$OPTARG" ;;
 T) pthTemp="$OPTARG" ;;
 f) pthFilterFile="$OPTARG" ;;
 D) fnFilter="$OPTARG" ;;
 s) flSkipIfExists=1 ;;
 g) gridBounds="$OPTARG" ;;
 t) flTestOut=1 ;;
 m) mode="${OPTARG,,}" ;;
 x) set -x; flDebug=1 ;;
 \?|*) exit 1 ;;
 esac
done
shift $((OPTIND-1))

[[ ${endDate=$(getLatestDay | sed -r 's%([0-9]{4})([0-9]{2})([0-9]{2})%\1-\2-\3%')} ]] || exit 99

[[ $pthFilterFile =~ /|\. ]] || pthFilterFile="${FILTER_PATH}/${pthFilterFile}.grep" 

[[ -f $pthFilterFile ]] || exit 101

[[ $startDate =~  ^20[0-9]{2}-(0[0-9]|1[0-2])-([0-2][0-9]|3[01])$ ]] || exit 102
[[ $endDate =~  ^20[0-9]{2}-(0[0-9]|1[0-2])-([0-2][0-9]|3[01])$ ]] || exit 103


nDays=$(( ( $(date -d $endDate +%s) - $(date -d $startDate +%s) )/(24*3600) + 1 ))

#echo "GRIB2GET.sh -f $pthFilterFile -D \"$fnFilter\" -d $pthTemp $curDate
#GRIB2CSV.sh -s $pthTemp -d $pthDest $curDate"
#exit 0
for ((i=0; i<nDays; i++)); do
 curDate=$(date -d "$startDate +${i} day" +%Y-%m-%d)
 { [[ -d $pthDest/$curDate ]] && (( flSkipIfExists )); } && continue
 [[ $mode == 'all' || $mode == 'grb2' ]] && \
  eval "${flTestOut+echo }GRIB2GET.sh ${flDebug+-x }-f $pthFilterFile ${fnFilter:+-D \"$fnFilter\"} -d $pthTemp $curDate"
 [[ $mode == 'all' || $mode == 'csv' ]] && \
  eval "${flTestOut+echo }GRIB2CSV.sh ${flDebug+-x }-s $pthTemp -d $pthDest ${gridBounds+-g \"$gridBounds\"} $curDate"
# rm -rf $pthTemp/$curDate
done
