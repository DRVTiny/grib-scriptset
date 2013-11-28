#!/usr/bin/perl
#=<DEPS>
use Getopt::Compact;
use PerlIO::gzip;
use Time::Local qw(timelocal);
use Date::Calc qw(Delta_DHMS Delta_Days Days_in_Month Add_Delta_Days);
use File::Path qw(mkpath);
use Math::Round qw(nearest);
use List::Util qw(min max);
use Math::Trig;
use Spreadsheet::WriteExcel;
#=</DEPS>

#=<CONST>
# We are going to work only with GMT!
$ENV{TZ}='GMT';
use constant DEFAULT_AREA_ID => 'rostov-on-don-short';
use constant AREA_CONF_DIR => '/etc/grib';
use constant COMP_BASE_DIR => '/store/METEO/compare/Stations';
use constant FACT_BASE_DIR => '/store/METEO/fact';
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
my $LALO_REGEX='^([-+]?[1-9][0-9]{0,1}(?:\.[0-9]+)?),(\+?[1-9][0-9]{0,2}(?:\.[0-9]+)?)$';
my %DiffID=('e'=>'System', 'a'=>'Absolute');
my %StaDim=( 'Rostov-On-Don'=>{lat=>47.3,lon=>39.8,alt=>75,area=>'rostov-on-don-short'},
             'Taganrog'=>{lat=>47.2,lon=>38.9,alt=>32,area=>'rostov-on-don-short'},
             'Tsimlyansk'=>{lat=>47.6,lon=>42.1,alt=>65,area=>'rostov-on-don-short'},
             'Remontnoe'=>{lat=>46.6,lon=>43.7,alt=>106,area=>'rostov-on-don-short'},
             'Giant'=>{lat=>46.5,lon=>41.3,alt=>79,area=>'rostov-on-don-short'},
             'Kazanskaya'=>{lat=>49.8,lon=>41.2,alt=>72,area=>'rostov-on-don-short'},
             'Millerovo'=>{lat=>48.9,lon=>40.4,alt=>155,area=>'rostov-on-don-short'},
             'Konstantinovsk'=>{lat=>47.6,lon=>41.1,alt=>66,area=>'rostov-on-don-short'} );
my %ConvFactVal=(
 'TIME' => undef,
  'DATE' => undef,
   'WDIR' => undef,
    'WIND' => undef,
     'GUST' => undef,
      'CSNOW' => [ sub { return shift || 0; } ],
       'CRAIN' => [ sub { return shift || 0; } ],
        'T' => [ \&cnvFactT ],
         'RH2m' => undef,
          'PRES' => [ \&cnvFactPres ],
           'dayTmin' => [ \&cnvFactT ],
            'dayTmax' => [ \&cnvFactT ],
             'APCP12' => undef
);
my %MPID2HEADF=(
 'TIME' => undef,
  'DATE' => undef,
   'WDIR' => undef,
    'WIND' => undef,
     'GUST' => undef,
      'CSNOW' => [ 'SNOW' ],
       'CRAIN' => [ 'RAIN' ],
        'T' => [ 'TMP' ],
         'RH2m' => [ 'R','RH' ],
          'PRES' => [ 'P' ],
           'dayTmin' => [ 'Tmin' ],
            'dayTmax' => [ 'Tmax' ],
             'APCP12' => undef
);
my %HEADF2MPID;
foreach my $mpid (keys %MPID2HEADF) {
 $HEADF2MPID{$mpid}=$mpid;
 if ($MPID2HEADF{$mpid}) {
  $HEADF2MPID{$_}=$mpid foreach @{ $MPID2HEADF{$mpid} };
 }
}
my @mpidsFact= grep(!/(TIME|DATE)/, keys %ConvFactVal);

#=</CONST>

#=<SUBS>
require 'point_forecast.subs';
#=</SUBS>
 
#=<ARGS>
my ($YearMonth,$dayStart,$dayEnd,$fileStations,$factDir, $csvDir,         $MAX_PRED_H, $STEP_PRED_H, $viewMode, @viewExcl)=
   (undef,     undef,    undef,  undef,        undef,    COOKED_BASE_DIR, 120,         3           , 'V'      );

$ARGV[0]='--help' unless @ARGV;
my $flCompare=grep(/^-(?:[Fc]|-(?:factdir|compare))$/,@ARGV);
my $opts = new Getopt::Compact
 ( name => 'point_forecast.pl', version => '0.021',
   struct => [ [ [qw(b begin)],   qq(Begin (date)), '=s',                         \$dayStart ],
               [ [qw(e end)],     qq(End (date)), '=s',                           \$dayEnd   ],
               [ [qw(F factdir)], qq(Directory with meteostation observed data),':s' ],
               [ [qw(C csv-dir)], qq(Directory with CSV representation of GFS data),'=s', \$csvDir  ],
               [ [qw(m month)],   qq(Month to compare: in YYYYMM (ex.: '201308') format), '=s',   \$YearMonth ],
               [ [qw(c compare)], qq(Compare mode on) ],
               [ [qw(f file)],    qq(File contains list of stations to proceed),'=s',\$fileStations ],
               [ [qw(H maxh)],  'Max predict hours (default: 120)','=s',         \$MAX_PRED_H ],
               [ [qw(S steph)], 'Step between predict hours (default: 3)','=s',  \$STEP_PRED_H ],
               [ [qw(view-mode)], 'View mode (horizontal or vertical)','=s',  \$viewMode ],
               [ [qw(view-excl)], 'Exclude meteoparameters from the prediction output','=s',  \@viewExcl ],
             ]
 )->opts;
#==<ARGS.viewSettings>
my %predVMods=('V'=>'V','H'=>'H','R'=>'H','C'=>'V');
$viewMode=$predVMods{uc(substr($viewMode,0,1))} || 
 die "\"--viewmode ${viewMode}\" is incorrect: must be 'H' or 'V': meteoparameters values in rows(H) or columns(V)";
my %ViewSettings=('Mode'=>$viewMode,'rxExcl'=>'^(?:'.join('|',map { $_=~s%[,;[:space:]]+%|%g; $_ } @viewExcl).')$');
#==</ARGS.viewSettings>
#==<ARGS.factDir>
$factDir=$opts->{'factdir'}?$opts->{'factdir'}:($flCompare?FACT_BASE_DIR:undef);
#==</ARGS.factDir>
#=</ARGS>

#=<DATE>
my (%Start,%End,$DeltaDays);

if ($dayStart) {
 my @DD=( [ $dayStart=~m/${YMD_REGEX}/ ], [ $dayEnd=~m/${YMD_REGEX}/ ] );
 @Start{'Year','Month','Day'}=@{$DD[0]};
 @End{'Year','Month','Day'}=@{$DD[1]}; 
 $DeltaDays=1+Delta_Days($DD[0][0],$DD[0][1],$DD[0][2],$DD[1][0],$DD[1][1],$DD[1][2]);
 die "Start date must be earlier than end date" unless $DeltaDays>=0; 
} else {
 @Start{'Year','Month','Day'}=($YearMonth=~m/^${YM_REGEX}/,'01');
 $DeltaDays=Days_in_Month($Start{'Year'},$Start{'Month'});
 @End{'Year','Month','Day'}=(@Start{'Year','Month'},$DeltaDays);
}
my @D=(\%Start,\%End);
# All timestamps with hour granularity, so TS(hours)=TS(POSIX, inseconds)/3600
foreach (@D) {
 $_->{'YM'}=$_->{'Year'}.$_->{'Month'};
 $_->{'Date'}=$_->{'YM'}.$_->{'Day'};
 $_->{'YMD'}=$_->{'Date'};
 $_->{'TSH'}=timelocal(0,0,0,$_->{'Day'},$_->{'Month'}-1,$_->{'Year'})/3600;
}
#=</DATE>
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
foreach ('WIND','WDIR') {
 $MP2LBL{$_.'-10_m_above_ground'}=$_ ;
 $LBL2MP{$_}=$_.'-10_m_above_ground';
 push @LBLOrder, $_;
}
push @LBLOrder,('APCP12','dayTmax','dayTmin');
#=</LABELS>

#=<LOOP.StationID>
if ($fileStations) {
 ( -f $fileStations ) || die "Stations file is absent";
 shift while @ARGV;
 open(STA,"<${fileStations}") || die "Cant open 'stations' file (specified with -f)";
 push @ARGV,map { chomp; $_ } (<STA>);
 close(STA);
}
while (my $StationID=shift) {
 my %geo;
#=<GHASHES>
 my (%fact,%comp,%diff);
#=</GHASHES> 
 if ($StationID eq 'all') {
  push @ARGV,keys %StaDim;
  next;
 } elsif (@geo{('Lat','Lon')}=($StationID =~ m/${LALO_REGEX}/)) {
  $geo{'StationID'}="Points/$StationID";
# FIX ME! ->
  $geo{'AreaID'}=DEFAULT_AREA_ID;
# <-
 } else {
  die 'Unknown station ID' unless defined $StaDim{$StationID};
  @geo{('StationID','AreaID','Lat','Lon')}=($StationID,@{$StaDim{$StationID}}{('area','lat','lon')});
 }
 #=<CELL>
#  cell[] indexes (turn clockwise from up left point to down left one):
#    |     |
#  - 0 --- 1 -
#    |     |
#    |   * |
#  - 3 --- 2 -
#    |     |
 my @cell=approx2grid($geo{'Lat'},$geo{'Lon'},StepLat,StepLon);
 my $kLat=($geo{'Lat'}-$cell[2]->{'lat'})/StepLat;
 my $kLon=($geo{'Lon'}-$cell[0]->{'lon'})/StepLon;

 my $rxCell='^(';
 $rxCell.=sprintf('%.02f',$_->{lon}).'0+\s*,\s*'.sprintf('%.02f',$_->{lat}).'|' foreach @cell;
 $rxCell=substr($rxCell,0,-1).')0+';
 #=</CELL>
# print join(';', map { $_.'='.$geo{$_} } keys %geo) . "\n";
# exit(0);
 #=<AREACONF>
 my %areaConf;
 $areaConf{'configFile'}=AREA_CONF_DIR.'/'.$geo{'AreaID'}.'.inc';
 open (AREACONF,'<',$areaConf{'configFile'}) || die "Cant open ".$areaConf{'configFile'}."\n";
 while (<AREACONF>) {
  $areaConf{$1}=$3 if (m/^([^=]+?)\s*=\s*(?'quote'['"]?)(.+?)\k'quote'\s*$/); 
 }
 close(AREACONF);
 $areaConf{'MPARS_LIST_FILE'}=FILTERS_DIR.'/'.$areaConf{'MPARS_LIST_FILE'} if (index($areaConf{'MPARS_LIST_FILE'},'/')<0);
 my $DATA_ID=$areaConf{'DATA_ID'};
 $MAX_PRED_H=$areaConf{'WFC_PREDICT_H'} unless $MAX_PRED_H;
 $STEP_PRED_H=$areaConf{'WFC_STEP_H'} unless $STEP_PRED_H;
 #=</AREACONF>

 #=<FILTERFILE>
 my @IsBool=('CSNOW','CRAIN','CFRZR','CICEP');
 open (MPL,'<',$areaConf{'MPARS_LIST_FILE'});
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

 #=<FACT>
 my ($maxFactTSH,@mpidsOut);
 if ($factDir) {
  @mpidsOut=grep { my $t=$_; grep { $t eq $_ } @mpidsFact } @LBLOrder;
  my $factFile=$factDir.'/'.$Start{'YM'}.'/'.$geo{'StationID'}.'_'.$Start{'YM'}.'.csv';
  $factFile=$factDir.'/'.$Start{'YM'}.'/'.$geo{'StationID'}.'.csv' unless  -f $factFile;
  open (FACT,'<',$factFile) || die "Cant open fact file ${factFile}: ".$!;
  
  my (@Col2Lbl,$j);
  $Col2Lbl[$j++]=$HEADF2MPID{$_} || $_ foreach map { $_=~m/^\s*(.+?)\s*$/; $1 } split(';',<FACT>);
  
# = tsh means 'UNIX time stamp in hours'
# = fdsh means 'time from day start in hours'
  my ($tsh,$fdshOld);
  while (<FACT>) {
   my (%F,$j);
   $F{$Col2Lbl[$j++]}=$_ foreach split /\;/;
   my ($fdsh,$date)=@F{'TIME','DATE'};
   if ( $date ) {
    my ($D,$M,$Y)=split(/[,.]/,$date);
# Good news: timelocal function is very clever and it can predictably work
# with years in YY format such as "13" or "69" (refer to Time::Local documentation)
    $tsh=timelocal(0,0,$fdsh,$D,$M-1,$Y)/3600;
   } else {
    $tsh+=$fdsh-$fdshOld+($fdsh>=$fdshOld?0:24);
   }
   $fdshOld=$fdsh;
   foreach my $lbl ( @mpidsFact ) {
    (my $v=$F{$lbl} ne ''?$F{$lbl}:undef)=~s%,%.%;
    if ( $ConvFactVal{$lbl} ) {
     $v=&$_($v) foreach @{ $ConvFactVal{$lbl} };
    }
    $fact{$lbl}{$tsh-($lbl=~m/dayTm(?:ax|in)/?$tsh%24:0)}=$v if defined($v);
   }
  }
# Save last (maximum) value of tsh
  $maxFactTSH=$tsh;
  
  #my @t=sort {$a<=>$b} keys %{$fact{APCP12}};
#  print "StationID=${StationID}\n";
#  dbgShowHsh(\%fact,['APCP12','dayTmin','dayTmax']);
#  exit(0);

  close(FACT);
 }
 #=</FACT>

 #=<LOOP.Days>
 my $tshBaseDay=$Start{'TSH'};
 my ($curYear,$curMonth,$curDay)=@Start{'Year','Month','Day'}; 
 my ($compDir,$predDir)=map { ( -d $_ ) || mkpath($_); $_ } (COMP_BASE_DIR.'/'.$geo{'StationID'},PRED_BASE_DIR.'/'.$geo{'StationID'});
 
 for (my $Day=1; $Day<=$DeltaDays; $Day++) {
  my $tshMax=$factDir?min($tshBaseDay+$MAX_PRED_H,$maxFactTSH):$tshBaseDay+$MAX_PRED_H;
  my @tshPred=map { ($_*$STEP_PRED_H)+$tshBaseDay } (0..($tshMax-$tshBaseDay)/$STEP_PRED_H);
  print "tshPred=".join(';',@tshPred)."\n";
  my $curDate=$curYear.sprintf('%02g',$curMonth).sprintf('%02g',$curDay);
  my $srcDir=COOKED_BASE_DIR.'/'.$DATA_ID.'/'.$curDate;
 #==<PRED>
 #===<READ4POINTS>
  print "READ4POINTS_${curDate}\n";
  foreach my $mp (keys %MParLvls) {
   foreach my $lvl ( @{ $MParLvls{$mp} } ) {
    for (my $predH=0; $predH<=$MAX_PRED_H; $predH+=$STEP_PRED_H) {
     my $mpid="${mp}-${lvl}";
     if ($predH eq 0 && index($csvNotInRA,"${mpid},")>=0 ) {
 # Remember: @cell is a GLOBALy-visible list!
      $_->{mpv}->{$mpid}->{0}=$_->{mpv}->{$mpid}->{24} foreach ( @cell );
      next;
     }
     my $csvFile="$srcDir/gfs_4_${curDate}_0000_".sprintf('%03g',$predH)."_${mp}-${lvl}.csv";
     my $e='';     
     if ( ! -f $csvFile ) {
      ($csvFile,$e)=($csvFile.'.gz',':gzip') if -f $csvFile.'.gz';
      die "Sorry, but file $csvFile seems to be not cooked yet :(" unless -f $csvFile;
     }
     open CSV, "<${e}", "$csvFile" or die "Cant open source file: $csvFile";
     chomp ( my @mpv=grep /${rxCell}/,(<CSV>) );
     foreach ( @cell ) {
      my $rx='^'.sprintf('%.02f',$_->{lon}).'0+\s*,\s*'.sprintf('%.02f',$_->{lat});
      $_->{mpv}->{"${mp}-${lvl}"}->{$predH}=[ split /\s*,\s*/,[ grep /${rx}/,@mpv ]->[0] ]->[2];
     } 
     close(CSV);
    }
   }
  }
 #===</READ4POINTS>

 #===<IPOL2POINT>
  print "IPOL2POINT_${curDate}\n"; 
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
    my $tsh=$tshBaseDay+$predH;
    $pred{$lbl}->{$tsh}=$R;
   }
  }
 #===</IPOL2POINT>

 #===<WINDCALC> 
  print "WINDCALC_${curDate}\n";  
  my $tsh=$tshBaseDay;
  foreach (0..$MAX_PRED_H/3) {  
   my ($U,$V)=( $pred{'U10m'}{$tsh}, $pred{'V10m'}{$tsh} );
   my $W=sqrt( $U**2 + $V**2 );
   $pred{'WIND'}{$tsh}=$W;
   my $A=360+(180/pi)*($U>0?-1:1)*acos(-$V/$W); 
   $pred{'WDIR'}{$tsh}=($A>=360?$A-360:$A);  
   $tsh+=$STEP_PRED_H;
  }
 #===</WINDCALC>
 
 #===<DAYTMIMA>
  print "DAYTMIMA_${curDate}\n";   
  foreach my $tshDay ( map { $tshBaseDay+24*$_ } 0..($MAX_PRED_H/24-1) ) {
   foreach ('max','min') {
    $pred{'dayT'.$_}->{$tshDay}=&$_(@{$pred{'T'.$_}}{(map { $tshDay+$_*$STEP_PRED_H } 1..24/$STEP_PRED_H)});
   }
  }
 #===<DAYTMIMA> 
 
 #==</PRED>
 
 #==<SUMAPCP12>
  print "APCP12_${curDate}\n";
  Add_APCP12_To_Pred(\%fact,\%pred) if $factDir;
 #==</SUMAPCP12>
 
 #==<OUTPRED>
  print "OUTPRED_${curDate}\n";
  outPred(\%pred,\@LBLOrder,$tshBaseDay,$predDir,\%geo,\%ViewSettings) unless $factDir;
 #==</OUTPRED>

 #==<DAY2COMP>
  if ($factDir) {
   print "DAY2COMP_${curDate}\n";
   print 'mpidsOut='.join(';',@mpidsOut)."\n";
   foreach my $lbl (@mpidsOut) {
    my ($F,$P,$C,$D)=( $fact{$lbl}, $pred{$lbl}, {}, $diff{$lbl} );
    foreach my $tsh ( grep { $F->{$_} ne undef and $P->{$_} ne undef } @tshPred ) {
     my ($predH,$fv,$pv)=($tsh-$tshBaseDay,$F->{$tsh},$P->{$tsh});
     my ($yy,$mm,$dd,$hh)=tsh2date($tsh);
     my $delta=getFactPreDelta($lbl,$fv,$pv);
     $D->{'e'}->{$predH}+=$delta;
     $D->{'a'}->{$predH}+=abs($delta);
     $C->{$tsh}=[$predH,"${yy}-${mm}-${dd}",$hh,$fv,nearest(0.01,$pv),$delta];
    }
    $diff{$lbl}=$D;
    $comp{$lbl}[$Day-1]=$C;
   }
  }
 #==</DAY2COMP>
  print "END_${curDate}\n";
  $tshBaseDay+=24;
  ($curYear,$curMonth,$curDay)=map { sprintf('%02g',$_) } Add_Delta_Days($curYear,$curMonth,$curDay,1);
 }
 #=</LOOP.Days>

 #=<OUTCMP>
 if ($factDir) {
  foreach my $mp (keys %comp) {
   my $fileOut="${compDir}/${mp}_".($YearMonth || $Start{'Date'}.'-'.$End{'Date'}).'.xls';
   my $wb = Spreadsheet::WriteExcel->new($fileOut) || die "Cant create xls spreadsheet ${fileOut}: ".$!; 
   my $boldStyle=$wb->add_format(bold=>1);
   for (my $Day=1; $Day<=@{$comp{$mp}}; $Day++) {
    my $sheet=$wb->add_worksheet($Day);
    my ($row,$col)=(0,0);  
    $sheet->write($row, $col++, $_) foreach ('PREDH','DATE','+HOURS','FACT','PRED','DELTA');
    my $table=$comp{$mp}[$Day-1];
    foreach my $tsh (sort { $a <=> $b } keys %{$table}) {
     $row+=1; $col=0;
     $sheet->write($row, $col++, $_) foreach @{$table->{$tsh}};
    } # TSH
   } # Days
   my $predH=[ sort {$a<=>$b} keys %{$diff{$mp}{'e'}} ];
   foreach my $et ('e','a') {
    my $sh=$wb->add_worksheet($et);
    $sh->write('A1',[ ['PREDH'],['DELTA'] ],$boldStyle);
    $sh->write('A2', [ $predH, [ map {$_/$DeltaDays} @{$diff{$mp}{$et}}{@{$predH}}] ]);
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
 }
 #=</OUTCMP>
}
#=</LOOP.StationID>
