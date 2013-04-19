USER_RUN_AS='grib'
BIN="$(getent passwd $USER_RUN_AS | cut -d':' -f6)/bin"
FILTER_PATH="$BIN/filters"
GRIB_BASE='/store/GRIB'
GFS_RAW="$GRIB_BASE/raw/GFS4"
GFS_RAW_NAMOS="$GFS_RAW/NAMOS"
GFS_RAW_NASA="$GFS_RAW/NASA"
[[ ${slf[NAME]-$slf} =~ CSV && ${GRID_BOUND=36:28:0.5 40:24:0.5} ]]
declare -A DEPS=(['GRIB2GET.sh']='get_inv.pl get_grib.pl')

GFS_COOKED="$GRIB_BASE/cooked/GFS4"
GFS_COOKED_CSV="$GFS_COOKED/csv"
#http://nomads.ncdc.noaa.gov/data/gfs4/201206/20120625/gfs_4_20120625_0000_000.grb2
BASEURL='http://nomads.ncdc.noaa.gov/data/gfs4/'

chkUnresDeps () {
 local dep errc=0 unres='' lst_deps="${DEPS[${slf[NAME]-${0##*/}}]}"
 [[ $lst_deps ]] || return 0
 for dep in $lst_deps; do
  which "$dep" &>/dev/null || {
   (( errc++ ))
   unres+=" $dep"
  }
 done
 echo -n "$unres"
 return $errc
}

chkRemoteFTPMounted () {
 mount | fgrep -q $GFS_RAW_NASA || \
  curlftpfs ftp://nomads.ncdc.noaa.gov/GFS/Grid4 $GFS_RAW_NASA
 return $?
}

getLatestDay () {
 local _last_month=$(curl -s $BASEURL | sed -nr "s%^.*<a href=\"([0-9]{6})/\">\1/</a>.*$%\1%p" | sort -rn | head -1)
 curl -s $BASEURL/${_last_month}/ | sed -nr "s%^.*<a href=\"([0-9]{8})/\">\1/</a>.*$%\1%p" | sort -rn | head -1
 return $?
}
getDateCmdArg () {
 if [[ $1 ]]; then
  [[ $1 =~ ^20[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]] || {
   echo "$slf: Unrecognized date passed to me, it must be in YYYY-MM-DD format" >&2
   exit 1
  }
  DATE="$1"
  svIFS=$IFS; IFS='-'
  y_m_d=($DATE)
  YM="${y_m_d[0]}${y_m_d[1]}"
  IFS=$svIFS
  YMD=${DATE//-/}
 else
 # We get parts of timestamp in UTC, because time in file names on FTP server is in UTC format
  YMD=$(getLatestDay) 
  YM="${YMD:0:6}"
  DATE="${YMD:0:4}-${YMD:4:2}-${YMD:6:2}"
 fi
 return 0
}
