#!/bin/bash
declare -A slf=([NAME]="${0##*/}" [PATH]="$0" [DIR]="${0%/*}")

doShowUsage () {
 cat <<EOF
${slf[NAME]} -e SEND_EMAIL_TO -a AREA_ID [-d 15.11.2013] [-x] [-E] 
EOF
 return 0
}

LOCK_FILE="/var/lock/${slf[NAME]}.lock"
if [[ -f $LOCK_FILE ]]; then
 if [[ -f /proc/$(<$LOCK_FILE)/cmdline ]]; then
  echo "Lock file $LOCK_FILE exists and its in actual state, exiting..." >&2
  exit 1
 else
  rm -f $LOCK_FILE
 fi
fi
echo $$ > $LOCK_FILE
trap "rm -f $LOCK_FILE" SIGINT SIGTERM SIGHUP

while getopts 'a: d: e: xEC' key; do
 case $key in
  d) Date2Rep="$OPTARG" ;;
  e) emailTO="$OPTARG"  ;;
  a) areaID="$OPTARG"   ;;
  E) mode='-m extended' ;;
  C) flDeleteCSV=1	;;
  x) set -x; DEBUG=1    ;;
  \?|*) doShowUsage; exit 1 ;;
 esac
done

[[ $areaID ]] || {
 echo 'Error: not enough parameters passed' >&2
 doShowUsage
 exit 1
}

USER_HOME=$(getent passwd $(whoami) | cut -d: -f6)
confArea="${USER_HOME}/conf/report/${areaID,,}.ini"

[[ -f $confArea && -r $confArea ]] || {
 echo "Error: config file $confArea is invalid" >&2
 exit 2
}

REPORT_DATES=${Date2Rep:=$(date +%d.%m.%Y)} ./order_point_fc.sh ${flDeleteCSV:+-C} -i ${areaID^^} -f "$confArea" -d "/tmp" $mode
RETVAL=$?
rm -f $LOCK_FILE
exit $RETVAL
