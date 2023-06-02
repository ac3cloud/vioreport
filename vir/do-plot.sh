#!/bin/bash
#
# 2017-02-26 Youzhen Cheng, Youzhen.Cheng@ac3.com.au
#
#export GDFONTPATH=/usr/share/fonts/liberation:${GDFONTPATH}
export GDFONTPATH=/usr/share/fonts/open-sans:${GDFONTPATH}

report=${1:-/usr/ac3/doj/i1-mgt-mon01-day.report}
debug=${2:-0}
report_home=${3:-${HOME}/vir}

report_base=$(basename ${report} .report)

if [ ! -d ${report_home}/${report_base} ]; then
	mkdir -p ${report_home}/${report_base}
fi

cd ${report_home}/${report_base}

/usr/ac3/vir/plot.pl \
	--config ${report} \
	--template /usr/ac3/vir/area.template \
	--index report.index \
	--type iops \
	--style line \
	--scale 1 \
	--debug ${debug}

for each in *.gnu
do
	gnuplot ${each}
done

/usr/ac3/vir/scan.pl \
	--config ${report} \
	--action html \
	--index  report.index \
	--output report.html \
	--debug ${debug}
