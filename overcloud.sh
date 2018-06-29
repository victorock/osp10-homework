#!/bin/bash

mkdir /root/httpd_conf_gnocchi
mv /etc/httpd/conf.d/{10-aodh_wsgi.conf,10-ceilometer_wsgi.conf,10-gnocchi_wsgi.conf} /root/httpd_conf_gnocchi/
systemctl restart httpd

systemctl list-units | egrep 'gnocchi|ceilo|aodh' > /root/gnocchi_backup.txt
systemctl list-unit-files | egrep 'gnocchi|ceilo|aodh' >> /root/gnocchi_backup.txt
systemctl list-unit-files |  egrep 'gnocchi|aodh|ceil' | awk '{print $1}' | while read service; do echo $service ; systemctl stop $service ; systemctl disable $service ; done
