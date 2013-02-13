#!/bin/bash -x
slf=${0##*/}
source ${0%/*}/GRIB2DEF.inc
chkRemoteFTPMounted
getDateCmdArg $@

FF=${slf##*_}

scanDirs="$GFS_RAW_NASA/$YM/$YMD"
if [[ ${FF%.sh} == "DAILY" ]]; then
 YMD1=$(date -d "$YMD-1day" +%Y%m%d) 
 scanDirs+=" $GFS_RAW_NASA/${YMD1:0:6}/$YMD1"
elif [[ ${FF%.sh} == "ALL" ]]; then
 scanDirs="$GFS_RAW_NASA"
fi
find $scanDirs \
     -type f -regex '.*/.*\.grb2$' \
     -exec $BIN/NASAtoNAMOS.sh {} \;
