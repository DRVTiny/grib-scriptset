#!/bin/bash
set +H

slf=${0##*/}

source ${0%/*}/GRIB2DEF.inc

#if ! s=$(chkUnresDeps); then
# { [[ $s ]] && echo "Unresolved dependencies found: \"$s\"" >&2; } || echo 'Problem while checking dependencies'
# exit 1
#fi

pthFilterFile="$BIN/filters/default.grep"
fnFilter='.'
while getopts 'f: D: d: g: x' key; do
 case $key in
 x)    set -x				;;
 f)    pthFilterFile="$OPTARG"		;;
 D)    fnFilter="$OPTARG"		;;
 d)    RAW_DIR="$OPTARG"		;;
 g)    GRID_BOUND="$OPTARG"		;;
 \?|*) echo "Wrong key: -${key}"	;;
 esac
done
shift $((OPTIND-1))

export PATH="${BIN}:${PATH}"

getDateCmdArg $@

baseDir="${RAW_DIR:-$GFS_RAW_NAMOS}/$DATE"
rxAlreadySeen="$baseDir/daily.grib2.grep"

mkdir -p "$baseDir"
touch    "$rxAlreadySeen"

declare -A FILEs

while read -r FILE; do
   echo "$FILE" >> "$rxAlreadySeen"   
   ( get_inv.pl $BASEURL/$YM/$YMD/${FILE}.inv | fgrep -f "$pthFilterFile" | get_grib.pl $BASEURL/$YM/$YMD/$FILE.grb2 ${baseDir}/${FILE}.grb2 ) &
   FILEs["$!"]="${baseDir}/${FILE}.grb2"
   sleep 3
done < <(
  curl -s $BASEURL/$YM/$YMD/ | \
   sed -nr "/gfs_4_/{ /$fnFilter/s%^.*>(gfs_4_[0-9]{8}_(0[06]|1[28])00_[0-9]{3})\.inv<.*$%\1%p; }" | \
    fgrep -v -f "$rxAlreadySeen"
)

for pid in ${!FILEs[@]}; do
 wait $pid 2>/dev/null
 if [[ $? -ne 0 ]]; then
  rm -f "${FILEs[$pid]}"
 elif [[ $GRID_BOUND ]]; then
  wgrib2 ${FILEs[$pid]} -lola ${GRID_BOUND} ${FILEs[$pid]}.tmp grib && \
   mv ${FILEs[$pid]}.tmp ${FILEs[$pid]}
 fi
done
