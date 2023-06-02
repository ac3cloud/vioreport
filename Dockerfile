FROM amazonlinux:latest

# Set environment variable
ENV NO_HTTPD 1

# Install necessary packages and create directories
RUN yum -y update && \
    yum -y install wget unzip perl yum-utils uuid-devel findutils php8.1 php8.1-cli && \
    yum clean all && \
    rm -rf /var/cache/yum && \
    mkdir -p /opt/vio /usr/ac3/vir /usr/ac3/reports /usr/ac3/vio-data /usr/share/php/tbs /usr/ac3/dcj-esx-sy6 /usr/ac3/dcj-esx-sy7 /var/data

# Download and install TinyButStrong library and OpenTBS plugin
RUN wget -P /tmp "https://www.tinybutstrong.com/dl.php?f=tbs_us.zip&s=2" && \
    wget -P /tmp "https://www.tinybutstrong.com/download/download.php?file=tbs_plugin_opentbs.zip&sid=2" && \
    unzip /tmp/tbs_us.zip -d /usr/share/php/tbs && \
    unzip /tmp/tbs_plugin_opentbs.zip -d /usr/share/php/tbs/plugins && \
    rm /tmp/tbs_us.zip /tmp/tbs_plugin_opentbs.zip

# Copy files to the appropriate locations
COPY ./vir/ /usr/ac3/vir
COPY ./dcj-esx-sy6/ /usr/ac3/dcj-esx-sy6/
COPY ./dcj-esx-sy7/ /usr/ac3/dcj-esx-sy7/
COPY ./reports/ /usr/ac3/reports
COPY ./rpms/vio-data-1.0-4.ac3.el6.x86_64.rpm /tmp/
COPY ./jmerge/jmerge.php /usr/ac3/bin/jmerge.php
COPY ./rpms/VMware-vSphere-Perl-SDK-6.7.0-8156551.1.ac3.el6.noarch.rpm /tmp/
COPY ./vio-data/run-vio.sh /usr/ac3/vio-data
COPY ./vio-data/vmware.authfile /usr/ac3

# Install Perl modules
RUN perl -MCPAN -e 'CPAN::Shell->notest("install", $_) for @ARGV' UUID Monitoring::Plugin XML::LibXML Crypt::SSLeay SOAP::Lite

# Update script file
RUN perl -pi -e "s/Nagios/Monitoring/g" /usr/ac3/vio-data/vio-info.pl && perl -pi -e "s/Nagios/Monitoring/g" /usr/ac3/vio-data/vio.pl

# Define mount point for external data
VOLUME /var/data

