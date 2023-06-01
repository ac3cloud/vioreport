#!/usr/bin/perl -w
#
# VIO Plot
#
# data.csv
# time,read kbps,write kbps,read iops,write iops,(day 2),(day 3),...
# timeformat = HH:MM:SS
#
# 2017-02-26 Youzhen Cheng, Youzhen.Cheng@ac3.com.au
#
use Getopt::Long;
use Digest::MD5 qw(md5_hex);
use DateTime;

my $opt_help = 0;
my $opt_verbose = 0;
my $opt_version = 0;
my $debug = 0;
my $config_filename = "sample.report";	# Report config file
my $template_filename = '/etc/vio/area.template';
my $index_filename = '/var/data/tmp/index.txt';
my $cbamap_filename = "/usr/ac3/vir/cba.map";	# Company Business Aapplication Map
my $opt_type = 'iops';
my $opt_chart = 'day';
my $opt_style = 'area';
my $opt_scale = 0;
my $opt_naa = 0;

my @template = ();
my %index = ();
my $time_first = '';
my $time_last = '';
my %config = ();
my %default_config = ();
my %cbamap = ();
my $now = time();
my $readBegin = '';
my $readEnd = '';

my $USAGE = qq{
Usage:
    vio-plot [<options>] file
Options:
    --config file    Report config file (file) [$config_filename]
    --template file  Template file [$template_filename]
    --index    file  Index file [$index_filename]
    --cbamap file    VM CBA map (file) [$cbamap_filename]
    --chart    type  Plot chart (day | week | month )
    --type     type  Plot type (iops | kbps )
    --style    type  Plot style (area | lines | impulses )
    --scale    n     Plot value in log scale (0 | 1)
    --naa      n     Plot performance with naa (0 | 1)
    --verbose        Verbose output
    --help           Display this message.
    --version        Display author and version information.
    --debug    n     Set debug level

};

sub parse_command_line
{
	use Getopt::Long;
	Getopt::Long::config('bundling');
	GetOptions (
		"config=s" => \$config_filename,
		"template=s" => \$template_filename,
		"index=s" => \$index_filename,
		"cbamap=s" => \$cbamap_filename,
		"type=s" => \$opt_type,
		"chart=s" => \$opt_chart,
		"style=s" => \$opt_style,
		"scale=i" => \$opt_scale,
		"naa=i" => \$opt_naa,
		"verbose" => \$opt_verbose,
		"debug=i" => \$debug,
		"help|h" => \$opt_help,
		"version|V" => \$opt_version,
	) or die "$USAGE";

	die "$USAGE" if $opt_help;
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

	if ($debug > 2)
	{
	printf("GetConfig(%s) = [%s]\n", $name, $value);
	}

	return($value);
}

sub GetHashKey($)
{
	local($q) = shift;

	my $k = md5_hex($q);

	return($k);
}

sub set_defaultconfig()
{
	$default_config{'view'} = 'week';	# view type: day week all
	$default_config{'bht'} = 5*900;		# business hours threshold
	$default_config{'aht'} = 5*7200;	# after hours threshold
	$default_config{'scan_start'} = 'all';	# start data point
	$default_config{'scan_end'} = 'all';	# end data point
	$default_config{'view_point'} = 'all';	# view point
}

sub delta_days($$)
{
	my $ds = shift;
	my $de = shift;

	local($y,$m,$d) = split('-',$ds);

	my $dt_s = DateTime->new(
		year => $y,
		month => $m,
		day => $d,
		hour => 0,
		minute => 0,
		second => 0,
		nanosecond => 0,
		time_zone => 'Australia/NSW',
	);

	($y,$m,$d) = split('-',$de);

	my $dt_e = DateTime->new(
		year => $y,
		month => $m,
		day => $d,
		hour => 0,
		minute => 0,
		second => 0,
		nanosecond => 0,
		time_zone => 'Australia/NSW',
	);

	my $delta = int ( 0.5 + ( $dt_e->epoch() - $dt_s->epoch() ) / 86400 );

	return ($delta);
}

sub get_config($)
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

	return($value);
}

sub read_config($)
{
	my $filename = shift;

	open(FH, "<", $filename) || return(1);
	while(<FH>)
	{
		chomp;
		next if ( /^\s*(#|$)/ );

		my($key,$value) = split('\s+=\s+', $_);
		$config{$key}{$value} = $value;
	}
	close(FH);

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

sub scan_data($)
{
	local($filename) = shift;

	open($fh, "<$filename") or return(('2017-03-01 00:00:00', '2017-03-02 00:00:00'));
	while(<$fh>)
	{
		chomp;
		next if (/^(#|\s*$)/);

		my(@a) = split(/,/, $_);

		if ( $time_first eq '' || $a[0] lt $time_first )
		{
			$time_first = $a[0];
		}

		if ( $time_last eq '' || $a[0] gt $time_last )
		{
			$time_last = $a[0];
		}
	}
	close($fh);

	return(($time_first, $time_last));
}

# read index file
sub read_index($)
{
	local($filename) = shift;

	open($fh, "<$filename") or return(1);
	while(<$fh>)
	{
		chomp;
		next if (/^(#|\s*$)/);

		next if ( /^KEY,VM Name,/);

		my($file,$vm,$naa,$tenant,$tier,$size,$qos,$ds,$iops,$qos_t1,$qos_t2,$qos_t3,$other) = split(/,/);

		$index{$file}{'vm'} = $vm;
		$index{$file}{'naa'} = $naa;
		$index{$file}{'tier'} = $tier;
		$index{$file}{'size'} = $size;
		$index{$file}{'qos'} = $qos;
		$index{$file}{'qos_t1'} = $qos_t1;
		$index{$file}{'qos_t2'} = $qos_t2;
		$index{$file}{'qos_t3'} = $qos_t3;
	}
	close($fh);

	return(0);
}

sub read_cbamap($)
{
	my $filename = shift;

	open(FH, "<", $filename) || return(1);
	while(<FH>)
	{
		chomp;
		next if ( /^\s*(#|$)/ );
		my(@a) = split(',', $_);

		$cbamap{$a[0]}{'company'} = $a[1];
		$cbamap{$a[0]}{'business'} = $a[2];
		$cbamap{$a[0]}{'application'} = $a[3];
	}
	close(FH);
}

# read template file
sub read_template($)
{
	local($filename) = shift;

	open($fh, "<$filename") or return(1);
	@template = <$fh>;
	close($fh);

	return(0);
}

sub gnu_text($)
{
	my $s = shift;

	$s =~ s/_/\\\\_/g;

	return($s);
}

# plot_data_with day week and month view
sub plot_data
{
	my $filename = shift;
	local($s) = '';

	my $r_index = 2;
	my $w_index = 3;

	if ( $opt_type =~ /kbps/i )
	{
		$r_index = 4;
		$w_index = 5;
	}

	if ( $opt_style =~ /area/i )
	{
	$s .= sprintf("'%s.csv' using 1:(%d+\$%d):(%d+\$%d+\$%d) notitle with filledcurves",
		$filename, $opt_scale, $r_index, $opt_scale, $r_index, $w_index);
	}
	elsif ( $opt_style =~ /impulses/i )
	{
	$s .= sprintf("'%s.csv' using 1:(%d+\$%d+\$%d) with impulses lt 1",
		$filename, $opt_scale, $r_index, $w_index);
	$s .= ",\\\n";
	$s .= sprintf("'%s.csv' using 1:(%d+\$%d+\$%d) with lines lw 4",
		$filename, $opt_scale, $r_index, $w_index);
	$s .= ",\\\n";
	$s .= sprintf("'%s.csv' using 1:(%d+\$%d) with lines lw 2",
		$filename, $opt_scale, $r_index);
	}
	else
	{
	$s .= sprintf("'%s.csv' using 1:(%d+\$%d+\$%d) notitle with lines lw 2",
		$filename, $opt_scale, $r_index, $w_index);
#	$s .= ",\\\n";
#	$s .= sprintf("'%s.csv' using 1:(%d+\$%d) notitle with lines lw 2",
#		$filename, $opt_scale, $r_index);
	}

	return($s);
}

sub get_xlabel($$$)
{
	my $days = shift;
	my $t0 = shift;
	my $t1 = shift;
	my $r = "( " . $t0;

	if ( $days > 1 )
	{
		$r .= " to ";
		$r .= $t1;
	}

	$r .= " )";

	return($r);
}

sub create_gnuplot($)
{
	my $file = shift;
	my($plot) = '';

	my ($filename) = GetHashKey($file);
	my($type) = lc($opt_type);

	my $vm = '';
	if ( defined($index{$file}{'vm'}) )
	{
		$vm = $index{$file}{'vm'};
	}
	my $vm_name = $vm;
	$vm_name =~ s/ .*$//g;
	if ( $vm_name eq '')
	{
		$vm_name = 'VM';
	}

	my $tier = '';
	if ( defined($index{$file}{'tier'}) )
	{
		$tier = $index{$file}{'tier'};
	}

	my $size = '';
	if ( defined($index{$file}{'size'}) )
	{
		$size = $index{$file}{'size'};
	}

	my $naa = '';
	if ( defined($index{$file}{'naa'}) )
	{
		$naa = $index{$file}{'naa'};
	}

	my $qos_t1 = 1;
	my $lw_t1 = 1;
	if ( defined($index{$file}{'qos_t1'}) )
	{
		$qos_t1 = $index{$file}{'qos_t1'};
		if ( $tier =~ /1/ )
		{
			$lw_t1 = 3;
		}
	}

	if ( $qos_t1 < 1 )
	{
		$qos_t1 = 1;
	}

	my $qos_t2 = 1;
	my $lw_t2 = 1;
	if ( defined($index{$file}{'qos_t2'}) )
	{
		$qos_t2 = $index{$file}{'qos_t2'};
		if ( $tier =~ /2/ )
		{
			$lw_t2 = 3;
		}
	}

	if ( $qos_t2 < 1 )
	{
		$qos_t2 = 1;
	}

	my $qos_t3 = 1;
	my $lw_t3 = 1;
	if ( defined($index{$file}{'qos_t3'}) )
	{
		$qos_t3 = $index{$file}{'qos_t3'};
		if ( $tier =~ /3/ )
		{
			$lw_t3 = 3;
		}
	}

	if ( $qos_t3 < 1 )
	{
		$qos_t3 = 1;
	}

	if ( $opt_naa && $naa eq '' )
	{
		return(0);
	}

	my ($gnu_filename) = $filename . ".gnu";

	open($ofh, ">${gnu_filename}") or return(1);

	foreach (@template)
	{
		chomp;

		next if (/^(#|\s*$)/);

		if ( /^set title / )
		{
			printf $ofh ("set title \"%s\\n%s %dGB on %s\"\n",
				gnu_text($vm), $tier, $size, $naa);
		}
		elsif ( /^set xrange / )
		{
			printf $ofh ("set xrange [ \"%s 00:00:00\" : \"%s 23:59:59\" ] noreverse nowriteback\n",
			$time_first, $time_last);
		}
		elsif ( /^set format x / )
		{
			if ( $opt_chart =~ /day/ )
			{
				printf $ofh ("set format x \"%%H:%%M\"\n");
			}
			elsif ( $opt_chart =~ /week/ )
			{
				printf $ofh ("set format x \"%%a\"\n");
			}
			else
			{
				if ( $x_range < 2 )
				{
				printf $ofh ("set format x \"%%H:%%M\"\n");
				}
				elsif ( $x_range < 8 )
				{
				printf $ofh ("set format x \"%%m-%%d\"\n");
				}
				else
				{
				printf $ofh ("set format x \"%%Y-%%m-%%d\"\n");
				}
			}
		}
		elsif ( /^set yrange / )
		{
			if ( $opt_scale )
			{
				printf $ofh ("set yrange [ 1.00000 : * ] noreverse nowriteback\n");
				printf $ofh ("set logscale y\n");
			}
			else
			{
				printf $ofh ("%s\n", $_);
			}
		}
		elsif ( /^set timefmt / )
		{
			if ( $opt_chart =~ /day/ )
			{
				printf $ofh ("%s\n", $_);
			}
			else
			{
				printf $ofh ("set timefmt \"%%Y-%%m-%%d %%H:%%M:%%S\"\n");
			}
		}
		elsif ( /^set xlabel / )
		{
			if ( $opt_chart =~ /day/ )
				# ( || $opt_chart =~ /week/ )
			{
				printf $ofh ("%s\n", $_);
			}
			else
			{
#				printf $ofh ("set xlabel \"Time %s\"\n", get_xlabel($x_range, $time_first, $time_last));
				printf $ofh ("set xlabel \"Time %s\"\n", get_xlabel($x_range, $readBegin, $readEnd));
			}
		}
		elsif ( /^set ylabel / )
		{
			if ( $opt_scale )
			{
			printf $ofh ("set ylabel \"%s (log scale)\"\n", uc($opt_type));
			}
			else
			{
			printf $ofh ("set ylabel \"%s\"\n", uc($opt_type));
			}
		}
		elsif ( /^set output / )
		{
			printf $ofh ("set output \"%s.png\"\n", $filename);
		}
		elsif ( /^plot / )
		{
			if ( $opt_type eq 'iops')
			{
				printf $ofh ("set arrow from \"%s 00:00:00\",%d to \"%s 23:59:59\",%d nohead front lc rgb \"#ff0000\" lw %d\n",
					$time_first, $qos_t1,
					$time_last, $qos_t1, $lw_t1 );
				printf $ofh ("set arrow from \"%s 00:00:00\",%d to \"%s 23:59:59\",%d nohead front lc rgb \"#00ff00\" lw %d\n",
					$time_first, $qos_t2,
					$time_last, $qos_t2, $lw_t2 );
				printf $ofh ("set arrow from \"%s 00:00:00\",%d to \"%s 23:59:59\",%d nohead front lc rgb \"#0000ff\" lw %d\n",
					$time_first, $qos_t3,
					$time_last, $qos_t3, $lw_t3 );
			}

			printf $ofh ("plot %s\n", plot_data($filename));
		}
		else
		{
			printf $ofh ("%s\n", $_);
		}
	}

	close($ofh);
}


sub do_plot
{
	foreach my $file (sort keys %index)
	{
		my $filename = GetHashKey($file);
		($time_first, $time_last) = scan_data($filename . ".csv");
		$time_first =~ s/ .*$//;
		$time_last =~ s/ .*$//;
		$x_range = delta_days( $time_first, $time_last );

	if ( $debug > 9 )
	{
printf("DO_PLOT %s.csv [%s] [%s]\n", $filename, $time_first, $time_last);
	}
		create_gnuplot($file);
	}
}

#
# main
#
parse_command_line();

set_defaultconfig();
read_config($config_filename);
read_index($index_filename);
read_template($template_filename);
read_cbamap($cbamap_filename);
$readBegin = GetConfig('read_begin');
$readEnd = GetConfig('read_end');
$opt_chart = get_config('view');

if ($debug > 2)
{
	printf("GetConfig(%s) = [%s]\n", 'read_begin', $readBegin);
	printf("GetConfig(%s) = [%s]\n", 'read_end', $readEnd);
}

do_plot();
