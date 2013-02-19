#!/bin/bash
doMacroSubst () {
 local v="$1" m
 local ev="${!v}"
 if [[ $ev =~ ^\<nomacro\> ]]; then
  echo "${ev:9}"
 else
  for m in \
   $(sed -r -e 's/\}\}[^{]+\{\{/}}{{/g; s/^[^{]+\{/{/; s/}[^}{]+$/}/; s%\}\}$%%; s%\}\}%\n%g; s%\{\{%%g' -e '/^$/d' <<<"$ev")
  do
   ev=${ev//\{\{$m\}\}/${!m}}
  done
  echo "$ev"
 fi
 return 0
}

unset dflt
declare -A dflt
dflt[DATA_ID]='<nodefault>'
dflt[MPARS_LIST_FILE]='<nodefault>'
dflt[MIN_LON]='<nodefault>'
dflt[MAX_LON]='<nodefault>'
dflt[MIN_LAT]='<nodefault>'
dflt[MAX_LAT]='<nodefault>'
dflt[BASEURL]='http://nomads.ncep.noaa.gov'
dflt[HELPER]='{{BASEURL}}/cgi-bin/filter_gfs_hd.pl'
dflt[USER_HOME]="$(getent passwd $(whoami) | cut -d: -f6)"
dflt[GFS_RAW_PATH]='/store/GRIB/raw/GFS4/{{DATA_ID}}'
dflt[GFS_CSV_PATH]=${dflt[GFS_RAW_PATH]//\/raw\//\/cooked\/}
dflt[MPARS_BASE_PATH]='{{USER_HOME}}/bin/filters'
dflt[MPARS_LIST_PATH]='{{MPARS_BASE_PATH}}/{{MPARS_LIST_FILE}}'
dflt[GRID_STEP]=0.5
dflt[WFC_PREDICT_H]=180
dflt[WFC_STEP_H]=3
dflt[GRB2_NAME_TEMPL]='<nomacro>gfs_4_{{YMD}}_{{HH}}00_{{si}}_{{METEOPAR}}-{{METEOPAR_COND}}.grb2'
dflt[OUT_FORMAT]='CSV'
dflt[FL_ZIP_OUT]=1
dflt[COMPRESS_CMD]='gzip -8 %OUT_FILE%'
dflt[FL_CLEAN_RAW_DIR]=0
dflt[FL_CLEAN_CSV_DIR]=0
dflt[FL_CLEAN_RAW_FILE]=0
# For compatibility only ->
dflt[FL_CLEAN_RAW]=0
dflt[FL_CLEAN_CSV]=0
# <-

declare -A FORMAT_EXT=([CSV]='csv' [NETCDF]='nc' [GRIB2]='grb2')

CONF_KEYS="${!dflt[@]}"

for v in $CONF_KEYS; do
 unset $v
done

[[ $GFS_CUSTOM_PARS && -f $GFS_CUSTOM_PARS && -r $GFS_CUSTOM_PARS ]] && \
 source $GFS_CUSTOM_PARS

for v in $CONF_KEYS; do
 if ! [[ ${!v} || ${dflt[$v]} == '<nodefault>' ]]; then  
  eval "$v=\"${dflt[$v]}\""
 fi
done

for v in $CONF_KEYS; do
 eval "$v=\"$(doMacroSubst $v)\""
done

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
local keyOpt
local flConvert2NetCDF=0 flDontDeleteRaw=0
local l a=() TS
declare -i la
local grb2File outFile tgtPath
local YMD i si
local FE
 (( FL_CLEAN_RAW_DIR || FL_CLEAN_RAW )) && \
  { rm -rf $GFS_RAW_PATH && mkdir -p $GFS_RAW_PATH; }
 (( FL_CLEAN_CSV_DIR || FL_CLEAN_CSV )) && \
  { rm -rf $GFS_CSV_PATH && mkdir -p $GFS_CSV_PATH; }
  
 TS="${1:-$(getLatestDataTS)}" 
 
 while read l; do
  IFS=':' read -a a <<<"${l// /_}"  
  YMD=${TS:0:8}; HH=${TS:8:2}
  la=${#a[@]}-1
  METEOPAR=${a[la-1]}
  METEOPAR_COND=${a[la]}
  tgtPath="$GFS_RAW_PATH/${YMD}"
  mkdir -p "${tgtPath}"
  for H_DIA in ${WFC_PREDICT_H_DIA:=000..${WFC_PREDICT_H}..${WFC_STEP_H}}; do
   for si in $(eval "echo {${H_DIA}}"); do
# si = Hours of prediction, format (ex.): 004, 015, 180  
    grb2File="${tgtPath}/$(doMacroSubst GRB2_NAME_TEMPL)"
    if ! [[ -f $grb2File ]]; then
     [[ ${si:0:1} == '0' ]] && si=${si:1:2}
     wget "${HELPER}?file=gfs.t${HH}z.mastergrb2f${si}&lev_${METEOPAR_COND}=on&var_${METEOPAR}=on&leftlon=${MIN_LON}&rightlon=${MAX_LON}&toplat=${MAX_LAT}&bottomlat=${MIN_LAT}&dir=%2Fgfs.${TS}%2Fmaster" \
         -O "$grb2File"
     if (( $? || ( $(stat -c %s "$grb2File") == 0 ) )); then
      rm -f "$grb2File"
      continue
     fi     
    fi
    FE=${FORMAT_EXT[${OUT_FORMAT^^}]}
    if [[ $FE ]]; then
     outFile=$(sed -r "s%^gfs_4_%%; s%/raw/%/cooked/%; s%\.grb2$%.${FE}%" <<<"$grb2File")
     mkdir -p ${outFile%/*}
     case ${OUT_FORMAT^^} in
     NETCDF)
      wgrib2 $grb2File -netcdf $outFile
     ;;
     CSV)
      if ! [[ -f $outFile || -f $outFile.gz ]]; then
       wgrib2 $grb2File | \
        wgrib2 $grb2File -i -lola $MIN_LON:$GRID_COLS:$GRID_STEP $MIN_LAT:$GRID_ROWS:$GRID_STEP $outFile spread
      fi
     ;;
     *) echo "Unknown output format: $OUT_FORMAT" >&2 ;;
     esac
     if [[ -f $outFile ]] && (( FL_ZIP_OUT )); then
      eval "${COMPRESS_CMD//%OUT_FILE%/$outFile}"
     fi
    else
     echo "Sorry, we dont know, how to work with output format \"$OUT_FORMAT\" yet" >&2
    fi
    (( FL_CLEAN_RAW_FILE )) && rm -f "$grb2File"
   done
  done 
 done <$MPARS_LIST_PATH
 return 0
}
