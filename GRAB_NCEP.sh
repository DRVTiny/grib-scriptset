#!/bin/bash
source /opt/scripts/functions/prologue.inc
source /opt/scripts/functions/debug.func
source /opt/scripts/functions/parex.inc
LOG_PATH='/var/log/grib/grab_ncep'

ID='rostov-on-don'
unset SfxNCEP
while getopts 'xpTA:l:' key; do
 case $key in
  A) ID="$OPTARG" ;;
  x) 
     export DEBUG=1 PS4='+[$BASHPID] '
     set -x
  ;;
  l) LOG_FILE="$OPTARG" ;;
  T) flTestOut=1 ;;
  p) SfxNCEP='Par' 
     info_ 'We will use';;
  
  \?|*) fatal_ "Unknown key passed to me: $key"; exit 1 ;;
 esac
done
shift $((OPTIND-1))

LOG_FILE="${LOG_FILE:-$LOG_PATH/$ID/common.log}"
mkdir -p "${LOG_FILE%/*}"

log_open $LOG_FILE

GFS_CUSTOM_PARS="/etc/grib/$ID.inc"
[[ -f $GFS_CUSTOM_PARS && -r $GFS_CUSTOM_PARS ]] || {
 error_ "Cant read GFS_CUSTOM_PARS=$GFS_CUSTOM_PARS"
 exit 1
}

# ParNCEP.inc is a copy of NCEP.inc with paralellized code of internal loop inside doCollectCSV function

source ${USER_HOME:=$(getent passwd $(whoami) | cut -d: -f6)}/bin/grib-scriptset/${SfxNCEP}NCEP.inc
startDate="$1"; shift
if [[ $startDate ]]; then
 if [[ ${#startDate} -eq 10 ]]; then
  if [[ $SfxNCEP ]]; then
   for curTS in $startDate $@; do
    if [[ $curTS =~ ^20[0-9]{8}$ ]]; then
     doCollectCSV $curTS
    else
     error_ "Wrong timestamp specified: $curTS"
    fi
   done
  else  
   trap rotate_tq SIGUSR1
   for curTS in $startDate $@; do
    if [[ $curTS =~ ^20[0-9]{8}$ ]]; then
     push_task -c <<'EOPROC'
      doCollectCSV $curTS
      kill -USR1 $$
EOPROC
    else
     error_ "Wrong timestamp specified: $curTS"
    fi
   done
   trap '' SIGUSR1
   wait4_all_gone
  fi  
 else
  endDate=${1:-$(getLatestDataTS)}; shift
  if [[ $@ ]]; then
   hours="$@"
  else
   hours='{00..18..6}'
  fi
  nDays=$(( ( $(date -d ${endDate:0:8} +%s) - $(date -d $startDate +%s) )/(24*3600) + 1 ))
  trap rotate_tq SIGUSR1
  for ((i=0; i<nDays; i++)); do
   YMD=$(date -d "$startDate +${i} days" +%Y%m%d)
   for hint in $hours; do
    for H in $(eval "echo $hint"); do
     push_task -c <<'EOPROC'
      ${flTestOut:+echo} doCollectCSV ${YMD}${H}
      kill -USR1 $$
EOPROC
    done
   done
  done
  trap '' SIGUSR1
  wait4_all_gone
 fi
else
# (( $(getLatestDataTS ncep) > $(getLatestDataTS dcoll) )) ...
  curTS=$(getLatestDataTS ncep) || exit 134
  if [[ $DEBUG ]]; then
   set -x  
   doCollectCSV $curTS &>"${LOG_FILE%/*}/dbg_${curTS}_$(date +%Y%m%d%H%M%S).log"
   set +x 
  else
   doCollectCSV $curTS
  fi  
fi
