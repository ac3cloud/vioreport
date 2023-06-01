# vioreport

vioreport processes VM IO performance data collected by vio-data on ESXi hosts.

# Report definition files

Private cloud

doj.wvpm.i1-doj-mon01.report = DOJ Weekly View per month report - data collected on i1-doj-mon01
doj.wvpm.s2-doj-mon01.report = DOJ Weekly View per month report - data collected on s2-doj-mon01

AC3 Shared Cloud

doj.wvpm.i1-mgt-mon01.report = DOJ Weekly View per month report - data collected on i1-mgt-mon01
doj.wvpm.s2-mgt-mon01.report = DOJ Weekly View per month report - data collected on s2-mgt-mon01

# run report

run-report.sh doj.wvpm.i1-doj-mon01.report

There are a few steps,

   run_scan    = scan data files - superimpose data to defined view (all, week, day)
   run_split   = split data into files for individual VMs
   run_analyse = analyse VM data
   run_report  = produce VM report
   run_xlsx    = assemble report data and fit into xlsx template
   run_plot    = gnuplot for charting
