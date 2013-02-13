#!/bin/bash -x
declare -A DATE
DATA_ID=ROSTOV_TMP850_01
FF='apcp_tmp850'
DATE[start]='2012-01-01'
DATE[end]='2012-03-30'
#H2PRED=180
#STEP_PRED=3
LOG_FILE="$HOME/logs/get_archive_${DATA_ID}.log"
#GB='37.5:1:0.5 55.5:1:0.5' # ALL RUSSIA
GB='36:28:0.5 40:24:0.5' # ROSTOB OBLAST


cd
>$LOG_FILE
#for ((i=0; i<=$H2PRED; i+=STEP_PRED)); do
#for H in {00,06,12,18}00; do
# zp=''
# if (( i<100 )); then
#  zp='0'
#  (( i<10 )) && zp+='0'
# fi
 $HOME/bin/1.sh \
  -b ${DATE[start]} -e ${DATE[end]} \
  -D "_00[036]\." \
  -T /store/GRIB/raw/GFS4/$DATA_ID \
  -d /store/GRIB/cooked/GFS4/$DATA_ID \
  -f $HOME/bin/filters/$FF.grep \
  -g "$GB" 2>&1 | \
   tee -a $LOG_FILE
#done
