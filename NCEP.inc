#!/bin/bash
doMacroSubst () {
 [[ $DEBUG ]] && set +x
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
 [[ $DEBUG ]] && set -x
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
dflt[COOKED_NAME_TEMPL]='<nomacro>gfs_4_{{YMD}}_{{HH}}00_{{si}}_{{METEOPAR}}-{{METEOPAR_COND}}.{{OUT_EXT}}'
dflt[OUT_FORMAT]='CSV'
dflt[FL_ZIP_OUT]=1
dflt[COMPRESS_LEVEL]=8
dflt[COMPRESS_CMD]="gzip -{{COMPRESS_LEVEL}} '%OUT_FILE%'"
dflt[FL_CLEAN_RAW_DIR]=0
dflt[FL_CLEAN_CSV_DIR]=0
dflt[FL_CLEAN_RAW_FILE]=0
dflt[FL_SET_LOCK]=0
# For compatibility only ->
dflt[FL_CLEAN_RAW]=0
dflt[FL_CLEAN_CSV]=0
# <-

declare -A FORMAT_EXT=([CSV]='csv' [NETCDF]='nc' [GRIB2]='grb2')
declare -A ZIP_EXT=([gzip]=gz [bzip2]=bz2 [7za]=7z [compress]=Z [zip]=zip)
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

unset getLatestDataTS doCollectCSV

getLatestDataTS () {
local TS nl=1 Where=${1^^}
 case ${Where:-NCEP} in
 NCEP)
  while :; do
   TS=$(wget -q "$HELPER" -O - 2>/dev/null | \
    sed 's%<a href%\n&%g' | \
     sed -nr 's%^<a href="'"${HELPER//./\\.}"'\?dir=\%2Fgfs\.(20(1[2-9]|[2-9][0-9])[0-9]{6})">gfs\.\1</a>.*$%\1%p' | \
      sort -rn | sed -n "${nl}{ p; q; }")
   [[ ${PIPESTATUS[0]} -eq 0 && $TS ]] || return 1
   wget -q "$HELPER?dir=%2Fgfs.${TS}" -O - 2>/dev/null | fgrep -q '>master</a>' && break
   (( nl++ ))
  done
 ;;
 DCOLL)
  maxDay=$(ls $GFS_CSV_PATH | sed -nr '/^[0-9]{8}$/p' | sort -rn | head -1)
  [[ $maxDay ]] || return 1
  TS=$(ls "$GFS_CSV_PATH/$maxDay" | sed -nr "s%^(.*_)?(${maxDay})_([0-9]{2})00_.*$%\2\3%p" | sort -rn | head -1)
 ;;
 *) return 1 ;; 
 esac
 echo -n "$TS"
 return 0
}

doCollectCSV () {
local keyOpt
local flConvert2NetCDF=0 flDontDeleteRaw=0
local l a=() TS
declare -i la
local grb2File outFile
local YMD i si
local FE tmp_ PID
 (( FL_CLEAN_RAW_DIR || FL_CLEAN_RAW )) && \
  { rm -rf $GFS_RAW_PATH && mkdir -p $GFS_RAW_PATH; }
 (( FL_CLEAN_CSV_DIR || FL_CLEAN_CSV )) && \
  { rm -rf $GFS_CSV_PATH && mkdir -p $GFS_CSV_PATH; }
 [[ $1 =~ ^([0-9]{10})?$ ]] || return 1 
 TS="${1:-$(getLatestDataTS)}" 

 YMD=${TS:0:8}; HH=${TS:8:2}
 mkdir -p {$GFS_RAW_PATH,$GFS_CSV_PATH}/${YMD}
 pthCooked="${GFS_CSV_PATH}/${YMD}"
 pthRaw="${GFS_RAW_PATH}/${YMD}"
 
 if [[ $FL_SET_LOCK -gt 0 ]]; then
  if [[ -f ${pthCooked}.pid ]]; then
   PID=$(<${pthCooked}.pid)  
   if [[ $PID =~ ^[0-9]+$ && -f /proc/$PID/cmdline ]] 2>/dev/null; then
    msg="Directory ${pthCooked} seems to be locked by process [$PID], we have nothing to do here"
    declare -f error_ &>/dev/null && \
     error_ "$msg"  || \
     echo "$msg" >&2
    return 1
   else
    rm -f ${pthCooked}.pid
   fi
  else
   echo "$$" > ${pthCooked}.pid
   trap "rm -f ${pthCooked}.pid" SIGINT SIGTERM SIGHUP SIGQUIT EXIT
  fi
 fi
 
 OUT_FORMAT=${OUT_FORMAT^^}
 OUT_EXT=${FORMAT_EXT[${OUT_FORMAT}]}
 [[ $OUT_EXT ]] || { 
  echo "Sorry, we dont know, how to work with output format \"$OUT_FORMAT\" yet" >&2
  return 1
 }
 
 [[ $FL_ZIP_OUT == 1 && ! $COMPRESS_EXT ]] && COMPRESS_EXT=${ZIP_EXT["${COMPRESS_CMD%%[[:space:]]*}"]:-zip}
 
 while read l; do
  IFS=':' read -a a <<<"${l// /_}"
  la=${#a[@]}-1
  METEOPAR=${a[la-1]}
  METEOPAR_COND=${a[la]}

  for H_DIA in ${WFC_PREDICT_H_DIA:=000..${WFC_PREDICT_H}..${WFC_STEP_H}}; do
   for si in $(eval "echo {${H_DIA}}"); do
# si = Hours of prediction, format (ex.): 004, 015, 180  
# Remember: Unlike archive GFS downloading, here GRB2 will be individual for each meteoparameter, base timestamp and hour of prediction
#
# GRB2_NAME_TEMPL (see upper): <nomacro>gfs_4_{{YMD}}_{{HH}}00_{{si}}_{{METEOPAR}}-{{METEOPAR_COND}}.grb2
# Note: grb2 is hardcoded, as of now you cant use other extension for raw files
    grb2File="$pthRaw/$(doMacroSubst GRB2_NAME_TEMPL)"

    outFile="$pthCooked/$(doMacroSubst COOKED_NAME_TEMPL)"
    outFileZ="${outFile}.${COMPRESS_EXT}"
# Check whether target CSV file or its compressed representation exists and it is not empty
    [[ ( -f $outFile && $(stat -c %s $outFile) -gt 0 ) || \
       ( $FL_ZIP_OUT == 1 && -f $outFileZ && $(stat -c %s $outFileZ) -gt 0 ) \
    ]] && continue
    
    if ! [[ -f $grb2File ]]; then
     [[ $si =~ ^0?([0-9]{2,3})$ ]]
     wget -q "${HELPER}?file=gfs.t${HH}z.mastergrb2f${BASH_REMATCH[1]}&lev_${METEOPAR_COND}=on&var_${METEOPAR}=on&subregion=&leftlon=${MIN_LON}&rightlon=${MAX_LON}&toplat=${MAX_LAT}&bottomlat=${MIN_LAT}&dir=%2Fgfs.${TS}%2Fmaster" \
         -O "$grb2File"
     if ! [[ $? -eq 0  && -f $grb2File && $(stat -c %s "$grb2File") -gt 0 ]]; then
      rm -f "$grb2File"
      continue
     fi     
    fi
    tmp_=$(mktemp /tmp/XXXXXXXXXXX)
    case $OUT_FORMAT in
     NETCDF)
      wgrib2 $grb2File -netcdf ${tmp_}
     ;;
     CSV)       
      wgrib2 $grb2File | \
       wgrib2 $grb2File -i -lola $MIN_LON:$GRID_COLS:$GRID_STEP $MIN_LAT:$GRID_ROWS:$GRID_STEP ${tmp_} spread
     ;;
     *) echo "Unknown output format: $OUT_FORMAT" >&2 ;;
    esac
    if (( $(stat -c %s $tmp_) )); then
     mv "${tmp_}" "$outFile"
# mktemp always set access mask to 0600
     chmod 644 "$outFile"
    else
     rm -f "${tmp_}"
    fi    
   done
  done 
 done <$MPARS_LIST_PATH
 
 cd "$pthCooked"
 (( FL_ZIP_OUT )) && \
  ls *.${OUT_EXT} | parallel gzip 2>/dev/null
 
 cd "$pthRaw"
 (( FL_CLEAN_RAW_FILE )) && \
  ls *.grb2 | parallel -m rm -f {} 2>/dev/null
 
 return 0
}
