#!/usr/bin/perl -w
#
# vio scan
#
# 2017-02-26 Youzhen Cheng, Youzhen.Cheng@ac3.com.au
#
# scan data file - superimpose data to defined view (all, week, day)
#
# view_type = all : all data in readBegin and readEnd time range
# view_type = week : all data map to a week (7x24 hours) with readBegin
# view_type = day : all data map to a day (24 hours) at readBegin
#
# fill in missing zero if required
#
use Getopt::Long;
use Digest::MD5 qw(md5_hex);
use POSIX;
use DateTime;

my $interval = 300;	# data point interval ( 5 minutes )
my $indexFilename = "-";	# index filename
my $naamapFilename = "/var/report/storage/NAA.csv";	# NAA map file
my $vmsmapFilename = "/var/report/vio/vio.vinfo";	# VM Storage map file
my $custmapFilename = "/usr/ac3/etc/customer.csv";	# Customer code map
my $cbamapFilename = "nofile.csv";	# CBA Map file
my $configFilename = "sample.report";	# Report config file
my $outputFilename = "-";	# index filename
my $outdir = ".";	# output directory
my $datadir = ".";	# data file directory
my $fill = 0;		# fill in missing zero
my $utc = 1;		# input is utc
my $view_type = "week";	# view type (all, week, day)
my $action = "scan";	# action (scan, split, analyse, report)
my $debug = 0;		# debug level

my $scanBegin = 'all';	# one day before readBegin
my $scanEnd = 'today';	# one day after readEnd
my $readBegin = 'all';	# time begin ( all )
my $readEnd = 'today';	# time end ( all )
my $viewBegin = '';	# 7th day of the month, or Sunday that week
my $viewEnd = '';	# 7th day of the month, or Saturday that week

my %siotab = ();
my %filetab = ();
my %keytab = ();
my $fields = 0;
my %naamap = ();
my %vmsmap = ();
my %cbamap = ();
my %custmap = ();
my %pricebook = ();
my %config = ();
my %default_config = ();
my $baseday = 0;
my @datafiles = ();
my %idxtab = ();
my %datatab = ();
my $begin_date = 'all';
my $end_date = 'all';
my $now = time();
my %viewStats = (
	'Days' => 7,
	'BusinessDays' => 5,
	'WeekendDays' => 2,
	);

my $USAGE = qq/
Usage:
    vio-scan [<options>] files
Options:
    --action act     Action (scan, split, analyse, report, html) [$action]
    --config file    Report config file (file) [$configFilename]
    --custmap file   Customer code map (file) [$custmapFilename]
    --cbamap file    VM Customer Department map (file) [$cbamapFilename]
    --interval n     Data point interval (seconds) [$interval]
    --begin time     Read data begin time (timestamp) [$readBegin]
    --end   time     Read data end time (timestamp) [$readEnd]
    --utc   n        Input timestamp is UTC [$utc]
    --view  type     View type (all, week, day) [$view_type]
    --index file     Index file (file) [$indexFilename]
    --naamap file    NAA Map file (file) [$naamapFilename]
    --vmsmap file    VM Storage Map file (file) [$vmsmapFilename]
    --outdir dir     Output directory (dir) [$outdir]
    --output file    Output file (file) [$outputFilename]
    --datadir dir    Data file directory (dir) [$datadir]
    --fill  boolen   Fill in missing zero [$fill]
    --debug n        Debug level (0)
/;

sub ParseCommandLine
{
	Getopt::Long::config('bundling');

	GetOptions(
		"action=s" => \$action,
		"config=s" => \$configFilename,
		"interval=n" => \$interval,
		"begin=s" => \$readBegin,
		"end=s" => \$readEnd,
		"custmap=s" => \$custmapFilename,
		"index=s" => \$indexFilename,
		"outdir=s" => \$outdir,
		"datadir=s" => \$datadir,
		"naamap=s" => \$naamapFilename,
		"vmsmap=s" => \$vmsmapFilename,
		"cbamap=s" => \$cbamapFilename,
		"output=s" => \$outputFilename,
		"view=s" => \$view_type,
		"fill=i" => \$fill,
		"utc=i" => \$utc,
#		"library=s" => \@libs,     # array
#		"include=s@" => \$includes, # array reference
#		"rgbcolor=i{3}" => \@color, # multipe values at once
#		"define=s" => \%defines,   # hash
#		"key=s%" => \$keys,   # hash ref
#		"length|height=f" => \$length,   # multiple options
#		"head" => \$head,   # unique short name example
		"debug=n" => \$debug,
	) or die("$USAGE");
}

sub GetTimeMonthDay($$)
{
	my $mDelta = shift;
	my $day = shift;

	my $s = time();

	my $dto = DateTime->from_epoch( epoch => $s );
	$dto->set_time_zone('Australia/NSW');

	if ( $mDelta )
	{
		$dto->add( 'months' => $mDelta );
	}

	$dto->set_day($day);

	return sprintf("%s 00:00:00", $dto->ymd('-'));
}

sub GetTimestamp($)
{
	my $s = shift;

	my $dto = DateTime->from_epoch( epoch => $s );

	$dto->set_time_zone('Australia/NSW');

	return sprintf("%s %s", $dto->ymd('-'), $dto->hms(':'));
}

sub GetYMD($)
{
	my $s = shift;

	my $dto = DateTime->from_epoch( epoch => $s );

	$dto->set_time_zone('Australia/NSW');

	return sprintf("%s", $dto->ymd('-'));
}

sub GetTimeByAlias($)
{
	my $alias = shift;
	my $r = $alias;
	my $ts = sprintf("%s 00:00:00", GetYMD($now));

	if ( $alias =~ /_WeekAgo_/i )
	{
		$r = TimestampAddDay($ts, -7);
	}
	elsif ( $alias =~ /_Yesterday_/i )
	{
		$r = TimestampAddDay($ts, -1);
	}
	elsif ( $alias =~ /_Today_/i )
	{
		$r = $ts;
	}
	elsif ( $alias =~ /_Tomorrow_/i )
	{
		$r = TimestampAddDay($ts, 1);
	}
	elsif ( $alias =~ /_(\d+)DaysAgo_/i )
	{
		my $days = $1;
		$r = TimestampAddDay($ts, -$days);
	}
	elsif ( $alias =~ /_(\d+)LastMonth_/i )
	{
		my $day = $1;
		$r = GetTimeMonthDay(-1, $day)
	}
	elsif ( $alias =~ /_(\d+)ThisMonth_/i )
	{
		my $day = $1;
		$r = GetTimeMonthDay(0, $day)
	}

	return($r);
}

# Work out different hours between two time points
# Business Hours
# Weekday After Hours
# Weekend Hours
sub CalcBusinessHours($$)
{
	my $viewBegin = shift;
	my $viewEnd = shift;

	my $dto = DateTime->from_epoch( epoch => $viewBegin );
	$dto->set_time_zone('Australia/NSW');
	my $dow = $dto->day_of_week;

	my $seconds = $viewEnd - $viewBegin;
	my $totalDays = int( $seconds / 86400);

	my $weeks = POSIX::floor ( $totalDays / 7 );
	my $days = $totalDays - 7 * $weeks;

	# business days within a week
	my $tmpDays = $days + $dow - 1;

	my $weekendDays = 0;

	if ( $days > 0 )
	{
		if ( $dow > 6 )
		{
			$weekendDays = 1;
		}
		elsif ( $tmpDays > 5 )
		{
			$weekendDays = $tmpDays - 5;
		}

		if ( $weekendDays > 2 )
		{
			$weekendDays = 2;
		}
	}

	my $businessDays = $days - $weekendDays;

	$viewStats{'Days'} = $totalDays;
	$viewStats{'BusinessDays'} = 5 * $weeks + $businessDays;
	$viewStats{'WeekendDays'} = $totalDays - $viewStats{'BusinessDays'};

	if ( $debug > 2 )
	{
	printf("days = %s\n", $days);
	printf("viewBegin = %s\n", GetTimestamp($viewBegin));
	printf("viewEnd = %s\n", GetTimestamp($viewEnd));
	printf("weeks = %s, days = %s\n", $weeks, $days);
	printf("dow = %s\n", $dow);
	printf("weekendDays = %s\n", $weekendDays);
	printf("businessDays = %s\n", $businessDays);
	printf("total businessDays = %s\n", 5 * $weeks + $businessDays);
	printf("total Days = %s\n", $totalDays);
	printf("view.Days = %s\n", $viewStats{'Days'});
	printf("view.BusinessDays = %s\n", $viewStats{'BusinessDays'});
	printf("view.WeekendDays = %s\n", $viewStats{'WeekendDays'});
	}
}

sub GetConfig($)
{
	my $name = shift;
	my $value = 0;

	# set to default internal if defined
	if ( defined($default_config{$name}) )
	{
		$value = $default_config{$name};
	}

	# set to user defined value
	if ( defined($config{$name}) )
	{
		foreach my $v (sort keys %{$config{$name}})
		{
			$value = $v;
		}
	}

	if ( $name =~ /_(begin|end)/ && $value =~ /_/ )
	{
		$value = GetTimeByAlias($value);
	}

	return($value);
}

sub SetDefaultConfig()
{
	$default_config{'view'} = 'week';	# view type: day week all
	$default_config{'bht'} = 90;		# business hours threshold per hour
	$default_config{'aht'} = 720;		# after hours threshold per hour
	$default_config{'pricebook'} = "/usr/ac3/etc/pricebook.csv";	# Price Book
}

sub ReadConfig($)
{
	my $filename = shift;

	open(FH, "<", $filename) || return(1);
	my(@lines) = <FH>;
	close(FH);

	foreach (@lines)
	{
		chomp;
		next if ( /^\s*(#|$)/ );

		my($key,$value) = split('\s+=\s+', $_);
		$config{$key}{$value} = $value;
	}

	if ( $debug > 9 )
	{
		foreach my $k (sort keys %config)
		{
			foreach my $v (sort keys %{$config{$k}})
			{
printf("XX [%s=%s]\n", $k, $v);
			}
		}
	}
}

sub ReadPriceBook($)
{
	my $filename = shift;

	open(FH, "<", $filename) || return(1);
	my(@lines) = <FH>;
	close(FH);

	foreach (@lines)
	{
		chomp;
		next if ( /^\s*(#|$)/ );

		my($tier,$price,$dummy) = split(',', $_, 3);
		$pricebook{$tier} = $price;
	}
}

sub ReadCustMap($)
{
	my $filename = shift;

	open(FH, "<", $filename) || return(1);
	my(@lines) = <FH>;
	close(FH);

	foreach (@lines)
	{
		chomp;
		next if ( /^\s*(#|$)/ );
		next if ( /^OLDCODE,NEWCODE,/ );

		my($oldcode,$newcode,$dummy) = split(',', uc($_), 3);
		$custmap{$oldcode} = $newcode;
	}
}

sub ReadNAAMap($)
{
	my $filename = shift;

	open(FH, "<", $filename) || return(1);
	my(@lines) = <FH>;
	close(FH);

	foreach (@lines)
	{
		chomp;
		next if ( /^\s*(#|$)/ );
		next if ( /^KEY,/ );
# '(S2|I1)_AC3_[^_]*(AZ|SHRD|ESX)[^_]*_.*_T[123]\.' 
# NAA,Customer,Tier,Size (GB),Label,Consumed (GB),T1 (GB),T2 (GB),T3 (GB),T4 (GB)
# {NAA} 60002AC0000000000000000000020F1E,AC3,T2,12,HP_AC3_3PAR_INTERNAL_T2.1,12,,12,


		my(@a) = split(',', $_);
		my $naa = $a[0];
		$naa =~ s/^{naa} /naa./i;
		$naa = lc($naa);
		$naamap{$naa}{'customer'} = $a[1];
		$naamap{$naa}{'tier'} = $a[2];
		$naamap{$naa}{'size'} = $a[3];
		$naamap{$naa}{'label'} = $a[4];

		# find tenant
		my $tenant = '';
		if ( $naamap{$naa}{'label'} =~ /^(S2|I1)_AC3_[^_]*(AZ|SH.*D|ESX)[^_]*_.*_T[123]\./  )
		{
			my @b = split('_', $naamap{$naa}{'label'} );
			$tenant = $b[3] || '';
		}
		if ( $tenant eq '' )
		{
			$tenant = $naamap{$naa}{'customer'};
		}
		$naamap{$naa}{'tenant'} = $tenant;
	}
}

sub SecondFromSunday($)
{
	my $ts = shift;
	local(@dt) = split('\s',$ts);
	local($y,$m,$d) = split('-',$dt[0]);
	local($hour,$min,$sec) = split(':',$dt[1]);

	my $dto = DateTime->new(
		year => $y,
		month => $m,
		day => $d,
		hour => $hour,
		minute => $min,
		second => $sec,
		nanosecond => 0,
		time_zone => 'Australia/NSW',
	);

	my $s = $dto->epoch();

	my $dow = $dto->day_of_week();

	if ( $dow > 6 )
	{
		$dow = 0;
	}

	my $r = $sec + 60*$min + 3600*$hour + 86400 * $dow;

	return($r);
}

sub FindSunday($)
{
	my $ts = shift;
	local(@dt) = split('\s',$ts);
	local($y,$m,$d) = split('-',$dt[0]);
	local($hour,$min,$sec) = split(':',$dt[1]);

	while ( $d < 14 )
	{
		$d += 7;
	}

	while ( $d > 21 )
	{
		$d -= 7;
	}

	my $dto = DateTime->new(
		year => $y,
		month => $m,
		day => $d,
		hour => $hour,
		minute => $min,
		second => $sec,
		nanosecond => 0,
		time_zone => 'Australia/NSW',
	);

	my $s = $dto->epoch();

	my $dow = $dto->day_of_week();

	my $r = $s - 86400 * $dow;

	return($r);
}

sub TimestampAddDay($$)
{
	my $ds = shift;
	my $days = shift;

	if ( $ds eq "all" )
	{
		return("all");
	}

	local(@ymd_hms) = split('\s+',$ds);
	local($y,$m,$d) = split('-',$ymd_hms[0]);
	local($hour, $min, $sec) = split(':',$ymd_hms[1]);

	my $dt = DateTime->new(
		year => $y,
		month => $m,
		day => $d,
		hour => $hour,
		minute => $min,
		second => $sec,
		nanosecond => 0,
		time_zone => 'Australia/NSW',
	);

	$dt->add( days => $days );

	return sprintf("%s %s", $dt->ymd('-'), $dt->hms(':'));
}

sub DaysFromSunday($)
{
	my $ts = shift;

	local(@dt) = split('\s',$ts);
	local($y,$m,$d) = split('-',$dt[0]);
	local($hour,$min,$sec) = split(':',$dt[1]);

	my $dto = DateTime->new(
		year => $y,
		month => $m,
		day => $d,
		hour => $hour,
		minute => $min,
		second => $sec,
		nanosecond => 0,
		time_zone => 'Australia/NSW',
	);

	my $dow = $dto->day_of_week();

	if ( $dow > 6 )
	{
		$dow = 0;
	}

	return($dow);
}

# view_type = all : all data in readBegin and readEnd time range
# view_type = week : all data map to a week (7x24 hours) with readBegin
# view_type = day : all data map to a day (24 hours) at readBegin
sub GetTimeKey($$)
{
	local($ts) = shift;
	local($check_range) = shift;

	if ( $ts =~ /T/ )
	{
		$ts =~ s/T/ /;
	}

	if ( $ts =~ /T/ )
	{
		$ts =~ s/Z//;
	}

	local(@d) = split('\s',$ts);
	local(@t) = split(':',$d[1]);
	local($r) = $ts;

	# ignore out of time range data point
	if ( $check_range
		&& ( $ts lt $readBegin || $ts gt $readEnd ) )
	{
		return("#time not in range data");
	}

	if ( $interval > 3600 )
	{
		my $interval_in_hour = int($interval/3600);
		my $hour = $interval_in_hour * int($t[0] / $interval_in_hour);
		$r = sprintf("%s %02d:00:00", $d[0], $hour);
	}
	else
	{
		my $interval_in_minute = int($interval/60);
		my $min = $interval_in_minute * int($t[1] / $interval_in_minute);

		if ( $view_type eq "week" )
		{
			my $days = DaysFromSunday($ts);
			my $ymd = TimestampAddDay(GetTimestamp($viewBegin), $days);
			$ymd =~ s/ .*$//;
			$r = sprintf("%s %02d:%02d:00", $ymd, $t[0], $min);
		}
		elsif ( $view_type eq "day" )
		{
			my $ymd = GetTimestamp($viewBegin);
			$ymd =~ s/ .*$//;
			$r = sprintf("%s %02d:%02d:00", $ymd, $t[0], $min);
		}
		else
		{
			$r = sprintf("%s %02d:%02d:00", $d[0], $t[0], $min);
		}
	}
	if ( $debug > 1 )
	{
printf("t_key (%s) => %s\n", $ts, $r);
	}
	return($r);
}

# create combo key ( primary key / secondary key )
sub GetComboKey($$)
{
	local($vn) = shift;
	local($naa) = shift;

	my $k = $naa . $vn;

	if ( not defined($keytab{$k}{'vn'}) )
	{
		$keytab{$k}{'vn'} = $vn;
		$keytab{$k}{'naa'} = $naa;
	}

	return($k);
}

sub GetHashKey($)
{
	local($q) = shift;

	my $k = md5_hex($q);

	return($k);
}

# STORAGE VM DS NAA vDisk-size
# STORAGE,ac3dc01 (5237dba7-b26b-4ebc-b075-fd6f6526c60e),SHRD-AC3-T2-3PAR7K-L6,naa.60002ac0000000000000007e00007995,91268055040

sub ReadVMSMap($)
{
	my $filename = shift;

	open(FH, "<", $filename) || return(1);
	my(@lines) = <FH>;
	close(FH);

	foreach (@lines)
	{
		chomp;
		next if ( /^\s*(#|$)/ );
		if ( /^STORAGE,/ )
		{
			my(@a) = split(',', $_);
			if ( $a[3] =~ /\s/ )
			{
				my(@b) = split('\s+', $a[3]);

				foreach $naa (@b)
				{
					my $c_key = GetComboKey($a[1], $naa);
					my $size = int (0.5 + $a[4] /1024/1024/1024);
					if ( defined($naamap{$naa}{'size'}) && $size > $naamap{$naa}{'size'} )
					{
						$size = $naamap{$naa}{'size'};
					}
					$vmsmap{$c_key}{'size'} = $size;
					$vmsmap{$c_key}{'datastore'} = $a[2];
				}
			}
			else
			{
			my $c_key = GetComboKey($a[1], $a[3]);
			$vmsmap{$c_key}{'size'} = int (0.5 + $a[4] /1024/1024/1024);
			$vmsmap{$c_key}{'datastore'} = $a[2];
			}
		}
	}
}

sub ReadCBAMap($)
{
	my $filename = shift;

	open(FH, "<", $filename) || return(1);
	my(@lines) = <FH>;
	close(FH);

	foreach (@lines)
	{
		chomp;
		next if ( /^\s*(#|$)/ );
		my(@a) = split(',', $_);

		$cbamap{$a[0]}{'company'} = $a[1];
		$cbamap{$a[0]}{'business'} = $a[2];
		$cbamap{$a[0]}{'application'} = $a[3];
	}
}

# timestamp to seconds
sub TimestampSecond($)
{
	my $ts = shift;

	local(@dt) = split('\s',$ts);
	local($y,$m,$d) = split('-',$dt[0]);
	local($hour,$min,$sec) = split(':',$dt[1]);

	my $dto = DateTime->new(
		year => $y,
		month => $m,
		day => $d,
		hour => $hour,
		minute => $min,
		second => $sec,
		nanosecond => 0,
		time_zone => 'Australia/NSW',
	);

	my $s = $dto->epoch();

	return($s);
}

# check business hour
# Mon - Fri
# 08:00 - 18:00
sub CheckBH($)
{
	my $ts = shift;

	local(@dt) = split('\s+',$ts);
	local($y,$m,$d) = split('-',$dt[0]);
	local($hour,$min,$sec) = split(':',$dt[1]);

	my $dto = DateTime->new(
		year => $y,
		month => $m,
		day => $d,
		hour => $hour,
		minute => $min,
		second => $sec,
		nanosecond => 0,
		time_zone => 'Australia/NSW',
	);

	my $s = $dto->epoch();
	my $dow = $dto->day_of_week();

	my $r = 0;

	if ( $dow > 0 && $dow < 6 && $hour > 7 && $hour < 18 )
	{
		$r = 1;
	}

	return($r);
}

# seconds to t_key
sub SecondTimeKey($)
{
	my $s = shift;

	local(@tm) = localtime($s);

	my $r = sprintf("%04d-%02d-%02d %02d:%02d:%02d",
		1900 + $tm[5],
		1 + $tm[4],
		$tm[3],
		$tm[2],
		$tm[1],
		$tm[0]);

	return(GetTimeKey($r, 0));
}

sub UTC2Local($)
{
	local($ts) = shift;

	$ts =~ s/T/ /;
	$ts =~ s/Z//;

	local(@ymd_hms) = split('\s',$ts);
	local($year, $mon, $day) = split('-',$ymd_hms[0]);
	local($hour, $min, $sec) = split(':',$ymd_hms[1]);

	my $dt = DateTime->new(
		year => $year,
		month => $mon,
		day => $day,
		hour => $hour,
		minute => $min,
		second => $sec,
		nanosecond => 0,
		time_zone => 'UTC',
	);

	$dt->set_time_zone('Australia/NSW');

	my $r = sprintf("%s %s",
		$dt->ymd('-'),
		$dt->hms(':'),
		);

	return($r);
}

sub AddIndex
{
	my ($ts, $vn, $naa, $data) = @_;

	my $t_key = GetTimeKey($ts, 1);

	if ($debug > 9)
	{
		printf STDERR ("DBX: AddIndex = %s %s %s\n", $ts, $vn, $naa);
	}

	return(1) if ( $t_key =~ /^#/ );

	my $c_key = GetComboKey($vn, $naa);
	my $customer = "UNKNOWN";

	if ( defined($naamap{$naa}{'customer'}) )
	{
		$customer = $naamap{$naa}{'customer'};
	}

	my $tenant = "UNKNOWN";

	if ( defined($naamap{$naa}{'tenant'}) )
	{
		$tenant = $naamap{$naa}{'tenant'};
	}

	if ( ! CheckNAA($naa) || ! CheckTenant($tenant) )
	{
		return(2);
	}

	my @a = split(',', $data);

	if ( ! defined($siotab{$c_key}{'data'}) )
	{
		@{$siotab{$c_key}{'data'}} = @a;
		$siotab{$c_key}{'iops'} = $a[0] + $a[1];
		$siotab{$c_key}{'begin_time'} = $ts;
		$siotab{$c_key}{'end_time'} = $ts;
	}
	else
	{
		$fields = 1 + $#a;
		my @b = @{$siotab{$c_key}{'data'}};
		for(my $i = 0; $i < $fields; $i++)
		{
			if ( $a[$i] > $b[$i] )
			{
				$b[$i] = $a[$i];
			}
		}
		@{$siotab{$c_key}{'data'}} = @b;
		$siotab{$c_key}{'iops'} = $b[0] + $b[1];
		if ( $siotab{$c_key}{'begin_time'} gt $ts)
		{
			$siotab{$c_key}{'begin_time'} = $ts;
		}
		if( $siotab{$c_key}{'end_time'} lt $ts)
		{
			$siotab{$c_key}{'end_time'} = $ts;
		}
	}
}

sub AddRecord
{
	my ($ts, $c_key, $data) = @_;

	my $t_key = GetTimeKey($ts, 1);

	if ($debug > 9)
	{
		printf STDERR ("DBX: AddRecord = %s %s\n", $ts, $c_key);
	}

	return(1) if ( $t_key =~ /^#/ );

	my @a = split(',', $data);

	if ( ! defined($siotab{$c_key}{$t_key}{'data'}) )
	{
		@{$siotab{$c_key}{$t_key}{'data'}} = @a;
		$siotab{$c_key}{$t_key}{'iops'} = $a[0] + $a[1];
		$siotab{$c_key}{'begin_time'} = $ts;
		$siotab{$c_key}{'end_time'} = $ts;
	}
	else
	{
		$fields = 1 + $#a;
		my @b = @{$siotab{$c_key}{$t_key}{'data'}};
		for(my $i = 0; $i < $fields; $i++)
		{
			if ( $a[$i] > $b[$i] )
			{
				$b[$i] = $a[$i];
			}
		}
		@{$siotab{$c_key}{$t_key}{'data'}} = @b;
		$siotab{$c_key}{$t_key}{'iops'} = $b[0] + $b[1];
		if ( $siotab{$c_key}{'begin_time'} gt $ts)
		{
			$siotab{$c_key}{'begin_time'} = $ts;
		}
		if( $siotab{$c_key}{'end_time'} lt $ts)
		{
			$siotab{$c_key}{'end_time'} = $ts;
		}
	}
}

# check date (readBegin -2, readEnd + 2)
sub CheckDate($)
{
	my($ds) = shift;

	if ( $scanBegin eq "all" )
	{
		return(1);
	}

	$ds =~ s/-//g;

	if ( $ds > $scanBegin && $ds < $scanEnd )
	{
		return(1);
	}

	return(0);
}

sub GetDataFiles()
{
	opendir(my $dh, $datadir) || return(1);

	while(my $file = readdir($dh))
	{
		if ( $file =~ /^(|[SGI][12]\-\S+\-)(\d{8}|\d{4}\-\d{2}\-\d{2})\.csv/ )
                {
#                        my $k = $1;
                        my $dt = $2;
			if ( CheckDate($dt) )
			{
	                        push(@datafiles, $file);
				if ( $debug )
				{
                        printf("<< %s file %s\n", $dt, $file);
                        	}
			}
                }
	}

	closedir $dh;

	if ($debug > 9)
	{
		foreach my $file (sort @datafiles)
		{
			printf STDERR ("DBX: date file = %s\n", $file);
		}
	}
}

sub ScanIndex($)
{
	my $filename = shift;

	if ($debug > 9)
	{
		printf STDERR ("DBX: scanindex = %s\n", $filename);
	}

	open(FH, "<", $filename) || return(1);
	my (@lines) = <FH>;
	close(FH);

	foreach (@lines)
	{
		chomp;
		next if (/^(#|\s*$)/);
		next if (/^[[:alpha:]]/);

		my($ts,$vn,$naa,$data) = split(/,/, $_, 4);

		if ( $utc )
		{
			$ts = UTC2Local($ts);
		}

		AddIndex($ts,$vn,$naa,$data);
	}
}

sub MakeIndex()
{
	local($c_key);


	foreach $c_key (sort keys %siotab)
	{
		my $naa = lc($keytab{$c_key}{'naa'});
		my $tenant = 'UNKNOWN';
		my $tier = 'T1';
		my $size = 1;
		my $datastore = 'Unknown_Label';
		if ( defined($naamap{$naa}{'tenant'}) )
		{
			$tenant = $naamap{$naa}{'tenant'};
		}
		if ( defined($naamap{$naa}{'tier'}) )
		{
			$tier = $naamap{$naa}{'tier'};
		}
		if ( defined($vmsmap{$c_key}{'size'}) )
		{
			$size = $vmsmap{$c_key}{'size'};
		}
		if ( defined($vmsmap{$c_key}{'datastore'}) )
		{
			$datastore = $vmsmap{$c_key}{'datastore'};
		}
		my $qos = $size;
		if ( $tier =~ /2/ )
		{
			$qos = 0.5 * $size;
		}
		elsif ( $tier =~ /3/ )
		{
			$qos = 0.25 * $size;
		}
		$idxtab{$c_key}{'vn'} = $keytab{$c_key}{'vn'};
		$idxtab{$c_key}{'naa'} = $keytab{$c_key}{'naa'};
		$idxtab{$c_key}{'tenant'} = $tenant;
		$idxtab{$c_key}{'tier'} = $tier;
		$idxtab{$c_key}{'size'} = $size;
		$idxtab{$c_key}{'qos'} = $qos;
		$idxtab{$c_key}{'datastore'} = $datastore;
		$idxtab{$c_key}{'iops'} = $siotab{$c_key}{'iops'};
		$idxtab{$c_key}{'qos_t1'} = $size;
		$idxtab{$c_key}{'qos_t2'} = 0.5*$size;
		$idxtab{$c_key}{'qos_t3'} = 0.25*$size;
		$idxtab{$c_key}{'bh_t1'} = 0;
		$idxtab{$c_key}{'bh_t2'} = 0;
		$idxtab{$c_key}{'bh_t3'} = 0;
		$idxtab{$c_key}{'ah_t1'} = 0;
		$idxtab{$c_key}{'ah_t2'} = 0;
		$idxtab{$c_key}{'ah_t3'} = 0;
		$idxtab{$c_key}{'recommend'} = "NA";
		$idxtab{$c_key}{'begin_time'} = $siotab{$c_key}{'begin_time'};
		$idxtab{$c_key}{'end_time'} = $siotab{$c_key}{'end_time'};

		if ($debug > 9)
		{
		printf STDERR ("%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n",
			$c_key,
			$idxtab{$c_key}{'vn'},
			$idxtab{$c_key}{'naa'},
			$idxtab{$c_key}{'tenant'},
			$idxtab{$c_key}{'tier'},
			$idxtab{$c_key}{'size'},
			$idxtab{$c_key}{'qos'},
			$idxtab{$c_key}{'datastore'},
			$idxtab{$c_key}{'iops'},
			$idxtab{$c_key}{'qos_t1'},
			$idxtab{$c_key}{'qos_t2'},
			$idxtab{$c_key}{'qos_t3'},
			$interval*$idxtab{$c_key}{'bh_t1'},
			$interval*$idxtab{$c_key}{'bh_t2'},
			$interval*$idxtab{$c_key}{'bh_t3'},
			$interval*$idxtab{$c_key}{'ah_t1'},
			$interval*$idxtab{$c_key}{'ah_t2'},
			$interval*$idxtab{$c_key}{'ah_t3'},
			);
		}
	}
}

sub ReadData($)
{
	my $filename = shift;
	open(FH, "<", $filename) || return(1);
	my(@lines) = <FH>;
	close(FH);

	foreach (@lines)
	{
		chomp;
		my(@a) = split(',', $_);
		my $ts = $a[0];
		$datatab{$ts}{'iops'} = $a[1] + $a[2];
	}
}

sub AnalyseVMS
{
	foreach my $c_key (sort keys %idxtab)
	{
		my $filename = GetHashKey($c_key) . ".csv";

		%datatab = ();
		ReadData($filename);

	foreach my $t_key (sort keys %datatab )
	{
		my $is_business_hour = CheckBH($t_key);
		my $iops = $datatab{$t_key}{'iops'};

		if ( $iops >= $idxtab{$c_key}{'qos_t1'})
		{
			if ( $is_business_hour )
			{
				$idxtab{$c_key}{'bh_t1'}++;
			}
			else
			{
				$idxtab{$c_key}{'ah_t1'}++;
			}
		}
		if ( $iops >= $idxtab{$c_key}{'qos_t2'})
		{
			if ( $is_business_hour )
			{
				$idxtab{$c_key}{'bh_t2'}++;
			}
			else
			{
				$idxtab{$c_key}{'ah_t2'}++;
			}
		}
		if ( $iops >= $idxtab{$c_key}{'qos_t3'})
		{
			if ( $is_business_hour )
			{
				$idxtab{$c_key}{'bh_t3'}++;
			}
			else
			{
				$idxtab{$c_key}{'ah_t3'}++;
			}
		}
	}
	}
}

sub AnalyseTime
{
	my $bh_threshold = 10 * $viewStats{'BusinessDays'} * GetConfig('bht');
	my $ah_threshold = 10 * $viewStats{'BusinessDays'} * GetConfig('aht')
		+ 24 * $viewStats{'WeekendDays'} * GetConfig('aht');

	foreach my $c_key (sort keys %idxtab)
	{
		my $tier = -1;
		my $msg = '';

		# BH T0
		if ( $tier < 0
			&& $bh_threshold > 0
			&& $interval*$idxtab{$c_key}{'bh_t1'} >= $bh_threshold )
		{
			$tier = 1;
			$msg = sprintf("BH: %s >= %s over T1 QOS",
				$interval*$idxtab{$c_key}{'bh_t1'}, $bh_threshold);
		}

		# AH T0
		if ( $tier < 0
			&& $ah_threshold > 0
			&& $interval*$idxtab{$c_key}{'ah_t1'} >= $ah_threshold )
		{
			$tier = 1;
			$msg = sprintf("AH: %s >= %s over T1 QOS",
				$interval*$idxtab{$c_key}{'ah_t1'}, $ah_threshold);
		}

		# BH T1
		if ( $tier < 0
			&& $bh_threshold > 0
			&& $interval*$idxtab{$c_key}{'bh_t2'} >= $bh_threshold )
		{
			$tier = 1;
			$msg = sprintf("BH: %s >= %s over T2 QOS",
				$interval*$idxtab{$c_key}{'bh_t2'}, $bh_threshold);
		}

		# AH T1
		if ( $tier < 0
			&& $ah_threshold > 0
			&& $interval*$idxtab{$c_key}{'ah_t2'} >= $ah_threshold )
		{
			$tier = 1;
			$msg = sprintf("AH: %s >= %s over T2 QOS",
				$interval*$idxtab{$c_key}{'ah_t2'}, $ah_threshold);
		}

		# BH T2
		if ( $tier < 0
			&& $bh_threshold > 0
			&& $interval*$idxtab{$c_key}{'bh_t3'} >= $bh_threshold )
		{
			$tier = 2;
			$msg = sprintf("BH: %s >= %s over T3 QOS",
				$interval*$idxtab{$c_key}{'bh_t3'}, $bh_threshold);
		}

		# AH T2
		if ( $tier < 0
			&& $ah_threshold > 0
			&& $interval*$idxtab{$c_key}{'ah_t3'} >= $ah_threshold )
		{
			$tier = 2;
			$msg = sprintf("AH: %s >= %s over T3 QOS",
				$interval*$idxtab{$c_key}{'ah_t3'}, $ah_threshold);
		}

		# T3
		if ( $tier < 0
			&& $bh_threshold > 0
			&& $ah_threshold > 0
			&& $interval*$idxtab{$c_key}{'bh_t3'} < $bh_threshold
			&& $interval*$idxtab{$c_key}{'ah_t3'} < $ah_threshold )
		{
			$tier = 3;
			$msg = sprintf("BH: %s < %s below T3 QOS",
				$interval*$idxtab{$c_key}{'bh_t3'}, $bh_threshold);
			$msg .= sprintf(" AND AH: %s < %s below T3 QOS",
				$interval*$idxtab{$c_key}{'ah_t3'}, $ah_threshold);
		}

		my $current_tier = $idxtab{$c_key}{'tier'};
		$current_tier =~ s/T//;

		$idxtab{$c_key}{'target_tier'} = sprintf("T%d", $tier);
		$idxtab{$c_key}{'reason'} = $msg;

		if ( $tier < 0 )
		{
			$idxtab{$c_key}{'recommend'} = "No recommendation";
			$idxtab{$c_key}{'target_tier'} = $idxtab{$c_key}{'tier'};
			$idxtab{$c_key}{'reason'} = "Default config";
		}
		elsif ( $current_tier == $tier )
		{
			$idxtab{$c_key}{'recommend'} = "No Change";
		}
		elsif ( $current_tier > $tier )
		{
			$idxtab{$c_key}{'recommend'} = "Upgrade";
		}
		elsif ( $current_tier < $tier )
		{
			$idxtab{$c_key}{'recommend'} = "Downgrade";
		}

		my $cost = $idxtab{$c_key}{'size'} * $pricebook{$idxtab{$c_key}{'tier'}};
		my $new_cost = $idxtab{$c_key}{'size'} * $pricebook{$idxtab{$c_key}{'target_tier'}};
		$idxtab{$c_key}{'cost'} = $cost;
		$idxtab{$c_key}{'new_cost'} = $new_cost;
	}
}

sub AnalyseHTML
{
	foreach my $c_key (sort keys %idxtab)
	{
		my $filename = GetHashKey($c_key) . ".png";
		$idxtab{$c_key}{'chart'} = "nodata.png";
		if ( -f "${filename}" )
		{
			$idxtab{$c_key}{'chart'} = "${filename}";
		}
	}
}

sub ReadDataFiles($)
{
	my $filename = shift;

	open(FH, "<", $filename) || return(0);
	my(@lines) = <FH>;
	close(FH);

	foreach (@lines)
	{
		chomp;
		push(@datafiles, $_);
	}
}

sub OutputDataFiles($)
{
	my $filename = shift;

	open($fh, ">", $filename) || return(0);

	foreach my $file (sort @datafiles)
	{
		printf $fh ("%s\n", $datadir . "/" . $file);
	}

	close($fh);
}

sub OutputIndex($)
{
	my $filename = shift;
	open(FH, ">", $filename) || return(1);

	printf FH ("%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n",
		"KEY",
		"VM Name",
		"LUN",
		"Customer",
		"Storage Tier",
		"Size(GB)",
		"QOS(IOPS)",
		"Datastore",
		"IOPS(Max)",
		"QOS T1",
		"QOS T2",
		"QOS T3",
		"Over T1(BH)",
		"Over T2(BH)",
		"Over T3(BH)",
		"Over T1(AH)",
		"Over T2(AH)",
		"Over T3(AH)",
		"Recommendation",
		"Tier(Proposed)",
		"Comment",
		"Cost(Existing)",
		"Cost(Proposed)",
		"First_sighted",
		"Last_sighted",
		"Company",
		"Business",
		"Application",
	);

	foreach $c_key (sort keys %idxtab)
	{
		my $recommend = "NA";
		my $target_tier = -1;
		my $reason = "NA";
		my $cost = 0;
		my $new_cost = 0;
		my $company = $idxtab{$c_key}{'tenant'};
		my $business = 'TBA';
		my $application = 'NA';
		if ( defined( $idxtab{$c_key}{'recommend'}) )
		{
			$recommend = $idxtab{$c_key}{'recommend'};
		}
		if ( defined( $idxtab{$c_key}{'target_tier'}) )
		{
			$target_tier = $idxtab{$c_key}{'target_tier'};
		}
		if ( defined($idxtab{$c_key}{'reason'}) )
		{
			$reason = $idxtab{$c_key}{'reason'};
		}
		if ( defined($idxtab{$c_key}{'cost'}) )
		{
			$cost = $idxtab{$c_key}{'cost'};
		}
		if ( defined($idxtab{$c_key}{'new_cost'}) )
		{
			$new_cost = $idxtab{$c_key}{'new_cost'};
		}
		if ( defined($cbamap{$idxtab{$c_key}{'vn'}}{'company'}) )
		{
			$company = $cbamap{$idxtab{$c_key}{'vn'}}{'company'};
		}
		if ( defined($cbamap{$idxtab{$c_key}{'vn'}}{'business'}) )
		{
			$business = $cbamap{$idxtab{$c_key}{'vn'}}{'business'};
		}
		if ( defined($cbamap{$idxtab{$c_key}{'vn'}}{'application'}) )
		{
			$application = $cbamap{$idxtab{$c_key}{'vn'}}{'application'};
		}
		printf FH ("%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n",
			$c_key,
			$idxtab{$c_key}{'vn'},
			$idxtab{$c_key}{'naa'},
			$idxtab{$c_key}{'tenant'},
			$idxtab{$c_key}{'tier'},
			$idxtab{$c_key}{'size'},
			$idxtab{$c_key}{'qos'},
			$idxtab{$c_key}{'datastore'},
			$idxtab{$c_key}{'iops'},
			$idxtab{$c_key}{'qos_t1'},
			$idxtab{$c_key}{'qos_t2'},
			$idxtab{$c_key}{'qos_t3'},
			$interval*$idxtab{$c_key}{'bh_t1'},
			$interval*$idxtab{$c_key}{'bh_t2'},
			$interval*$idxtab{$c_key}{'bh_t3'},
			$interval*$idxtab{$c_key}{'ah_t1'},
			$interval*$idxtab{$c_key}{'ah_t2'},
			$interval*$idxtab{$c_key}{'ah_t3'},
			$recommend,
			$target_tier,
			$reason,
			$cost,
			$new_cost,
			$idxtab{$c_key}{'begin_time'},
			$idxtab{$c_key}{'end_time'},
			$company,
			$business,
			$application,
			);
	}
	close(FH);
}

sub ReadIndex($)
{
	my $filename = shift;

	open(FH, "<", $filename) || return(1);
	my(@lines) = <FH>;
	close(FH);

	foreach (@lines)
	{
		chomp;
		my(@a) = split(',', $_);
		my $idx = 0;
		my $c_key = $a[$idx++];
		next if ( $c_key eq 'KEY' );

		if ( $action eq "split"
			&& ( ! CheckNAA($a[2]) || ! CheckTenant($a[3]) )
		)
		{
			next;
		}
		$idxtab{$c_key}{'vn'} = $a[$idx++];
		$idxtab{$c_key}{'naa'} = $a[$idx++];
		$idxtab{$c_key}{'tenant'} = $a[$idx++];
		$idxtab{$c_key}{'tier'} = $a[$idx++];
		$idxtab{$c_key}{'size'} = $a[$idx++];
		$idxtab{$c_key}{'qos'} = $a[$idx++];
		$idxtab{$c_key}{'datastore'} = $a[$idx++];
		$idxtab{$c_key}{'iops'} = $a[$idx++];
		$idxtab{$c_key}{'qos_t1'} = $a[$idx++];
		$idxtab{$c_key}{'qos_t2'} = $a[$idx++];
		$idxtab{$c_key}{'qos_t3'} = $a[$idx++];
		$idxtab{$c_key}{'bh_t1'} = int($a[$idx++]/$interval);
		$idxtab{$c_key}{'bh_t2'} = int($a[$idx++]/$interval);
		$idxtab{$c_key}{'bh_t3'} = int($a[$idx++]/$interval);
		$idxtab{$c_key}{'ah_t1'} = int($a[$idx++]/$interval);
		$idxtab{$c_key}{'ah_t2'} = int($a[$idx++]/$interval);
		$idxtab{$c_key}{'ah_t3'} = int($a[$idx++]/$interval);
		$idxtab{$c_key}{'recommend'} = $a[$idx++];
		$idxtab{$c_key}{'target'} = $a[$idx++];
		$idxtab{$c_key}{'reason'} = $a[$idx++];
		$idxtab{$c_key}{'cost'} = $a[$idx++];
		$idxtab{$c_key}{'cost_new'} = $a[$idx++];
		$idxtab{$c_key}{'begin_time'} = $a[$idx++];
		$idxtab{$c_key}{'end_time'} = $a[$idx++];
		$idxtab{$c_key}{'company'} = $a[$idx++];
		$idxtab{$c_key}{'business'} = $a[$idx++];
		$idxtab{$c_key}{'application'} = $a[$idx++];
	}
}

#################################################

# optional naa check
sub CheckNAA($)
{
	my($naa) = shift;
	my $naa_not_required = 1;

	foreach my $k (sort keys %config)
	{
		foreach my $v (sort keys %{$config{$k}})
		{
			if ( $k eq 'naa' )
			{
				$naa_not_required = 0;
				if ( defined($naa) && $naa =~ /$v/i )
				{
					return(1);
				}
			}
		}
	}

	return($naa_not_required);
}

# optional tenant check
sub CheckTenant($)
{
	my($tenant) = shift;
	my $tenant_check_not_required = 1;

	foreach my $k (sort keys %config)
	{
		foreach my $v (sort keys %{$config{$k}})
		{
			if ( $k eq 'tenant' )
			{
				$tenant_check_not_required = 0;
				if ( defined($tenant) && $tenant =~ /${v}/ )
				{
					return(1);
				}
			}
			elsif ( $k eq 'customer' )
			{
				$tenant_check_not_required = 0;
				if ( defined($tenant) && $tenant eq $v )
				{
					return(1);
				}
			}
		}
	}

	return($tenant_check_not_required);
}

sub SplitAddRecord
{
	my ($ts, $c_key, $data) = @_;

	my $t_key = GetTimeKey($ts, 1);

	return(2) if ( $t_key =~ /^#/ );

	my @a = split(',', $data);

	if ( ! defined($siotab{$c_key}{$t_key}{'data'}) )
	{
		@{$siotab{$c_key}{$t_key}{'data'}} = @a;
	}
	else
	{
		$fields = 1 + $#a;
		my @b = @{$siotab{$c_key}{$t_key}{'data'}};
		for(my $i = 0; $i < $fields; $i++)
		{
			if ( $a[$i] > $b[$i] )
			{
				$b[$i] = $a[$i];
			}
		}
		@{$siotab{$c_key}{$t_key}{'data'}} = @b;
	}
}

sub ScanFile($)
{
	my $filename = shift;

	if ( $debug > 9)
	{
		printf("split scanfile %s\n", $filename);
	}

	open(FH, "<", $filename) || return(1);
	my(@lines) = <FH>;
	close(FH);

	if ( $debug > 9)
	{
		printf("scanfile opened %s\n", $filename);
	}
	foreach (@lines)
	{
		chomp;
		next if (/^(#|\s*$)/);
		next if (/^[[:alpha:]]/);

		my($ts,$vn,$naa,$data) = split(/,/, $_, 4);
		my $c_key = GetComboKey($vn, $naa);

		if ( defined($idxtab{$c_key}) )
		{
			if ( $utc )
			{
				$ts = UTC2Local($ts);
			}

			SplitAddRecord($ts,$c_key,$data);
		}
	}
}

sub SplitFiles()
{
	foreach my $file (sort @datafiles)
	{
		ScanFile($file);
	}
}

sub SplitMakeFile
{
	my $param = shift;

	my $filename = $param->{'filename'} || '-';
	my $vn = $param->{'vn'};
	my $naa = $param->{'naa'};
	my $data = $param->{'data'};
	my $myFilename = $param->{'filename'} . ".csv";
	if ( $outdir ne "." )
	{
		$myFilename = $outdir . "/" . $param->{'filename'} . ".csv";
	}

	open(FH, ">", $myFilename) || return(1);

	# output as it is
	if ( $readBegin eq "all" || $fill == 00 )
	{
		foreach my $t_key (sort keys %{$data} )
		{
			printf FH ("%s", $t_key);
			foreach $v (@{$data->{$t_key}{'data'}})
			{
				printf FH (",%s", $v);
			}
			printf FH ("\n");
		}
	}
	# output with filled zero
	else
	{
		for(my $t = $viewBegin; $t < $viewEnd; $t += $interval)
		{
			$t_key = SecondTimeKey($t);
			next if ( $t_key =~ /^#/ );
			printf FH ("%s", $t_key);
			if ( defined($data->{$t_key}) )
			{
				foreach $v (@{$data->{$t_key}{'data'}})
				{
					printf FH (",%s", $v);
				}
			}
			else
			{
				for(my $i = 0; $i < $fields; $i++)
				{
					printf FH (",0");
				}
			}
			printf FH ("\n");
		}
	}

	close(FH);
}

sub SplitOutput()
{
	local($c_key);

	foreach $c_key (sort keys %siotab)
	{
		SplitMakeFile({'filename' => GetHashKey($c_key),
			'data' => $siotab{$c_key},
			'vn' => $keytab{$c_key}{'vn'},
			'naa' => $keytab{$c_key}{'naa'},
			});
	}
}

sub OutputHTML($)
{
	my $filename = shift;
	open(FH, ">", $filename) || return(1);
	foreach $c_key (sort keys %idxtab)
	{
		if ( $idxtab{$c_key}{'chart'} ne "nodata.png" )
		{
			my $file = GetHashKey($c_key);
		printf FH ("<table>\n");
		printf FH ("<tr>\n");
		printf FH ("<td>VM Name</td>\n");
		printf FH ("<td>%s</td>\n",
			$idxtab{$c_key}{'vn'});
		printf FH ("</tr>\n");

		printf FH ("<tr>\n");
		printf FH ("<td>LUN</td>\n");
		printf FH ("<td>%s</td>\n",
			$idxtab{$c_key}{'naa'});
		printf FH ("</tr>\n");

		printf FH ("<tr>\n");
		printf FH ("<td>Tier</td>\n");
		printf FH ("<td>%s</td>\n",
			$idxtab{$c_key}{'tier'});
		printf FH ("</tr>\n");

		printf FH ("<tr>\n");
		printf FH ("<td>Size</td>\n");
		printf FH ("<td>%s</td>\n",
			$idxtab{$c_key}{'size'});
		printf FH ("</tr>\n");
		printf FH ("</table>\n");
		printf FH ("<br>\n");
		printf FH ("<img src=\"%s.png\">\n", $file);
		}
	}
	close(FH);
}

#
# main
#
ParseCommandLine();

SetDefaultConfig();
ReadConfig($configFilename);
ReadCustMap($custmapFilename);
ReadNAAMap($naamapFilename);

my $pricebookFilename = GetConfig('pricebook');
ReadPriceBook($pricebookFilename);

if ( ! -f $cbamapFilename )
{
	$cbamapFilename = GetConfig('cbamap');
}
$datadir = GetConfig('datadir');
$vmsmapFilename = GetConfig('vmsmap');

ReadVMSMap($vmsmapFilename);

ReadCBAMap($cbamapFilename);
$view_type = GetConfig('view');

if ( $debug )
{
printf("DBX %s 0\n", $action);
printf("read (%s,%s)\n", $readBegin, $readEnd);
}

if ( $readBegin eq 'all' )
{
	$readBegin = GetConfig('read_begin');
}

if ( $readEnd eq 'today' || $readEnd eq 'all' )
{
	$readEnd = GetConfig('read_end');
}

if ( $debug )
{
printf("DBX %s 1\n", $action);
printf("read (%s,%s)\n", $readBegin, $readEnd);
}

if ( $view_type eq "week" )
{
	$viewBegin = FindSunday($readBegin);
	$viewEnd = TimestampSecond(
		TimestampAddDay(GetTimestamp($viewBegin), 7)
		);
}
elsif ( $view_type eq "day" )
{
	$viewBegin = TimestampSecond($readBegin);
	$viewEnd = TimestampSecond(
		TimestampAddDay(GetTimestamp($viewBegin), 1)
		);
}
else
{
	$viewBegin = TimestampSecond($readBegin);
	$viewEnd = TimestampSecond($readEnd);
}

if ( $action eq "scan"
	|| $action eq "split"
	|| $action eq "analyse"
)
{
	$scanBegin = TimestampAddDay($readBegin, -1);
	$scanBegin =~ s/ .*//;
	$scanBegin =~ s/\-//g;
	$scanEnd = TimestampAddDay($readEnd, +1);
	$scanEnd =~ s/ .*//;
	$scanEnd =~ s/\-//g;
}


if ( $debug )
{
printf("DBX %s 2\n", $action);
printf("scan (%s,%s)\n", $scanBegin, $scanEnd);
printf("read (%s,%s)\n", $readBegin, $readEnd);
printf("view (%s,%s) [%s,%s]\n",
	GetTimestamp($viewBegin), GetTimestamp($viewEnd),
	$viewBegin, $viewEnd);
printf("vmsmap (%s)\n", $vmsmapFilename);
printf("datadir (%s)\n", $datadir);
}

if ( $action eq "scan" )
{
	GetDataFiles();
	OutputDataFiles($outputFilename . ".filelist");

	foreach my $file (sort @datafiles)
	{
		ScanIndex($datadir . "/" . $file);
	}

	# scan for index
	MakeIndex();

	# create index file
	OutputIndex($outputFilename);
}
elsif ( $action eq "split" )
{
	ReadIndex($indexFilename);
	ReadDataFiles($indexFilename . ".filelist");
	SplitFiles();
	SplitOutput();
	OutputIndex($outputFilename);
}
elsif ( $action eq "analyse" )
{
	ReadIndex($indexFilename);

	# analyse individual vm+naa
	AnalyseVMS();

	# create index file
	OutputIndex($outputFilename);
}
elsif ( $action eq "report" )
{
	ReadIndex($indexFilename);

	# analyse individual vm+naa
	AnalyseTime();

	# create index file
	OutputIndex($outputFilename);
}
elsif ( $action eq "html" )
{
	ReadIndex($indexFilename);

	# analyse individual vm+naa
	AnalyseHTML();

	# create index file
	OutputHTML($outputFilename);
}
