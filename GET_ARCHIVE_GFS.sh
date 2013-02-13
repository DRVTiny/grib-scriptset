#!/bin/bash -x
source ~/bin/GRIB2DEF.inc

startDate="$(date +%Y)-01-01"
pthFilterFile=~/bin/filters/immediately-fcast.grep
fnFilter=''
flSkipIfExists=0
pthTemp='/store/GRIB/raw/GFS4/EXH'
pthDest='/store/GRIB/cooked/GFS4/EXH/csv'
while getopts 'T: d: b: e: f: D: g: s' key; do
 case $key in
 b) startDate="$OPTARG" ;;
 e) endDate="$OPTARG" ;;
 d) pthDest="$OPTARG" ;;
 T) pthTemp="$OPTARG" ;;
 f) pthFilterFile="$OPTARG" ;;
 D) fnFilter="$OPTARG" ;;
 s) flSkipIfExists=1 ;;
 g) gridBounds="$OPTARG" ;;
 \?|*) exit 1 ;;
 esac
done
endDate=${endDate:-$(getLatestDay | sed -r 's%([0-9]{4})([0-9]{2})([0-9]{2})%\1-\2-\3%')}

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
 eval "GRIB2GET.sh -f $pthFilterFile ${fnFilter:+-D \"$fnFilter\"} -d $pthTemp $curDate"
 eval "GRIB2CSV.sh -s $pthTemp -d $pthDest ${gridBounds+-g \"$gridBounds\"} $curDate"
# rm -rf $pthTemp/$curDate
done
