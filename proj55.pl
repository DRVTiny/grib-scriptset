#!/usr/bin/perl
# .Usage ->
sub doShowUsage {
 print <<EOF;
Usage: proj55.pl [ -f GRIB_FILE | -Y day ] [-s SOURCE_PATH] [-d DEST_PATH]
EOF
 return 0;
}
# .Usage <-


# .opts ->
#use strict;
# .opts <-
# .depend ->
use File::MkTemp;
use File::Path qw(make_path);
use Getopt::Compact;
# .depend <-
# .const ->
use constant MAX_ROW => 470;
use constant MAX_COL => 420;
use constant CSV_DEST_PATH      => '/store/GRIB/cooked/GFS4/NTC-POWER';
use constant GRIB_RAW_PATH      => '/store/GRIB/raw/GFS4/NTC-POWER';
use constant MATRIX_TO_GEO_CSV  => '/usr/local/warehouse/grib/data/rodarea.csv'; 
# .const <-
# sub.read_geopoints ->
sub read_geopoints {
# M2G means Matrix dimensions to Geo(graphical coordinates) array
 local $pthM2G=$_[0];
 local %M2G;
 open(RODAREA,"<$pthM2G");
 while (<RODAREA>) {
  chomp;
  my ($col,$row,$lat,$lon)=split(/;/);
  $lat =~ s/,/./; $lon =~ s/,/./;
  $M2G{"$row,$col"}="$lon,$lat";
 }
 close(RODAREA);
 return \%M2G;
}
# sub.read_geopoints <-
# sub read.grib ->
sub read_grib {
  local ($in_grib,$dpthResultsHere,$m2g)=@_;
  $dpthResultsHere =~ s%/+$%%;
  ( -f $in_grib && -r $in_grib )   || return 0;
  ( $in_grib =~ m%/lfff([0-9]{2})([01][0-9]|2[0-3])[0-9]{4}[ps]$% ) || return 0;
  my $predHours=$1*24+$2;
  return 0 if ! (my @grib_inv=`wgrib -v $in_grib 2>/dev/null`);
  print "Processing GRIB ${in_grib}\n";
  foreach (@grib_inv) {
   chomp; s/:\".+$/:/;
   my $inv_line=$_;
   my @inv=split(/:/);
   my $baseHour=substr($inv[2],length($inv[2])-2,2);
   my $day=substr($inv[2],2,8); 
   make_path("${dpthResultsHere}/${day}") || die "Cant make dest. directory ${dpthResultsHere}/${day}";
   my $mp=$inv[3]; 
   my $lvl=$inv[4]; 
   $lvl =~ s/\s/_/g; $lvl =~ s/\bsfc\b/surface/g; $lvl =~ s/\bgnd\b/ground/g;
   my $csvFile="$dpthResultsHere/$day/gfs_4_${day}_${baseHour}00_" . sprintf('%03g',$predHours) . "_${mp}-${lvl}.csv";
   my $out_csv=mktemp('/tmp/XXXXXXXXXXXXX');
#   my $ret_=`echo "${inv_line}" | wgrib $in_grib -i -text -o $out_csv &>/dev/null`;
   system("echo $inv_line | wgrib $in_grib -i -text -o $out_csv >/dev/null 2>&1") && 
    die "Cant wgrib to CSV\nInventory: ${inv_line}";
   open(CSVFILE,">$csvFile")   || die 'Fuck your self asshole, busted!!!';
   open(METEOVALS,"<$out_csv") || die 'What the hell you doing here?!';
   my $mval=<METEOVALS>;
   for (my $i=1; $i<=MAX_ROW; $i++) {
    for (my $j=1; $j<=MAX_COL; $j++) {
     $mval=<METEOVALS> || die 'Fucking shit happens, so... finita la comedia occured!';
     chomp $mval;
     $m2g->{"$i,$j"} && print CSVFILE $m2g->{"$i,$j"}.",$mval\n";  
    }
   }
   close(METEOVALS);
   close(CSVFILE);
   unlink $out_csv;
  }
}
# sub read.grib <-
# sub.read_unprocessed_gribs ->
sub read_unprocessed_gribs {
  local ($src_pth,$dst_pth,$m2g)=@_;
  print "$src_pth\n";
  ( $src_pth && -d $src_pth ) || return 0;
  print "hello there\n";
  opendir(NTCP,$src_pth);
  foreach (readdir(NTCP)) { 
   if ( m/^[0-9]{10}$/ && -d "${src_pth}/$_" ) {
    my $cur_dir="${src_pth}/$_";
    print "${cur_dir}\n";
    opendir(NTCPD,$cur_dir);
    read_grib("${cur_dir}/$_",$dst_pth,$m2g) foreach (readdir(NTCPD));
   }
  }
}
# sub.read_unprocessed_gribs <-

# .defaults ->
my $rxGribFN='^lfff([0-9]{2})([01][0-9]|2[0-3])[0-9]{4}[ps]$';
my $pthLocalAreaCSV=MATRIX_TO_GEO_CSV;
my $dpthResults=CSV_DEST_PATH;
my $dpthGribs=GRIB_RAW_PATH;
# .defaults <-
# .nodefault ->
my $fpthGrib1;
my $day;
# .nodefault <-
my $ret_ = new Getopt::Compact
 ( name => 'proj55.pl', version => '0.01', modes => [qw(debug)],             
   struct => [
               [ [qw(d dst)], qq(base of destination directory where to place cooked csv-files), '=s', \$dpthResults ],
               [ [qw(s src)], qq(base of source directory from where to get grib1 raw files),    '=s', \$dpthGribs   ],
               [ [qw(Y day)], qq(day to process),                                                '=s', \$day         ],
               [ [qw(f file)],qq(explicitly specify a file to proceed),			         '=s', \$fpthGrib1   ],
               [ [qw(a m2g)], qq(csv file containing matrix to geo array),			 '=s', \$pthLocalAreaCSV ]
             ]
 );


my $opts=$ret_->opts;

my $ARR2GEO=read_geopoints($pthLocalAreaCSV);
if ($day && $fpthGrib1) {
 doShowUsage();
 die 'You cant specify both -Y and -f!'; 
} elsif ($fpthGrib1) {
 read_grib($fpthGrib1,$dpthResults,$ARR2GEO);
} elsif ($day) {
 my $cur_dir="$dpthGribs/$day";
 ( -d $cur_dir ) || die "No such directory ${cur_dir}"; 
 opendir(NTCPD,$cur_dir);
 read_grib("${cur_dir}/$_",$dpthResults,$ARR2GEO) foreach (readdir(NTCPD));
} else {
 read_unprocessed_gribs($dpthGribs,$dpthResults,$ARR2GEO);
}
