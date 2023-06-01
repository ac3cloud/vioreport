FROM amazonlinux:latest
ENV NO_HTTPD 1
WORKDIR /
RUN mkdir -p /opt/vio && mkdir -p /usr/ac3/vir && mkdir -p /usr/ac3/reports
COPY ./vir/ /usr/ac3/vir
COPY ./reports/ /usr/ac3/reports
#COPY ../vio/ /opt/vio/
COPY ./rpms/vio-data-1.0-4.ac3.el6.x86_64.rpm  /tmp/
COPY ./jmerge/jmerge.php /usr/ac3/bin/jmerge.php
COPY ./rpms/VMware-vSphere-Perl-SDK-6.7.0-8156551.1.ac3.el6.noarch.rpm /tmp/
RUN yum -y install perl yum-utils uuid-devel findutils
RUN rpm -ivh --nodeps  /tmp/VMware-vSphere-Perl-SDK-6.7.0-8156551.1.ac3.el6.noarch.rpm
RUN rpm -ivh --nodeps  /tmp/vio-data-1.0-4.ac3.el6.x86_64.rpm
RUN perl -MCPAN -e 'CPAN::Shell->notest("install", $_) for @ARGV' UUID Monitoring::Plugin XML::LibXML Crypt::SSLeay SOAP::Lite
RUN mkdir -p /opt/reports # This should be a bind mount from the OS
