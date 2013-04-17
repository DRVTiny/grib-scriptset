if (( flReCreateMP2LBL )); then
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

  for mp in {{U,V}GRD,RH,TMP,HGT}-{{100..900..50},{925..975..25}}_mb; do
   MP2LBL["$mp"]=$(sed -r 's%([UV]|T|RH|HGT)((GRD|MP)?)-([0-9]+)_mb%\1\4%' <<<"$mp")
  done

  MP2LBL+=(['TMAX-2_m_above_ground']='Tmax'  ['TMIN-2_m_above_ground']='Tmin'  ['TMP-2_m_above_ground']='T'  )
  MP2LBL+=(['UGRD-10_m_above_ground']='U10m' ['VGRD-10_m_above_ground']='V10m' ['RH-2_m_above_ground']='RH2m')
  MP2LBL+=(['WEASD-surface']='WEASD')
 ;;
 *)
  :
 ;;
 esac
else
 declare -A MP2LBL='(
		[UGRD-10_m_above_ground]="U10m"
		[UGRD-850_mb]="U850"
		[CSNOW-surface]="CSNOW"
		[CFRZR-surface]="CFRZR"
		[CRAIN-surface]="CRAIN"
		[TMP-500_mb]="T500"
		[RH-2_m_above_ground]="RH2m"
		[TMAX-2_m_above_ground]="Tmax"
		[GUST-surface]="GUST"
		[RH-700_mb]="RH700"
		[PRES-surface]="PRES"
		[TMP-850_mb]="T850"
		["TCDC-entire_atmosphere_(considered_as_a_single_layer)"]="TCDC"
		[CICEP-surface]="CICEP"
		[VGRD-10_m_above_ground]="V10m"
		[TMP-700_mb]="T700"
		[RH-500_mb]="RH500"
		[APCP-surface]="APCP"
		[UGRD-500_mb]="U500"
		[TMIN-2_m_above_ground]="Tmin"
		[VGRD-500_mb]="V500"
		[TMP-2_m_above_ground]="T"
		[UGRD-700_mb]="U700"
		[VGRD-850_mb]="V850"
		[RH-850_mb]="RH850"
		[VGRD-700_mb]="V700"
 )'
fi

declare -A NotInRA=(
		['APCP-surface']=3
		['CFRZR-surface']=3
		['CICEP-surface']=3
		['CRAIN-surface']=3
		['CSNOW-surface']=3
		['TCDC-entire_atmosphere_(considered_as_a_single_layer)']=3
		['TMAX-2_m_above_ground']=3
		['TMIN-2_m_above_ground']=3
)
                                                                
case ${mode=standart} in
standart)
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
		 'WEASD'
 )
;;
esac
declare  -A LBL2MP

for mp in ${!MP2LBL[@]}; do
 LBL2MP[${MP2LBL["$mp"]}]="$mp"
done
