#!/usr/bin/perl
#
# quick runsheet
#
# 2015-12-20 Youzhen Cheng, Youzhen.Cheng@ac3.com.au
#
# activity,activity name
# task,task name,description,duration,start time,end time,owner
# task,task name,description,duration,start time,end time,owner
# milestone
# activity,activity name
# task,task name,description,duration,start time,end time,owner
# task,task name,description,duration,start time,end time,owner
# milestone
#
use JSON;
use Data::Dumper;
use Getopt::Long;
use Time::Local;
use POSIX;
use POSIX::strptime;

use vars qw(
	$opt_input
	$opt_output
	$opt_fmt
	$opt_verbose
	$opt_debug
	$opt_help
	$opt_version
	);

sub read_file($);
$opt_debug = 0;
$opt_fmt = 'vir';
$timestamp = ();

my $USAGE = qq/
Usage:
    qrunsheet [<options>]
Options:
    --input file            Input file
    --output file           Output file
    --fmt format            Input file format (vcd | vir)
    --verbose               Verbose output
    --help                  Display this message.
    --version               Display author and version information.
    --debug=N               Set debug level

/;

sub parse_command_line
{
	use Getopt::Long;
	Getopt::Long::config('bundling');
	GetOptions (
		"input|i=s" => \$opt_input,
		"output|o=s" => \$opt_output,
		"fmt|f=s" => \$opt_fmt,
		"verbose" => \$opt_verbose,
		"debug=i" => \$opt_debug,
		"help|h" => \$opt_help,
		"version|V" => \$opt_version,
	) or die "$USAGE";

	die "$USAGE" if $opt_help;
}

sub read_file($)
{
	my $filename = shift;

	open(FH, "<$filename") || return(0);
	my @_lines = <FH>;
	close(FH);

	my @lines = ();
	foreach my $line (@_lines)
	{
		chomp($line);
		if ( $line =~ /^include,(\S+)/ )
		{
			$line =~ s/^include,//;
			$line =~ s/^['"\s]*//g;
			$line =~ s/['"\s]$//g;
			my @b = read_file($line);
			push(@lines, @b);
		}
		else
		{
			push(@lines, ($line));
		}
	}
	return(@lines);
}

sub time_epoch($)
{
	my($s) = shift;

	my($mday, $mon, $year, $hour, $min, $sec)
		= ( POSIX::strptime($s, '%Y-%m-%d %H:%M:%S') )[3,4,5,2,1,0];

	my($ts) = mktime($sec, $min, $hour, $mday, $mon, $year);

	return($ts);
}

sub get_duration($)
{
	my($s) = shift;

	my(@a) = split(':', $s);

	$ts = 60 * ( 60 * $a[0] + $a[1]);

	return($ts);
}

sub get_nextday($$)
{
	my($t) = shift;
	my($d) = shift;
	my(@tm) = localtime($t);

	my($mday, $mon, $year);

	$mday = $tm[3];
	$mon = $tm[4];
	$year = $tm[5];

	my($ts) = mktime(0, 0, 0, $mday, $mon, $year);
	my($s) = $d * 86400;

	my($r) = $ts + $s;

	return($r);
}

sub get_nextworkday($$)
{
	my($t) = shift;
	my($d) = shift;
	my(@tm) = localtime($t);

	my($mday, $mon, $year, $wday);

	$mday = $tm[3];
	$mon = $tm[4];
	$year = $tm[5];
	$wday = $tm[6];

	my($ts) = mktime(0, 0, 0, $mday, $mon, $year);

	my($e) = 0;

	if ( $wday + $d >= 5 )
	{
		$e = 2;
	}

	my($s) = ($d + $e) * 86400;

	my($r) = $ts + $s;

	return($r);
}

sub get_starttime($)
{
	my($s) = shift;

	my($ts);

	if ( $s =~ /^max:(.*)/ )
	{
		my($var) = $1;
		my(@a) = split('\s', $var);
		$ts = 0;

		foreach $v (@a)
		{
			if ( defined($timestamp{$v}) )
			{
				$tv = $timestamp{$v};
				if ( $ts < 1 || $tv > $ts )
				{
					$ts = $tv;
				}
			}
		}
#		printf STDERR ("DBX [%s] [%s]\n", $s, $ts);
	}
	elsif ( $s =~ /^min:(.*)/ )
	{
		my($var) = $1;
		my(@a) = split('\s', $var);
		$ts = 0;

		foreach $v (@a)
		{
			if ( defined($timestamp{$v}) )
			{
				$tv = $timestamp{$v};
				if ( $ts < 1 || $tv < $ts )
				{
					$ts = $tv;
				}
			}
		}
#		printf STDERR ("DBX [%s] [%s]\n", $s, $ts);
	}
	elsif ( $s =~ /^nextday:(.*)/ )
	{
		# next day 09:00
		$dhm = $1;
		if ( $dhm =~ /(\d+)\s+(\d+):(\d+)/ )
		{
			my($d) = $1;
			my($h) = $2;
			my($m) = $3;
			my($delta) = 3600 * $h + 60 * $m;
			my($now) = $timestamp{'auto'};

			my($t) = get_nextday($now, $d);

			$ts = $t + $delta;
		}
	}
	elsif ( $s =~ /^nextworkday:(.*)/ )
	{
		# next work day 09:00
		$dhm = $1;
		if ( $dhm =~ /(\d+)\s+(\d+):(\d+)/ )
		{
			my($d) = $1;
			my($h) = $2;
			my($m) = $3;
			my($delta) = 3600 * $h + 60 * $m;
			my($now) = $timestamp{'auto'};

			my($t) = get_nextworkday($now, $d);

			$ts = $t + $delta;
		}
	}
	elsif ( defined($timestamp{$s}) )
	{
		$ts = $timestamp{$s};
	}
	elsif ( $s =~ /[0-9]{4}-[01][0-9]-[0-3][0-9]\s+[012][0-9]:[0-5][0-9]:[0-5][0-9]/ )
	{
		$ts = time_epoch($s);
	}

	return($ts);
}

sub fmt_duration($)
{
	my($t) = shift;

	my($h) = int($t/3600);

	my($m) = int( ($t - 3600 * $h) / 60 );

	my($ts) = sprintf("%02d:%02d", $h, $m);

	return($ts);
}

sub fmt_time($)
{
	my($t) = shift;

	my(@tm) = localtime($t);

	my($ts) = POSIX::strftime('%Y-%m-%d %H:%M:%S', @tm);

	return($ts);
}

sub parse_global($)
{
	my($s) = shift;

	my(@a) = split(',', $s);
	return(@a);
}

sub parse_define($$)
{
	my($s) = shift;
	my($n) = shift;

	my(@a) = split(',', $s, $n);
	return(@a);
}

sub parse_activity($)
{
	my($s) = shift;

	my(@a) = split(',', $s);
	return(@a);
}

sub parse_task($)
{
	my($s) = shift;

	my(@a) = split(',', $s);
	return(@a);
}

sub parse_milestone($)
{
	my($s) = shift;

	my(@a) = split(',', $s);
	return(@a);
}

sub parse_contact($)
{
	my($s) = shift;

	my(@a) = split(',', $s);
	return(@a);
}

sub parse_version($)
{
	my($s) = shift;

	my(@a) = split(',', $s);
	return(@a);
}

sub get_input($)
{
	my($filename) = shift;

	my($conf) = ();

	my $row_count = 0;

	my @lines = read_file($filename);

	foreach (@lines)
	{
		my $idx = 0;

		chomp;
		s/\r//;

		next if ( /^(#.*|\s*)$/ );

#		printf STDERR ("# line = [%s]\n", $_);

		my(@a) = split(',', $_);

		next if ( $a[0] eq 'KEY' );

		{
			$conf->[$row_count]{'key'} = $a[$idx++];
			$conf->[$row_count]{'vmname'} = $a[$idx++];
			$conf->[$row_count]{'naa'} = $a[$idx++];
			$conf->[$row_count]{'tenant'} = $a[$idx++];

			$conf->[$row_count]{'tier'} = $a[$idx++];
			$conf->[$row_count]{'size'} = $a[$idx++];
			$conf->[$row_count]{'qos'} = $a[$idx++];
			$conf->[$row_count]{'datastore'} = $a[$idx++];
			$conf->[$row_count]{'iops'} = $a[$idx++];
			$conf->[$row_count]{'qos_t1'} = $a[$idx++];
			$conf->[$row_count]{'qos_t2'} = $a[$idx++];
			$conf->[$row_count]{'qos_t3'} = $a[$idx++];
			$conf->[$row_count]{'bh_t1'} = $a[$idx++];
			$conf->[$row_count]{'bh_t2'} = $a[$idx++];
			$conf->[$row_count]{'bh_t3'} = $a[$idx++];
			$conf->[$row_count]{'ah_t1'} = $a[$idx++];
			$conf->[$row_count]{'ah_t2'} = $a[$idx++];
			$conf->[$row_count]{'ah_t3'} = $a[$idx++];
			$conf->[$row_count]{'action'} = $a[$idx++];
			$conf->[$row_count]{'target'} = $a[$idx++];
			$conf->[$row_count]{'reason'} = $a[$idx++];
			$conf->[$row_count]{'cost'} = $a[$idx++];
			$conf->[$row_count]{'cost_new'} = $a[$idx++];
			$conf->[$row_count]{'first_sighted'} = $a[$idx++];
			$conf->[$row_count]{'last_sighted'} = $a[$idx++];

			$conf->[$row_count]{'customer'} = $a[$idx++];
			$conf->[$row_count]{'business'} = $a[$idx++];
			$conf->[$row_count]{'application'} = $a[$idx++];

#			print Dumper($conf);
			$row_count++;
		}
	}

	my $config;
	$config->{'data'} = $conf;
	my $jconfig = encode_json($config);
	return ($jconfig);
}

sub make_output($$)
{
	my($fh) = shift;
	my($s) = shift;

	if (ref($fh) eq "GLOB")
	{
		printf $fh ("%s\n", $s);
	}
	else
	{
		open(FH, ">$fh") || return(0);
		printf FH ("%s\n", $s);
		close(FH);
	}

	return(0);
}

#
# main
#
parse_command_line();

my ($jconf) = get_input($opt_input);

if (defined ($opt_output) )
{
	make_output($opt_output, $jconf);
}
else
{
	make_output(\*STDOUT, $jconf);
}

