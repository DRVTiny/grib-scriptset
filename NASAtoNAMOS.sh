#!/bin/bash

fNASA="$1"; shift 1
[[ $fNASA ]] || exit 1

source ${0%/*}/GRIB2DEF.inc

YMD=$(awk -F'/' '{a=NF-1; print substr($a,1,4) "-" substr($a,5,2) "-" substr($a,7,2) ; }' <<<"$fNASA")

svIFS="$IFS"; IFS='-'
dparts=($YMD)
IFS="$svIFS"

YEAR=${dparts[0]}
MONTH=${dparts[1]}
DAY=${dparts[2]}

fNAMOS="${fNASA%/NASA/*}/NAMOS/$YMD/${fNASA##*/}"

[[ -f $fNAMOS ]] && exit 0
mkdir -p ${fNAMOS%/*}

echo "Get filtered $fNASA to a local directory"

GFS_URL="${BASEURL}/${YEAR}${MONTH}/${YEAR}${MONTH}${DAY}"
METEOPAR_ID=$(echo "$fNAMOS" | sed -r 's%^.+/([^/]+)\.grb2$%\1%')
echo "Will be using \"inv\" file ${GFS_URL}/${METEOPAR_ID}.inv"
set -x
get_inv.pl ${GFS_URL%/}/${METEOPAR_ID}.inv | \
 fgrep -f $BIN/filters/fire-fcast.grep | \
  get_grib.pl ${GFS_URL%/}/${METEOPAR_ID}.grb2 $fNAMOS &
set +x
sleep 2
