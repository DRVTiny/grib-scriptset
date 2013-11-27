#!/bin/bash
shopt -s extglob; set +H
doShowUsage () {
 cat <<EOF
Usage: ${slf[NAME]} 
  [-b START_DATE] where START_DATE=YYYY-MM-DD
  [-e FIN_DATE]   where FIN_DATE=YYYY-MM-DD
  [-s PATH_TO_RAW_GRB2] note: GRB2 files must be in PATH_TO_RAW_GRB2/YYYY-?MM-?DD subdirs!
  [-d PATH_WHERE_COOKED_CSV] note: CSV files goes to PATH_WHERE_COOKED_CSV/YYYYMMDD
  [-i DATA_ID]          Example: ROSTOV_ON_DON
  [-f FILTER_FILE]      Example: /usr/local/warehouse/bin/filters/extended.grep
  [-D FILE_NAME_FILTER] Example: _0000_003
  [-g GRID_BOUND]       Example: 36:28:0.5 39:26:0.5
  [-m MODE] Specify what 2 do: 
             - only download grb2 files (MODE=grb2),
             - generate csv's from previously downloaded grb2 files (MODE=csv) or
             - (default) download grb2 and generate appropriate csv's for each of them (MODE=all)
  [-E] Skip csv creation if it is already exists and file length is not null
  [-T] Dont touch anything, output low-level commands instead
  [-x] Standart BASH debug mode (see  man bash, -x key)
  [-h] Show this message
See http://wiki.namos.ru/Main/GetArchiveGFS for more info
EOF
 return 0
}

declare -A slf=([NAME]="${0##*/}" [PATH]="${0%/*}")
source ~/bin/GRIB2DEF.inc
declare -A DATAID2CONF=(['NCEP']='rostov-on-don'
                        ['MOSCOW']='mos-oblast'
                        ['SPB']='spb'
                        )
startDate="$(date +%Y)-01-01"
fnFilter=''
flSkipIfExists=0
pthRawGrib2='/store/GRIB/raw/GFS4/EXH'
pthCookedCSV='/store/GRIB/cooked/GFS4/EXH/csv'
unset flTestOut CONFIG pthFilterFile
mode='all'
while getopts 'c: s: d: b: e: f: D: i: g: m: ETxh' key; do
 case $key in
  b) startDate="$OPTARG"  	;;
  e) endDate="$OPTARG"    	;;
  s) pthRawGrib2="$OPTARG"    	;;
  d) pthCookedCSV="$OPTARG"    	;; 
  i) DATA_ID="$OPTARG"		;;  
  c) [[ $OPTARG =~ / ]] && CONFIG=$OPTARG || CONFIG="/etc/grib/${OPTARG}.inc"
     [[ -f $CONFIG && -r $CONFIG ]] || \
      { echo "Config file '$CONFIG' not exist or not readable" >&2; exit 1; }
  ;;
  f) pthFilterFile="$OPTARG" 	;;
  D) fnFilter="$OPTARG"		;;
  g) gridBounds="$OPTARG" 	;;
  m) mode="${OPTARG,,}"   	;;
  E) flSkipIfExists=1     	;;
  T) flTestOut=1          	;;
  x) set -x; flDebug=1    	;;
  h) doShowUsage; exit 0        ;;
  \?|*) echo 'ERROR: Wrong parameter passed to me!'
        doShowUsage; exit 1   	;;
 esac
done
shift $((OPTIND-1))

[[ $DATA_ID && ! $gridBounds ]] && CONFIG=$(fgrep -rH "DATA_ID='${DATA_ID}'" /etc/grib/ | sed -nr 's%^([^:]+\.inc):.*$%\1%p' | head -1)

if [[ $CONFIG ]]; then
 source "$CONFIG"
 [[ $gridBounds ]] || gridBounds="${MIN_LON}:$(((MAX_LON-MIN_LON)<<1)):0.5 ${MIN_LAT}:$(((MAX_LAT-MIN_LAT)<<1)):0.5"
 [[ $pthFilterFile ]] || pthFilterFile="$HOME/bin/filters/$MPARS_LIST_FILE"
fi

if [[ $DATA_ID ]]; then
 pthRawGrib2="/store/GRIB/raw/GFS4/${DATA_ID}"
 pthCookedCSV=${pthRawGrib2/\/raw\//\/cooked\/}
fi

[[ ${endDate=$(getLatestDay | sed -r 's%([0-9]{4})([0-9]{2})([0-9]{2})%\1-\2-\3%')} ]] || exit 99

[[ $pthFilterFile =~ /|\. ]] || pthFilterFile="${FILTER_PATH}/${pthFilterFile}.grep" 

[[ -f $pthFilterFile ]] || exit 101

[[ $startDate =~  ^20[0-9]{2}-?(0[0-9]|1[0-2])-?([0-2][0-9]|3[01])$ && $endDate =~ ^20[0-9]{2}-?(0[0-9]|1[0-2])-?([0-2][0-9]|3[01])$ ]] || exit 102
DAY_TEMPLATE='%Y-%m-%d'
[[ $startDate =~ \- ]] || DAY_TEMPLATE='%Y%m%d'

nDays=$(( ( $(date -d $endDate +%s) - $(date -d $startDate +%s) )/(24*3600) + 1 ))

if [[ ${gridBounds:0:1} == '@' ]]; then
 flRawGridConv=' '
 gridBounds=${gridBounds:1}
fi

cmd='eval'
[[ $flTestOut ]] && cmd='echo'

GRIB2GET_="GRIB2GET.sh ${flDebug+-x }-d ${pthRawGrib2}${flRawGridConv:+ -g \"$gridBounds\"}${fnFilter:+ -D \"$fnFilter\"} -f ${pthFilterFile} -E"
GRIB2CSV_="GRIB2CSV.sh ${flDebug+-x }-s ${pthRawGrib2} -d ${pthCookedCSV} ${fnFilter:+ -D \"$fnFilter\" }${flRawGridConv:- -g \"$gridBounds\"}"

for ((i=0; i<nDays; i++)); do
 curDate=$(date -d "$startDate +${i} day" +${DAY_TEMPLATE})
 { [[ -d $pthCookedCSV/$curDate ]] && (( flSkipIfExists )); } && continue
 [[ $mode == 'all' || $mode == 'grb2' ]] && \
  $cmd "${GRIB2GET_} ${curDate}"
 [[ $mode == 'all' || $mode == 'csv' ]] && \
  $cmd "${GRIB2CSV_} ${curDate}"
done
