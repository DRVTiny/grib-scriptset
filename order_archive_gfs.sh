#!/bin/bash -x
DATA_ID='ROSTOV2012_Thunder'
declare -A GB=(
                [ROSTOV2012_Thunder]='36:28:0.5 39:26:0.5'
)
FF='fire-fcast'

declare -A DATE=(
		[start]='2012-05-01'
		[end]='2012-08-31'
)

BASE_TIME='00'
H2PRED=120; STEP_PRED=3

LOG_FILE="$HOME/logs/get_archive_${DATA_ID}.log"

cd

>$LOG_FILE

for baseH in $(eval "echo $BASE_TIME"); do
 for predH in  $(eval "echo {000..$H2PRED..$STEP_PRED}"); do
  $HOME/bin/grib-scriptset/GET_ARCHIVE_GFS.sh \
   -b ${DATE[start]} -e ${DATE[end]} \
   -D "${baseH}00_${predH}\." \
   -T /store/GRIB/raw/GFS4/$DATA_ID \
   -d /store/GRIB/cooked/GFS4/$DATA_ID \
   -f $HOME/bin/filters/$FF.grep \
   -g "${GB[$DATA_ID]}" 2>&1 | \
    tee -a $LOG_FILE
 done
done
