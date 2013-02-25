#!/bin/bash -x
eval_dinv () { 
 local d days month year
 IFS='.' read days month year <<<"$1"
 if [[ ! $year ]]; then
  year=$month
  month=$days
  days='1-'$(date -d "${year}${month}01+1 month-1 day" +%d)
 fi
 for ((d=${days%-*}; d<=${days#*-}; d++)); do
  echo ${year}${month}$(printf '%02g' $d)
 done
 return 0
}

sqr_points () {
 local lat_u="$1" lon_l="$2"
 local lat_d=$(bc <<<"$lat_u-0.5")
 local lon_r=$(bc <<<"$lon_l+0.5")
 echo "$lat_u,$lon_l $lat_u,$lon_r $lat_d,$lon_l $lat_d,$lon_r"
 return 0
}

declare -A dblocks ul_point

 dblocks[RostovOnDon]='05.2012 06.2012 07.2012 08.2012'
ul_point[RostovOnDon]='47.5 39.5'

#if (( 0 )); then
#dblocks[Remontnoe]='4-7.01.2013 15-18.01.2013 23-26.01.2013'
 dblocks[Remontnoe]='06.2012 07.2012 08.2012'
ul_point[Remontnoe]='47.0 43.5'

#dblocks[Kazanskaya]='23-26.01.2013'
 dblocks[Kazanskaya]='06.2012 07.2012 08.2012'
ul_point[Kazanskaya]='50.0 41.0'

#dblocks[Millerovo]='22-25.11.2012 10-13.12.2012 25-28.12.2012 20-23.01.2013'
 dblocks[Millerovo]='06.2012 07.2012 08.2012'
ul_point[Millerovo]='49.0 40.0'

#dblocks[Taganrog]='10-13.12.2012 23-26.12.2012 10-13.01.2013 23-26.01.2013'
 dblocks[Taganrog]='05.2012 06.2012 07.2012 08.2012'
ul_point[Taganrog]='47.5 38.5'

#dblocks[Konstantinovsk]='10-13.12.2012 11-14.01.2013 25-28.01.2013'
 dblocks[Konstantinovsk]='06.2012 07.2012 08.2012'
ul_point[Konstantinovsk]='48.0 41.0'
#fi

ID='R-O-D_Thunder_2012.05-07'

baseDir="/tmp/$ID"
if [[ -d $baseDir ]]; then
 rm -rf $baseDir/*
else
 mkdir $baseDir
fi

for meteoStationID in ${!dblocks[@]}; do
 mkdir -p $baseDir/$meteoStationID
 for dblock in ${dblocks[$meteoStationID]}; do
  mkdir -p $baseDir/$meteoStationID/$dblock
  for d in $(eval_dinv $dblock); do
   for pp in $(sqr_points ${ul_point[$meteoStationID]}); do
    $HOME/bin/point_forecast -d $baseDir/$meteoStationID/$dblock -H 120 ${pp/,/ } $d 0
   done
  done   
 done
done
