#!/bin/bash -x
#
#Execution time for 1 day: 4m 30s
#
slf=${0##*/}
source ${0%/*}/GRIB2DEF.inc
pthFilterFile="$BIN/filters/fire-fcast.grep"
fnFilter='.'
while getopts 'f: D: d:' key; do
 case $key in
 f)    pthFilterFile="$OPTARG"		;;
 D)    fnFilter="$OPTARG"		;;
 d)    RAW_DIR="$OPTARG"		;;
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

{
 while read -r FILE; do
    echo "$FILE" >> "$rxAlreadySeen"
    get_inv.pl $BASEURL/$YM/$YMD/${FILE}.inv | \
     fgrep -f "$pthFilterFile" | \
      get_grib.pl $BASEURL/$YM/$YMD/$FILE.grb2 ${baseDir}/${FILE}.grb2 &
    sleep 3
 done < <(
  curl -s $BASEURL/$YM/$YMD/ | \
   sed -nr "/$fnFilter/p" | \
    sed -nr '/gfs_4_/s%^.*>(gfs_4_[0-9]{8}_[0-9]{4}_[0-9]{3})\.inv<.*$%\1%p' | \
     fgrep -v -f "$rxAlreadySeen"
         )
}
exit $?
