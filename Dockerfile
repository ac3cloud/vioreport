FROM amazonlinux:latest

# Set environment variable
ENV NO_HTTPD 1

# Install necessary packages and create directories
RUN yum -y update && \
    yum -y install vim wget unzip perl yum-utils uuid-devel findutils php8.1 php8.1-cli cronie && \
    yum clean all && \
    rm -rf /var/cache/yum && \
    mkdir -p /usr/ac3/doj /usr/ac3/etc /opt/vio /usr/ac3/vir /usr/ac3/reports /usr/ac3/vio-data /usr/share/php/tbs /usr/ac3/dcj-esx-sy6 /usr/ac3/dcj-esx-sy7 /var/data

# Download and install TinyButStrong library and OpenTBS plugin
RUN wget "https://www.tinybutstrong.com/dl.php?f=tbs_us.zip&s=2" -O /tmp/tbs_us.zip && \
    wget "https://www.tinybutstrong.com/download/download.php?file=tbs_plugin_opentbs.zip&sid=2" -O /tmp/tbs_plugin_opentbs.zip && \
    unzip /tmp/tbs_us.zip -d /usr/share/php/tbs && \
    unzip /tmp/tbs_plugin_opentbs.zip -d /usr/share/php/tbs/plugins && rm -f /tmp/*

# Copy files to the appropriate locations
COPY ./etc/customers.csv /usr/ac3/etc/
COPY ./vir/ /usr/ac3/vir
COPY ./dcj-esx-sy6/ /usr/ac3/dcj-esx-sy6/
COPY ./dcj-esx-sy7/ /usr/ac3/dcj-esx-sy7/
COPY ./reports/ /usr/ac3/reports
COPY ./rpms/vio-data-1.0-4.ac3.el6.x86_64.rpm /tmp/
COPY ./jmerge/jmerge.php /usr/ac3/bin/jmerge.php
COPY ./rpms/VMware-vSphere-Perl-SDK-6.7.0-8156551.1.ac3.el6.noarch.rpm /tmp/
RUN rpm -ivh --nodeps  /tmp/VMware-vSphere-Perl-SDK-6.7.0-8156551.1.ac3.el6.noarch.rpm
RUN rpm -ivh --nodeps  /tmp/vio-data-1.0-4.ac3.el6.x86_64.rpm
COPY ./vio-data/run-vio.sh /usr/ac3/vio-data
COPY ./vio-data/vmware.authfile /usr/ac3
# Install Perl modules
RUN perl -MCPAN -e 'CPAN::Shell->notest("install", $_) for @ARGV' UUID Monitoring::Plugin XML::LibXML Crypt::SSLeay SOAP::Lite DateTime JSON

# Update script file
RUN perl -pi -e "s/Nagios/Monitoring/g" /usr/ac3/vio-data/vio-info.pl && perl -pi -e "s/Nagios/Monitoring/g" /usr/ac3/vio-data/vio.pl

RUN cat /usr/ac3/vio-data/vio-data.cron >> /etc/crontab
# Define mount point for external data
VOLUME /var/data

CMD crond -n -s
