FROM amazonlinux:latest
ENV NO_HTTPD 1
WORKDIR /
RUN yum -y install wget unzip && mkdir -p /opt/vio && mkdir -p /usr/ac3/vir && mkdir -p /usr/ac3/reports && mkdir -p /usr/ac3/vio-data && mkdir -p /usr/share/php/tbs
RUN cd /tmp && wget "https://www.tinybutstrong.com/dl.php?f=tbs_us.zip&s=2" -O tbs.zip && wget "https://www.tinybutstrong.com/download/download.php?file=tbs_plugin_opentbs.zip&sid=2" -O opentbs.zip && cd /usr/share/php/tbs && unzip /tmp/tbs.zip &&  cd /usr/share/php/tbs/plugins && unzip /tmp/opentbs.zip
COPY ./vir/ /usr/ac3/vir
COPY ./dcj-esx-sy6/ /usr/ac3/
COPY ./dcj-esx-sy7/ /usr/ac3/
COPY ./reports/ /usr/ac3/reports
COPY ./rpms/vio-data-1.0-4.ac3.el6.x86_64.rpm  /tmp/
COPY ./jmerge/jmerge.php /usr/ac3/bin/jmerge.php
COPY ./rpms/VMware-vSphere-Perl-SDK-6.7.0-8156551.1.ac3.el6.noarch.rpm /tmp/
RUN yum -y install perl yum-utils uuid-devel findutils php8.1 php8.1-cli
RUN rpm -ivh --nodeps  /tmp/VMware-vSphere-Perl-SDK-6.7.0-8156551.1.ac3.el6.noarch.rpm
RUN rpm -ivh --nodeps  /tmp/vio-data-1.0-4.ac3.el6.x86_64.rpm
RUN perl -MCPAN -e 'CPAN::Shell->notest("install", $_) for @ARGV' UUID Monitoring::Plugin XML::LibXML Crypt::SSLeay SOAP::Lite
RUN perl -pi -e "s/Nagios/Monitoring/g" /usr/ac3/vio-data/vio-info.pl
COPY ./vio-data/run-vio.sh /usr/ac3/vio-data
COPY ./vio-data/vmware.authfile /usr/ac3
RUN mkdir -p /var/data # This should be a bind mount from the OS
