#!/usr/bin/perl
#=<DEPS>
use PerlIO::gzip;
use Date::Calc qw(Delta_DHMS Days_in_Month Add_Delta_Days);
use File::Path qw(mkpath);
use Math::Round qw(nearest);
use List::Util qw(min max);
use Math::Trig;
use Spreadsheet::WriteExcel;
#=</DEPS>

#=<CONST>
use constant AREA_CONF_DIR => '/etc/grib';
use constant OUT_BASE_DIR => '/store/GRIB/compare/GFS4';
use constant FACT_BASE_DIR => '/store/GRIB/fact/GFS4';
use constant PRED_BASE_DIR => '/store/GRIB/cooked/GFS4/Stations';
use constant COOKED_BASE_DIR => '/store/GRIB/cooked/GFS4';
use constant FILTERS_DIR => '/usr/local/warehouse/grib/bin/filters';
use constant ZEROC=>273.15;
use constant StepLat=>0.5;
use constant StepLon=>0.5;
my $DAY_REGEX='(?:0[1-9]|[12][0-9]|3[0-1])';
my $MONTH_REGEX='(?:0[1-9]|1[0-2])';
my $YEAR_REGEX='20(?:[2-9][0-9]|1[2-9])';
my $YMD_REGEX="^(${YEAR_REGEX})[-._]?(${MONTH_REGEX})[-._]?(${DAY_REGEX})\$";
my $YM_REGEX="^(${YEAR_REGEX})[-._]?(${MONTH_REGEX})\$";
my %StaDim=( 'Rostov-On-Don'=>{lat=>47.3,lon=>39.8,alt=>75,area=>'rostov-on-don-short'},
             'Taganrog'=>{lat=>47.2,lon=>38.9,alt=>32,area=>'rostov-on-don-short'},
             'Tsimlyansk'=>{lat=>47.6,lon=>42.1,alt=>65,area=>'rostov-on-don-short'},
             'Remontnoe'=>{lat=>46.6,lon=>43.7,alt=>106,area=>'rostov-on-don-short'},
             'Giant'=>{lat=>46.5,lon=>41.3,alt=>79,area=>'rostov-on-don-short'},
             'Kazanskaya'=>{lat=>49.8,lon=>41.2,alt=>72,area=>'rostov-on-don-short'},
             'Millerovo'=>{lat=>48.9,lon=>40.4,alt=>155,area=>'rostov-on-don-short'},
             'Konstantinovsk'=>{lat=>47.6,lon=>41.1,alt=>66,area=>'rostov-on-don-short'} );
#=</CONST>

#=<GLOBAL>
my (%fact,%comp,%diff);
#=</GLOBAL>

#=<ARGS>
my ($StationID,$YearMonth)=@ARGV;
die 'Unknown station ID' unless defined $StaDim{$StationID};
my ($areaID,$pLat,$pLon)=( $StaDim{$StationID}{area}, $StaDim{$StationID}{lat}, $StaDim{$StationID}{lon} );
my ($Year,$Month)=($YearMonth=~m/^${YM_REGEX}/);
my $DaysInMonth=Days_in_Month($Year,$Month);
#=</ARGS>

#=<SUBS>
require 'point_forecast.subs';
#=</SUBS>

#=<CELL>
my @cell=approx2grid($pLat,$pLon,StepLat,StepLon);
my $kLat=($pLat-$cell[2]->{lat})/StepLat;
my $kLon=($pLon-$cell[0]->{lon})/StepLon;

my $rxCell='^(';
$rxCell.=sprintf('%.02f',$_->{lon}).'0+\s*,\s*'.sprintf('%.02f',$_->{lat}).'|' foreach @cell;
$rxCell=substr($rxCell,0,-1).')0+';
#=</CELL>

#=<AREACONF>
my %areaConf;
open (AREACONF,"<".AREA_CONF_DIR."/$areaID.inc") || die "Cant open ".AREA_CONF_DIR."/$areaID.inc\n";
while (<AREACONF>) {
 $areaConf{$1}=$3 if (m/^([^=]+?)\s*=\s*(?'quote'['"]?)(.+?)\k'quote'\s*$/); 
}
close(AREACONF);
$areaConf{MPARS_LIST_FILE}=FILTERS_DIR.'/'.$areaConf{MPARS_LIST_FILE} if (index($areaConf{MPARS_LIST_FILE},'/')<0);
my $DATA_ID=$areaConf{DATA_ID};
my $MAX_PRED_H=$areaConf{WFC_PREDICT_H} || 120;
my $STEP_PRED_H=$areaConf{WFC_STEP_H} || 3;
#=</AREACONF>

#=<FILTERFILE>
my @IsBool=('CSNOW','CRAIN','CFRZR','CICEP');
open (MPL,'<',$areaConf{MPARS_LIST_FILE});
my $mp,$lvl;
my %MParLvls;
while (<MPL>) {
 chomp;
 ($_,$mp,$lvl)=split /:/;
 $lvl=~s%\s%_%g;
 push @{$MParLvls{$mp}}, $lvl;
}
close(MPL);
#=</FILTERFILE>

#=<NOTINRA>
open(RAE,'<reanalyze_excl.inc');
chomp ( @NotInRA = grep /\=3/,(<RAE>) );
for ($i=0; $i<@NotInRA; $i++) {
 $NotInRA[$i]=~s%(^\s*\[\'|\'\]\s*=\s*3\s*$)%%g;
}
my $csvNotInRA=join(',',@NotInRA).',';
close(RAE);
#=</NOTINRA>

#=<LABELS>
eval `bash -c "source ~grib/bin/grib-scriptset/point_forecast_hashes_standart.def; source /opt/scripts/functions/perl.inc; PerlDcl_Arr MP2LBL LBL2MP LBLOrder"`;
foreach ('WINDS','WINDD') {
 $MP2LBL{$_.'-10_m_above_ground'}=$_ ;
 $LBL2MP{$_}=$_.'-10_m_above_ground';
 push @LBLOrder, $_;
}
push @LBLOrder,('APCP12','dayTmax','dayTmin');
#=</LABELS>

#=<FACT>
%dscFactCSV=(
 HOUR => { COL=>0 },
  DATE => { COL=>1 },
   WINDD => { COL=>2 },
    WINDS => { COL=>3 },
     GUST => { COL=>4 },
      CSNOW => { COL=>10, 
                 CONV=>[ sub { return shift || 0; } ] },
       CRAIN => { COL=>11,
                 CONV=>[ sub { return shift || 0; } ] },
        T => { COL=>17,
               CONV=>[ \&cnvFactT ] },
         RH2m => { COL=>19 },
          PRES => { COL=>23, 
                    CONV=>[ \&cnvFactPres ] },
           dayTmin => { COL=>24,
                        CONV=>[ \&cnvFactT ] },
            dayTmax => { COL=>25,
                         CONV=>[ \&cnvFactT ] },
             APCP12 => { COL=>26 }
);
#my %fact;
my @mpidsFact= grep(!/(HOUR|DATE)/, keys %dscFactCSV);
my @mpidsOut=grep { my $t=$_; grep { $t eq $_ } @mpidsFact } @LBLOrder;
my $factFile=FACT_BASE_DIR."/${Year}${Month}/${StationID}_${Year}${Month}.csv";
open (FACT,'<',$factFile) || die "Cant open fact file ${factFile}: ".$!;
$_=<FACT>;
#$monthFilter="^[0-9]+;${DAY_REGEX},${Month},".substr($Year,2,2).';';
#foreach ( grep /${monthFilter}/,(<FACT>) ) {
my ($fmbh,$fdsh);
while (<FACT>) {
 my @l=split /\;/;
 if ( $l[$dscFactCSV{DATE}->{COL}] ) {
  $fdsh=$l[$dscFactCSV{HOUR}->{COL}];
  my ($D,$M,$Y)=split(/,/,$l[$dscFactCSV{DATE}->{COL}]);
  if ($M eq $Month) {
   $fmbh=($D-1)*24+$fdsh;
  } else {
   my ($days,$hours,undef,undef) = Delta_DHMS($Year,$Month,1,0,0,0,2000+$Y,$M,$D,$fdsh,0,0);
   $fmbh=$days*24+$hours;
  }
 } else {
  $fmbh+=($l[$dscFactCSV{HOUR}->{COL}]-$fdsh);
  $fdsh=$l[$dscFactCSV{HOUR}->{COL}];
 }
 foreach my $lbl ( @mpidsFact ) {
  (my $v=$l[$dscFactCSV{$lbl}{COL}] ne ''?$l[$dscFactCSV{$lbl}{COL}]:undef)=~s%,%.%;
  if ( $dscFactCSV{$lbl}{CONV} ) {
   $v=&$_($v) foreach @{ $dscFactCSV{$lbl}{CONV} };
  } 
  $fact{$lbl}{$fmbh-($lbl=~m/dayTm(?:ax|in)/?$fmbh%24:0)}=$v if defined($v);
 }
 
}

my $maxFactFMBHours=$fmbh;

#my @t=sort {$a<=>$b} keys %{$fact{APCP12}};
#dbgShowHsh(\%fact,['dayTmin']);
#exit(0);

close(FACT);
#=</FACT>

#=<DAYS>
# FMBH means 'from month base hours'
my $FMBHours=0;

my $outDir=OUT_BASE_DIR.'/'.$StationID.'/'.$Year.$Month;
#mkpath([ map { $outDir.'/'.$_ } (@mpidsOut,'xls') ]);
my $predDir=PRED_BASE_DIR.'/'.$StationID.'/'.$Year.$Month;
mkpath($predDir);

#$DaysInMonth=3;
for (my $Day=1; $Day<=$DaysInMonth; $Day++) {
 my $maxFMBH=min($FMBHours+$MAX_PRED_H,$maxFactFMBHours);
 my $Date=$Year.$Month.sprintf('%02g',$Day);
 my $srcDir=COOKED_BASE_DIR.'/'.$DATA_ID.'/'.$Date;
 
#==<READ4POINTS>
 foreach my $mp (keys %MParLvls) {
  foreach my $lvl ( @{ $MParLvls{$mp} } ) {
   for (my $predH=0; $predH<=$MAX_PRED_H; $predH+=$STEP_PRED_H) {
    my $mpid="${mp}-${lvl}";
    if ($predH eq 0 && index($csvNotInRA,"${mpid},")>=0 ) {
# Remember: @cell is a GLOBALy-visible list!
     $_->{mpv}->{$mpid}->{0}=$_->{mpv}->{$mpid}->{24} foreach ( @cell );
     next;
    }
    my $csvFile="$srcDir/gfs_4_${Date}_0000_".sprintf('%03g',$predH)."_${mp}-${lvl}.csv.gz";
    open CSV, "<:gzip", "$csvFile" or die "Cant open source file: $csvFile";
    chomp ( my @mpv=grep /${rxCell}/,(<CSV>) );
    foreach ( @cell ) {
     my $rx='^'.sprintf('%.02f',$_->{lon}).'0+\s*,\s*'.sprintf('%.02f',$_->{lat});
     $_->{mpv}->{"${mp}-${lvl}"}->{$predH}=[ split /\s*,\s*/,[ grep /${rx}/,@mpv ]->[0] ]->[2];
    } 
    close(CSV);
   }
  }
 }
#==</READ4POINTS>

#==<IPOL2POINT>
 my %pred;
 foreach my $mp (keys %{$cell[0]->{mpv}}) {
  die "No label for ${mp}" unless (my $lbl=$MP2LBL{$mp}); 
  my ($mpid,$lvl)=($mp=~m/^(.+?)-(.+)$/);
  my @C; $C[$_]=$cell[$_]->{mpv}->{$mp} foreach 0..3;
  for (my $predH=0; $predH<=$MAX_PRED_H; $predH+=$STEP_PRED_H) {
   my $R2=$C[0]->{$predH}+$kLon*($C[1]->{$predH} - $C[0]->{$predH});
   my $R1=$C[3]->{$predH}+$kLon*($C[2]->{$predH} - $C[3]->{$predH});
   my $R=$R1+$kLat*($R2-$R1);
   $R=($R>0.5?1:0) if ( grep { $_ eq $mpid } @IsBool );
   my $fmbh=$predH+$FMBHours;
   $pred{$lbl}->{$fmbh}=$R;
  }
 }
#==</IPOL2POINT>

#==<DAYTMIMA>
 foreach my $fmbhDay ( map { $FMBHours+24*$_ } 0..($MAX_PRED_H/24-1) ) {
  foreach ('max','min') {
   $pred{'dayT'.$_}->{$fmbhDay}=&$_(@{$pred{'T'.$_}}{(map { $fmbhDay+$_*$STEP_PRED_H } 1..24/$STEP_PRED_H)});
  }
 } 
#=<DAYTMIMA>

#=<SUMAPCP12>
my $p_fmbh=$FMBHours;
#my @t=sort { $a<=>$b } grep { ($_>=$FMBHours) and ($_<=$maxFMBH) } keys %{$fact{APCP12}};
#foreach my $fmbh12 ( @t ) {
foreach my $fmbh12 ( sort { $a<=>$b } grep { ($_>=$FMBHours) and ($_<=$maxFMBH) } keys %{$fact{APCP12}} ) {
 my $precp=0;
 for (my $fmbh=$p_fmbh+$STEP_PRED_H; $fmbh<=$fmbh12; $fmbh+=$STEP_PRED_H) {
  $precp+=$pred{APCP}{$fmbh};
 }
 $pred{APCP12}{$fmbh12}=nearest(0.01,$precp);
 $p_fmbh=$fmbh12;
}

#if ($Day==14) {
# print "<fact>\n";
# dbgShowHsh(\%fact,['APCP12'],\@t);
# print "</fact>\n";
# print "<pred>\n";
# dbgShowHsh(\%pred,['APCP12'],\@t);
# print "</pred>\n";
#}
#==</SUMAPCP12>

# if (0) {

#==<WINDCALC> 
 my $fmbh=$FMBHours;
 foreach (0..$MAX_PRED_H/3) {  
  my ($U,$V)=( $pred{'U10m'}{$fmbh}, $pred{'V10m'}{$fmbh} );
  my $W=sqrt( $U**2 + $V**2 );
  $pred{'WINDS'}{$fmbh}=$W;
  my $A=360+(180/pi)*($U>0?-1:1)*acos(-$V/$W); 
  $pred{'WINDD'}{$fmbh}=($A>=360?$A-360:$A);  
  $fmbh+=3;
 }
#==</WINDCALC>

#==<OUTPRED> 
 my @mem=( 'FMBH;'.join(';',keys %pred) );
 for (my $fmbh=$FMBHours; $fmbh<=$FMBHours+$MAX_PRED_H; $fmbh+=$STEP_PRED_H) {
  push @mem,$fmbh.';'.(join ';', map { nearest(0.01,$pred{$_}{$fmbh}) } keys %pred);
 }
 
 open(PRED,'>',$predDir.'/'.$Date.'.csv');
 print PRED join("\n", @mem);
 close(PRED);
 
 @mem=();
#==</OUTPRED>

#==<DAY2COMP>
 foreach my $lbl (@mpidsOut) {
  my ($F,$P,$C,$D)=( $fact{$lbl}, $pred{$lbl}, {}, $diff{$lbl} );
  foreach my $fmbh ( grep { $F->{$_} ne undef } sort {$a <=> $b} keys %{$P} ) {
   my ($predH,$fv,$pv,$yy,$mm,$dd,$hh)=($fmbh-$FMBHours,$F->{$fmbh},$P->{$fmbh},fmbh2date($Year,$Month,$fmbh));
   my $delta=getFactPreDelta($lbl,$fv,$pv);
   $D->{$predH}+=$delta;
   $C->{$fmbh}=[$predH,"${yy}-${mm}-${dd}",$hh,$fv,nearest(0.01,$pv),$delta];
  }
  $diff{$lbl}=$D;
  $comp{$lbl}[$Day-1]=$C;
 }
#==</DAY2COMP>
 $FMBHours+=24;
}
#=</DAYS>

#=<OUTCMP>
my %DiffID=('e'=>'System', 'a'=>'Absolute');
foreach my $mp (keys %comp) {
 my $fileOut="${outDir}/${mp}-${Year}${Month}.xls";
 my $wb = Spreadsheet::WriteExcel->new($fileOut) || die "Cant create xls spreadsheet ${fileOut}: ".$!; 
 my $boldStyle=$wb->add_format(bold=>1);
 for (my $Day=1; $Day<=@{$comp{$mp}}; $Day++) {
  my $sheet=$wb->add_worksheet($Day);
  my ($row,$col)=(0,0);  
  $sheet->write($row, $col++, $_) foreach ('PREDH','DATE','+HOURS','FACT','PRED','DELTA');
  my $table=$comp{$mp}[$Day-1];
  foreach my $fmbh (sort { $a <=> $b } keys %{$table}) {
   $row+=1; $col=0;
   $sheet->write($row, $col++, $_) foreach @{$table->{$fmbh}};
  } # FMBH
 } # Days
 my %tblDiff;
 my $predH=[ sort {$a<=>$b} keys %{$diff{$mp}} ];
 my $l=@{$predH};
 $tblDiff{$_}[0]=$predH foreach ('e','a');
 foreach ( @{$predH} ) {
  my $d=$diff{$mp}{$_};
  $d/=$l;
  push @{$tblDiff{'e'}->[1]},$d;
  push @{$tblDiff{'a'}->[1]},abs($d);
 }
 foreach my $et ('e','a') {
  my $sh=$wb->add_worksheet($et);
  $sh->write('A1',[ ['PREDH'],['DELTA'] ],$boldStyle);
  $sh->write('A2',$tblDiff{$et});
  my $ch = $wb->add_chart( type => 'line', embedded => 1 );
  $ch->add_series(
         name       => $DiffID{$et}.' error / predict hours',
         categories => '='.$et.'!$A$2:$A$42',
         values     => '='.$et.'!$B$2:$B$42',
                   );
  $ch->set_x_axis( name => 'Hours of prediction' );
  $ch->set_y_axis( name => $DiffID{$et}.' diff b/w fact and pred' );
                       
  $sh->insert_chart('C2',$ch,25,10,3,1);
 }
  
 $wb->close();
} # Meteopars
#=</OUTCMP>
