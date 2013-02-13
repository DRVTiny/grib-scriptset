
#!/bin/bash
unset dflt
declare -A dflt
dflt[BASEURL]='http://nomads.ncep.noaa.gov'
dflt[HELPER]='{{BASEURL}}/cgi-bin/filter_gfs_hd.pl'
dflt[USER_HOME]="$(getent passwd $(whoami) | cut -d: -f6)"
dflt[DATA_ID]='NCEP'
dflt[GFS_RAW_PATH]='/store/GRIB/raw/GFS4/{{DATA_ID}}'
dflt[GFS_CSV_PATH]=${dflt[GFS_RAW_PATH]//\/raw\//\/cooked\/}
dflt[FL_CLEAN_RAW]=0
dflt[FL_CLEAN_CSV]=0
dflt[MPARS_BASE_PATH]='{{USER_HOME}}/bin/filters'
dflt[MPARS_LIST_FILE]='fire-fcast.grep'
dflt[MPARS_LIST_PATH]='{{MPARS_BASE_PATH}}/{{MPARS_LIST_FILE}}'
dflt+=([MIN_LON]=36 [MAX_LON]=50)
dflt+=([MIN_LAT]=39 [MAX_LAT]=52)
dflt[GRID_STEP]=0.5
dflt[WFC_PREDICT_H]=180
dflt[WFC_STEP_H]=3

CONF_KEYS="${!dflt[@]}"

for v in $CONF_KEYS; do
 unset $v
done

[[ $GFS_CUSTOM_PARS && -f $GFS_CUSTOM_PARS && -r $GFS_CUSTOM_PARS ]] && \
 source $GFS_CUSTOM_PARS

for v in $CONF_KEYS; do
 [[ ${!v} ]] || eval "$v=\"${dflt[$v]}\""
done

for v in $CONF_KEYS; do
 ev=${!v}
 for m in \
  $(sed -r -e 's/\}\}[^{]+\{\{/}}{{/g; s/^[^{]+\{/{/; s/}[^}{]+$/}/; s%\}\}$%%; s%\}\}%\n%g; s%\{\{%%g' -e '/^$/d' <<<"$ev")
 do
  ev=${ev//\{\{$m\}\}/${!m}}
 done
 [[ $ev == ${!v} ]] || eval "$v=\"$ev\""
 
# echo "$v = ${!v}"
done


#echo "$MPARS_LIST_PATH"

GRID_COLS=$( bc <<<"($MAX_LON-$MIN_LON)/$GRID_STEP+1" )
GRID_ROWS=$( bc <<<"($MAX_LAT-$MIN_LAT)/$GRID_STEP+1" )

getLatestDataTS () {
local TS
  TS=$(wget "$HELPER" -O - 2>/dev/null | \
   sed 's%<a href%\n&%g' | \
    sed -nr 's%^<a href="'"${HELPER//./\\.}"'\?dir=\%2Fgfs\.(20(1[2-9]|[2-9][0-9])[0-9]{6})">gfs\.\1</a>.*$%\1%p' | \
     sort -rn | head -1)
  if ! wget "$HELPER?dir=%2Fgfs.${TS}" -O - 2>/dev/null | fgrep -q '>master</a>'; then
   TS=$(wget "$HELPER" -O - 2>/dev/null | \
    sed 's%<a href%\n&%g' | \
     sed -nr 's%^<a href="'"${HELPER//./\\.}"'\?dir=\%2Fgfs\.(20(1[2-9]|[2-9][0-9])[0-9]{6})">gfs\.\1</a>.*$%\1%p' | \
      sort -rn | head -2 | sed '1d')
  fi
  echo "$TS"    
 return 0
}

doCollectCSV () {
local l a=() TS
local grb2File csvFile tgtPath
local sIFS YMD i si
 (( FL_CLEAN_RAW )) && \
  { rm -rf $GFS_RAW_PATH && mkdir -p $GFS_RAW_PATH; }
 (( FL_CLEAN_CSV )) && \
  { rm -rf $GFS_CSV_PATH && mkdir -p $GFS_CSV_PATH; }
  
 TS="${1:-$(getLatestDataTS)}"
 
 while read l; do
  sIFS=$IFS; IFS=':'
  a=(${l// /_})
  IFS="$sIFS"
  
  YMD=${TS:0:8}
  HH=${TS:8:2}
  METEOPAR=${a[1]}
  METEOPAR_COND=${a[2]}
  tgtPath="$GFS_RAW_PATH/${YMD}"
  mkdir -p "${tgtPath}"
  for si in $(seq -f '%03g' 0 $WFC_STEP_H $WFC_PREDICT_H); do
# si = Hours of prediction, format (ex.): 004, 015, 180  
   grb2File="${tgtPath}/gfs_4_${YMD}_${HH}00_${si}_${METEOPAR}-${METEOPAR_COND}.grb2"
   if ! [[ -f $grb2File ]]; then
    [[ ${si:0:1} == '0' ]] && si=${si:1:2}
    wget "${HELPER}?file=gfs.t${HH}z.mastergrb2f${si}&lev_${METEOPAR_COND}=on&var_${METEOPAR}=on&leftlon=${MIN_LON}&rightlon=${MAX_LON}&toplat=${MAX_LAT}&bottomlat=${MIN_LAT}&dir=%2Fgfs.${TS}%2Fmaster" \
        -O "$grb2File"
    if (( $? || ( $(stat -c %s "$grb2File") == 0 ) )); then
     rm -f "$grb2File"
     continue
    fi     
   fi
   csvFile=$(sed -r 's%^gfs_4_%%; s%/raw/%/cooked/%; s%\.grb2$%.csv%' <<<"$grb2File")
   mkdir -p ${csvFile%/*}
   if ! [[ -f $csvFile || -f ${csvFile}.gz ]]; then
    wgrib2 $grb2File | \
     wgrib2 $grb2File -i -lola $MIN_LON:$GRID_COLS:$GRID_STEP $MIN_LAT:$GRID_ROWS:$GRID_STEP $csvFile spread && \
      gzip $csvFile
   fi
   rm -f "$grb2File"
  done 
 done <$MPARS_LIST_PATH
 return 0
}
