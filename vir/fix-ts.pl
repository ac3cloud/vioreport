#!/usr/bin/perl
#
# fix timestamp problem
#
use POSIX;

my $ts_old_base = 0;
my $ts_old = 0;
my $ts_new = 0;
my $delta = 0;

sub get_ts($)
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

        return($r);
}

sub ts_to_seconds($)
{
        my $ts = shift;

        local(@dt) = split('\s',$ts);
        local($y,$m,$d) = split('-',$dt[0]);
        local(@t) = split(':',$dt[1]);

        my $s = POSIX::mktime($t[2],$t[1],$t[0],$d,$m-1,$y-1900,0,0,1);

        return($s);
}

sub scan($)
{
	my $filename = shift;

	open(FH, "<", $filename) || return(1);
	while(<FH>)
	{
		chomp;
		my(@a) = split(',', $_, 2);
		next if ( $a[0] eq 'TIME' );

		my $s = ts_to_seconds($a[0]);

		if ( $ts_old < 1 )
		{
			$ts_old_base = $s;
			$ts_old = $s;
		}

		if ( $s > $ts_old
			&& $s < ( $ts_old_base + 172800 ) )
		{
			$ts_old = $s;
		}

		if ( $ts_new < 1 || $s > $ts_new )
		{
			$ts_new = $s;
		}
	}
	close(FH);
}

sub filter($)
{
	my $filename = shift;

	open(FH, "<", $filename) || return(1);
	while(<FH>)
	{
		chomp;
		my(@a) = split(',', $_, 2);
		my $s = ts_to_seconds($a[0]);
		my $ts = $a[0];

		if ( $a[0] ne 'TIME' )
		{
			if ( $s <= $ts_old )
			{
				$ts = get_ts($s + $delta);
			}
		}

		printf("%s,%s\n", $ts, $a[1]);
	}
	close(FH);
}

scan($ARGV[0]);

$delta = $ts_new - $ts_old;

#printf("OLD = [%s]\n", $ts_old);
#printf("NEW = [%s]\n", $ts_new);

filter($ARGV[0]);
