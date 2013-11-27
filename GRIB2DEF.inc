USER_RUN_AS='grib'
BIN="$(getent passwd $USER_RUN_AS | cut -d':' -f6)/bin"
FILTER_PATH="$BIN/filters"
GRIB_BASE='/store/GRIB'
GFS_RAW="$GRIB_BASE/raw/GFS4"
GFS_RAW_NAMOS="$GFS_RAW/NAMOS"
GFS_RAW_NASA="$GFS_RAW/NASA"

declare -A DEPS=(
        ['GRIB2GET.sh']='get_inv.pl get_grib.pl curl parallel wgrib2'
	['GRIB2CSV.sh']='parallel wgrib2'
)

GFS_COOKED="$GRIB_BASE/cooked/GFS4"
GFS_COOKED_CSV="$GFS_COOKED/csv"
# Example file path: http://nomads.ncdc.noaa.gov/data/gfs4/201206/20120625/gfs_4_20120625_0000_000.grb2
BASEURL='http://nomads.ncdc.noaa.gov/data/gfs4/'
DEPS=''
chkUnresDeps () {
 local dep errc=0 unres='' lst_deps="${DEPS[${slf[NAME]-${0##*/}}]}"
 [[ $lst_deps ]] || return 0
 DEPS=''
 for dep in $lst_deps; do
  [[ $dep =~ / && -f $dep ]] || which "$dep" &>/dev/null || {
   (( errc++ ))
   DEPS+=" $dep"
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
  [[ $1 =~ ^(20[0-9]{2})[-.]?([0-9]{2})[-.]?([0-9]{2})$ ]] || {
   echo "${slf}.getDateCmdArg: Error: Unrecognized date passed to me, it must be in YYYY-MM-DD or YYYYMMDD format" >&2
   return 1
  }
 # Save original formatting in DATE var
  DATE=$1
  y_m_d=(${BASH_REMATCH[@]:1:3})
  YM="${y_m_d[0]}${y_m_d[1]}"
  YMD="${YM}${y_m_d[2]}"
 else
 # We get parts of timestamp in UTC, because time in file names on FTP server is in UTC format
  YMD=$(getLatestDay) 
  YM="${YMD:0:6}"
  DATE="${YMD:0:4}-${YMD:4:2}-${YMD:6:2}"
 fi
 return 0
}
