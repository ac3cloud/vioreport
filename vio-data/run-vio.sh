#!/bin/bash
#
# 2017-02-26 Youzhen Cheng, Youzhen.Cheng@ac3.com.au
#
# TODO: MAke this dynamic via mount
for each in $( cat \
	/usr/ac3/dcj-esx-*/esx-*/esx.list \
	| egrep -v '^ *(#|$)' \
	| awk '{printf("%s:%s\n", $1, $2);}' )
do
	host="${each%%\:*}"
	ip="${each#*\:}"

	if [ ! -d /var/data/${host} ]; then
		mkdir -p /var/data/${host}
	fi

	/usr/ac3/vio-data/vio.pl -f /usr/ac3/vmware.authfile \
	-S /tmp/vsession.${ip} \
	-H ${ip} >> /var/data/${host}/$(date +'%Y-%m-%d' --date='45 minutes ago') &

done

wait

for each in $( cat \
	/usr/ac3/dcj-esx-*/esx-*/esx.list \
	| egrep -v '^ *(#|$)' \
	| awk '{printf("%s:%s\n", $1, $2);}' )
do
	host="${each%%\:*}"
	ip="${each#*\:}"

	if [ ! -d /var/data/info ]; then
		mkdir -p /var/data/info
	fi

	/usr/ac3/vio-data/vio-info.pl -f /usr/ac3/vmware.authfile \
	-S /tmp/vsession.${ip} \
	-H ${ip} -t 120 > /var/data/info/${host}.vinfo &

done
