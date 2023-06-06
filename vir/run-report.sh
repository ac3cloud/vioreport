#!/bin/bash

# run week view (7 day view) reports

report=${1:-/usr/ac3/reports/dcj.report}
debug=${2:-0}
control=${3:-all}
report_home=${4:-${HOME}/vir}

report_base=$(basename ${report} .report)

if [ ! -d ${report_home}/${report_base} ]; then
	mkdir -p ${report_home}/${report_base}
fi

run_scan=false
run_split=false
run_analyse=false
run_report=false
run_xlsx=false
run_plot=false

case "$control" in
	all)
		run_scan=true
		run_split=true
		run_analyse=true
		run_report=true
		run_xlsx=true
		run_plot=true
		;;
esac

case "$control" in
	*scan*)
		run_scan=true
		;;
esac

case "$control" in
	*split*)
		run_split=true
		;;
esac

case "$control" in
	*analyse*)
		run_analyse=true
		;;
esac

case "$control" in
	*report*)
		run_report=true
		;;
esac

case "$control" in
	*xlsx*)
		run_xlsx=true
		;;
esac

case "$control" in
	*plot*)
		run_plot=true
		;;
esac

cd ${report_home}/${report_base} && /bin/rm -f *.csv *.gnu *.png *.index* report.* 

$run_scan && /usr/ac3/vir/scan.pl \
	--config ${report} \
	--output scan.index \
	--action scan \
	--debug ${debug}

$run_split && /usr/ac3/vir/scan.pl \
	--config ${report} \
	--output split.index \
	--action split \
	--index scan.index \
	--fill 1 \
	--debug ${debug}

$run_analyse && /usr/ac3/vir/scan.pl \
	--config ${report} \
	--output analyse.index \
	--action analyse \
	--index split.index \
	--debug ${debug}

$run_report && /usr/ac3/vir/scan.pl \
	--config ${report} \
	--output report.index \
	--action report \
	--index analyse.index \
	--debug ${debug}

$run_report && echo "Summary: U $(grep -i upgrade report.index |wc -l) D $(grep -i downgrade report.index |wc -l) S $(grep -i 'no change' report.index |wc -l) T $(( $(wc -l report.index | cut -d" " -f1) - 1 ))"

$run_xlsx && /usr/ac3/vir/report-data.pl \
		--input report.index \
	| /usr/ac3/bin/jmerge.php \
		-t /usr/ac3/vir/vir-template.xlsx \
		-T v \
		-o report.xlsx

$run_plot && /usr/ac3/vir/do-plot.sh ${report} ${debug}
