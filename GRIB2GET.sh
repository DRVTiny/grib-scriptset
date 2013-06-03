#!/bin/bash
MAX_TASKS=8

set +H
me=$(readlink -e "$0")
declare -A slf=([NAME]=${me##*/} [PATH]=${me%/*})
source /opt/scripts/functions/parex.inc
source ${slf[PATH]}/GRIB2DEF.inc

chkUnresDeps || {
 echo "Unresolved dependencies: $DEPS" >&2
 exit 1
}

pthFilterFile="$BIN/filters/default.grep"
fnFilter='.'
while getopts 'f: D: d: g: xE' key; do
 case $key in
  x)    set -x				;;
  d)    grb2Path="$OPTARG"		;;
  f)    pthFilterFile="$OPTARG"		;;
  D)    fnFilter="$OPTARG"		;;
  g)    GRID_BOUND="$OPTARG"		;;
  E)    flSkipIfExists=1		;;
 \?|*)  echo "Wrong key: -${key}"
        exit 1	                        ;;
 esac
done
shift $((OPTIND-1))

export PATH="${BIN}:${PATH}"

getDateCmdArg $@

baseDir="${grb2Path:-$GFS_RAW_NAMOS}/$DATE"

mkdir -p "$baseDir"

#declare -A FILEs

while read -r FILE; do
   grb2File="${baseDir}/${FILE}.grb2"
   [[ $flSkipIfExists && -f $grb2File && $(stat -c %s $grb2File) -gt 0 && $(wgrib2 "$grb2File" 2>/dev/null | wc -l) ]] && continue
   push_task <<EOF
if get_inv.pl $BASEURL/$YM/$YMD/${FILE}.inv | \
    fgrep -f '$pthFilterFile' | \
     get_grib.pl $BASEURL/$YM/$YMD/${FILE}.grb2 ${baseDir}/${FILE}.grb2 && \
      [[ -n '${GRID_BOUND}' ]]
then
 wgrib2 ${baseDir}/${FILE}.grb2 -lola ${GRID_BOUND} ${baseDir}/${FILE}.tmp grib && \
  mv ${baseDir}/${FILE}.{tmp,grb2}
fi
EOF
#   FILEs["$!"]="${baseDir}/${FILE}.grb2"
   sleep 3
done < <(
  curl -s $BASEURL/$YM/$YMD/ | \
   sed -nr "/gfs_4_/{ /$fnFilter/s%^.*>(gfs_4_[0-9]{8}_(0[06]|1[28])00_[0-9]{3})\.inv<.*$%\1%p; }"
)

wait4_all_gone
#for pid in ${!FILEs[@]}; do
# wait $pid 2>/dev/null
# if [[ $? -ne 0 ]]; then
#  :
##  rm -f "${FILEs[$pid]}"
# elif [[ $GRID_BOUND ]]; then
#  wgrib2 ${FILEs[$pid]} -lola ${GRID_BOUND} ${FILEs[$pid]}.tmp grib && \
#   mv ${FILEs[$pid]}.tmp ${FILEs[$pid]}
# fi
#done
