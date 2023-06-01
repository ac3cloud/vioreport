#!/bin/bash

for each in *.csv
do
	/usr/ac3/vir/fix-ts.pl ${each} > $$.csv
	mv $$.csv ${each}
done
