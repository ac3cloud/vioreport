FROM amazonlinux:latest
ARG location
ENV site_location $location
# Set environment variable
ENV NO_HTTPD 1
ENV TZ=Australia/Sydney
# Install necessary packages and create directories
RUN yum -y update && \
    yum -y install tzdata mailx vim wget unzip perl yum-utils uuid-devel findutils php8.1 php8.1-cli cronie gnuplot-minimal && \
    yum clean all && \
    rm -rf /var/cache/yum && \
    mkdir -p /var/report /var/data /root/vir/dcj /usr/ac3/doj /usr/ac3/etc /opt/vio /usr/ac3/vir /usr/ac3/reports /usr/ac3/vio-data /usr/share/php/tbs /usr/ac3/dcj-esx-$location /var/data /var/report/storage /var/report/vio

# Download and install TinyButStrong library and OpenTBS plugin
RUN wget "https://www.tinybutstrong.com/dl.php?f=tbs_us.zip&s=2" -O /tmp/tbs_us.zip && \
    wget "https://www.tinybutstrong.com/download/download.php?file=tbs_plugin_opentbs.zip&sid=2" -O /tmp/tbs_plugin_opentbs.zip && \
    unzip /tmp/tbs_us.zip -d /usr/share/php/tbs && \
    unzip /tmp/tbs_plugin_opentbs.zip -d /usr/share/php/tbs/plugins && rm -f /tmp/*

# Copy files to the appropriate locations
COPY ./reports/NAA.csv /var/report/storage/
COPY ./etc/customer.csv /usr/ac3/etc/
COPY ./vir/ /usr/ac3/vir
COPY ./dcj-esx-$location/ /usr/ac3/dcj-esx-$location/
COPY ./reports/pricebook-doj.csv /usr/ac3/etc/
COPY ./reports/doj-cba.map /usr/ac3/etc/
COPY ./reports/ /usr/ac3/reports
COPY ./rpms/vio-data-1.0-4.ac3.el6.x86_64.rpm /tmp/
COPY ./jmerge/jmerge.php /usr/ac3/bin/jmerge.php
COPY ./rpms/VMware-vSphere-Perl-SDK-6.7.0-8156551.1.ac3.el6.noarch.rpm /tmp/
RUN rpm -ivh --nodeps  /tmp/VMware-vSphere-Perl-SDK-6.7.0-8156551.1.ac3.el6.noarch.rpm
RUN rpm -ivh --nodeps  /tmp/vio-data-1.0-4.ac3.el6.x86_64.rpm
COPY ./vio-data/run-vio.sh /usr/ac3/vio-data
COPY ./vio-data/vmware.authfile /usr/ac3
# Install Perl modules
RUN perl -MCPAN -e 'CPAN::Shell->notest("install", $_) for @ARGV' UUID Monitoring::Plugin XML::LibXML Crypt::SSLeay SOAP::Lite DateTime POSIX::strptime JSON
# Dowgrade LWP
RUN perl -MCPAN -e 'CPAN::Shell->notest("install", "OALDERS/libwww-perl-6.68/tar.gz");'
# Update script file
RUN perl -pi -e "s/Nagios/Monitoring/g" /usr/ac3/vio-data/vio-info.pl && perl -pi -e "s/Nagios/Monitoring/g" /usr/ac3/vio-data/vio.pl
# TOTAL HACK JOB IM PROUD OF THIS
RUN awk 'NR==51{print "$ssl_opts->{SSL_verify_mode} = 0;"}1' /usr/local/share/perl5/5.32/LWP/UserAgent.pm > /tmp/UserAgent.pm && mv /tmp/UserAgent.pm /usr/local/share/perl5/5.32/LWP/UserAgent.pm
RUN cat /usr/ac3/vio-data/vio-data.cron >> /etc/crontab
RUN echo "0 9 2 * * root /usr/ac3/vir/run-report.sh > /dev/null 2>&1" >> /etc/crontab

# Define mount point for external data
VOLUME /var/data
VOLUME /var/report
VOLUME /root/vir/dcj

CMD crond -n -s
