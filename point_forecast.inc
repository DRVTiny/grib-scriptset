
if (( flReCompileHashes )); then
 declare  -A MP2LBL
 case ${mode=standart} in
 standart)
  for mp in 'TCDC-entire_atmosphere_(considered_as_a_single_layer)' {PRES,GUST,APCP,CSNOW,CRAIN,CICEP,CFRZR}-surface; do
   MP2LBL["$mp"]="${mp%%-*}"
  done

  for mp in {{U,V}GRD,RH,TMP}-{50,70,85}0_mb; do
   MP2LBL["$mp"]=$(sed -r 's%([UV]|T|RH)((GRD|MP)?)-(([57]0|85)0)_mb%\1\4%' <<<"$mp")
  done

  MP2LBL+=(['TMAX-2_m_above_ground']='Tmax' ['TMIN-2_m_above_ground']='Tmin' ['TMP-2_m_above_ground']='T')
  MP2LBL+=(['UGRD-10_m_above_ground']='U10m' ['VGRD-10_m_above_ground']='V10m' ['RH-2_m_above_ground']='RH2m')
 ;;
 extended)
  for mp in 'TCDC-entire_atmosphere_(considered_as_a_single_layer)' {PRES,GUST,APCP,CSNOW,CRAIN,CICEP,CFRZR}-surface; do
   MP2LBL["$mp"]="${mp%%-*}"
  done

  for mp in {{U,V}GRD,RH,TMP,HGT,VVEL}-{{100..900..50},{925..975..25}}_mb; do
   MP2LBL["$mp"]=$(sed -r 's%([UV](VEL)?|T|RH|HGT)((GRD|MP)?)-([0-9]+)_mb%\1\5%' <<<"$mp")
  done

  MP2LBL+=(['TMAX-2_m_above_ground']='Tmax'  ['TMIN-2_m_above_ground']='Tmin'  ['TMP-2_m_above_ground']='T'  )
  MP2LBL+=(['UGRD-10_m_above_ground']='U10m' ['VGRD-10_m_above_ground']='V10m' ['RH-2_m_above_ground']='RH2m')
  MP2LBL+=(['WEASD-surface']='WEASD')
 ;;
 *)
  :
 ;;
 esac
 # On the fly create hash for reverse matching (table's label to meteoparameter ID)
 declare  -A LBL2MP
 for mp in ${!MP2LBL[@]}; do
  LBL2MP[${MP2LBL["$mp"]}]="$mp"
 done
else
# Load pre-compiled hashes
# NOTE: To create apropriate ".def" files, call point_forecast with -Z key and -m TYPE_OF_HASHes parameters!
 case ${mode=standart} in
 standar[td])
  source ${slf[PATH]}/${slf[NAME]%.*}_hashes_standart.def
 ;;
 extended)
  source ${slf[PATH]}/${slf[NAME]%.*}_hashes_extended.def
 ;;
 *) 
  :
 ;;
 esac
fi

source $(dirname $(readlink -e "$0"))/reanalyze_excl.inc
                                                                
case ${mode=standart} in
standar[td])
 declare -a LBLOrder=(
                 'PRES'
                 'TCDC'
                 'CSNOW'
                 'CRAIN'
                 'CICEP'
                 'CFRZR'
                 'APCP'
                 'GUST'
                 'V500'
                 'V700'
                 'V850'
                 'V10m'
                 'U500'
                 'U700'
                 'U850'
                 'U10m'
                 'RH500'
                 'RH700'
                 'RH850'
                 'RH2m'
                 'T500'
                 'T700'
                 'T850'
                 'Tmax'
                 'Tmin'
                 'T'
 )
;;
extended)
 declare -a LBLOrder=(
                 'PRES'
                 'TCDC'
                 'CSNOW'
                 'CRAIN'
                 'CICEP'
                 'CFRZR'
                 'APCP'
                 'GUST'
                 V{{100..900..50},{925..975..25}}
                 'V10m'
                 U{{100..900..50},{925..975..25}}
                 'U10m'
		 RH{{100..900..50},{925..975..25}}
                 'RH2m'
                 T{{100..900..50},{925..975..25}}
                 'Tmax'
                 'Tmin'
                 'T'
		 HGT{{100..900..50},{925..975..25}}
		 VVEL{{100..900..50},{925..975..25}}
		 'WEASD'
 )
;;
esac
