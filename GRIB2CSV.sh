#!/bin/bash
declare -A slf=([NAME]="${0##*/}" [PATH]="${0%/*}")
source /opt/scripts/functions/parex.inc
source ${slf[PATH]}/GRIB2DEF.inc

fnFilter='.*'
while getopts 's: d: g: D: xT' key; do
 case $key in
  x) set -x		  ;;
  s) grb2Path="$OPTARG"   ;;
  d) csvPath="$OPTARG"    ;;
  g) GRID_BOUND="$OPTARG" ;;
  D) fnFilter="$OPTARG"   ;;
  T) flTestOut=1	  ;;
  \?|*) : ;;
 esac
done
shift $((OPTIND-1))

getDateCmdArg $@

csvPath="${csvPath:-$GFS_COOKED_CSV}/$DATE"
grb2Path="${grb2Path:-$GFS_RAW_NAMOS}/$DATE"

if [[ $flTestOut ]]; then
 cmd='cat -'
else
 cmd='parallel'
fi
 
[[ $GRID_BOUND ]]; (( flDontUseGridConv|=$? ))

mkdir -p "$csvPath"
cd       "$grb2Path"


$cmd < <({
    for GRB2_FILE in $( ls -1 *.grb2 2>/dev/null | sed -nr "/${fnFilter}/p" ); do
     while read -r GFS_PAR_AT_LVL; do
      CSV_FILE=gfs_4_$(sed -r 's/^gfs_4_//; s/\.grb2$//' <<<"$GRB2_FILE")_$(echo "$GFS_PAR_AT_LVL" | cut -d: -f4,5 | sed -r 's%\s+%_%g; s%:%-%g').csv
      
      [[ -f $CSV_FILE && $(stat -c %s $CSV_FILE) -gt 0 ]] && continue
      
      if [[ $GRID_BOUND ]]; then
       cat <<EOF
wgrib2 -i '${grb2Path}/${GRB2_FILE}' -lola ${GRID_BOUND} '${csvPath}/${CSV_FILE}' spread &>>'${grb2Path}.log' <<<'$GFS_PAR_AT_LVL'
EOF
      else   
       cat <<EOF
wgrib2 -i '${grb2Path}/${GRB2_FILE}' -spread             '${csvPath}/${CSV_FILE}'        &>>'${grb2Path}.log' <<<'$GFS_PAR_AT_LVL'
EOF
      fi
     done < <(wgrib2 ${grb2Path}/$GRB2_FILE)
    done
})

#wait4_all_gone
