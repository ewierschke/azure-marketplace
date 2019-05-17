#!/bin/bash

#Templated script to be edited by ARM template command prior to execution by other scripts

# Custom logging with time so we can easily relate running times, also log to separate file so order is guaranteed.
# The Script extension output the stdout/err buffer in intervals with duplicates.
log()
{
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1"
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1" >> /var/log/arm-install.log
}

log "Begin execution of set-static-dns script on ${HOSTNAME}"
START_TIME=$SECONDS


#########################
# Installation sequence
#########################

#test adjusting resolv.conf for domain join
log "[resolv_adjust] adding DNS IP to resolv.conf"
echo "nameserver CHANGE_ME1" >> /etc/resolv.conf
echo "nameserver CHANGE_ME1" >> /etc/resolv.conf.save
echo "nameserver CHANGE_ME2" >> /etc/resolv.conf
echo "nameserver CHANGE_ME2" >> /etc/resolv.conf.save
echo "search CHANGE_ME3" >> /etc/resolv.conf
echo "search CHANGE_ME3" >> /etc/resolv.conf.save
log "[resolv_adjust] adding DNS1 to ifcfg"
echo "DNS1="CHANGE_ME1"" >> /etc/sysconfig/network-scripts/ifcfg-eth0
log "[resolv_adjust] adding DNS2 to ifcfg"
echo "DNS2="CHANGE_ME2"" >> /etc/sysconfig/network-scripts/ifcfg-eth0
log "[resolv_adjust] adding suffix to ifcfg"
echo "SEARCH="CHANGE_ME3"" >> /etc/sysconfig/network-scripts/ifcfg-eth0
log "[resolv_adjust] removing azure dns"
echo "PEERDNS=no" >> /etc/sysconfig/network-scripts/ifcfg-eth0
sed -e '/168.63.129.16/ s/^#*/#/' -i /etc/resolv.conf

ELAPSED_TIME=$(($SECONDS - $START_TIME))
PRETTY=$(printf '%dh:%dm:%ds\n' $(($ELAPSED_TIME/3600)) $(($ELAPSED_TIME%3600/60)) $(($ELAPSED_TIME%60)))

log "End execution of set-static-dns script on ${HOSTNAME} in ${PRETTY}"
exit 0
