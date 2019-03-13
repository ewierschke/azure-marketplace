#!/bin/bash

# Custom logging with time so we can easily relate running times, also log to separate file so order is guaranteed.
# The Script extension output the stdout/err buffer in intervals with duplicates.
log()
{
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1"
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1" >> /var/log/arm-install.log
}

log "Begin execution of watchmaker script extension on ${HOSTNAME}"
START_TIME=$SECONDS

watchmaker_hardening()
{
    log "[watchmaker_hardening] running watchmaker for hardening"
    yum -y install epel-release 
    # Install pip
    yum -y --enablerepo=epel install python-pip wget 
    # Install setup dependencies for python 2.x (removed ver dep for pip, others from readthedocs re 2.6, not sure if applicable to 2.7)
    pip install --upgrade "pip" "wheel<0.30.0" "setuptools<37"
    # Install Watchmaker
    pip install --upgrade watchmaker 
    # Setup terminal support for UTF-8
    export LC_ALL=en_US.UTF-8
    export LANG=en_US.UTF-8
    # Run Watchmaker
    watchmaker --no-reboot --log-level debug --log-dir=/var/log/watchmaker --config=/usr/lib/python2.7/site-packages/watchmaker/static/config.yaml
    if [ $? -ne 0 ]; then
        log "watchmaker didn't run correctly, exit"
        exit 1
    fi
    log "[watchmaker_hardening] disabling fips mode for azure linux agent and extensions"
    salt-call --local ash.fips_disable
}

update_and_reboot_in_2_min()
{
    log "[update_and_reboot_in_2_min] prep for yum update"
    (
        printf "yum -y update\n"
        printf "shutdown -r now\n"
    ) > /root/update.sh
    chmod 700 /root/update.sh
    yum -y install at
    service atd start
    log "[update_and_reboot_in_2_min] run yum update in 2 min and then reboot"
    at now + 2 minutes -f /root/update.sh
}

#########################
# Installation sequence
#########################

#test adjusting resolv.conf for domain join
log "[resolv_adjust] adding IP to resolv.conf"
sed -e '/168.63.129.16/ s/^#*/#/' -i /etc/resolv.conf
echo "nameserver 10.33.0.4" >> /etc/resolv.conf
echo "nameserver 10.33.0.4" >> /etc/resolv.conf.save
log "[resolv_adjust] adding DNS1 to ifcfg"
echo "DNS1="10.33.0.4"" >> /etc/sysconfig/network-scripts/ifcfg-eth0
log "[resolv_adjust] removing azure dns"
echo "PEERDNS=no" >> /etc/sysconfig/network-scripts/ifcfg-eth0
sed -e '/168.63.129.16/ s/^#*/#/' -i /etc/resolv.conf

watchmaker_hardening

update_and_reboot_in_2_min

ELAPSED_TIME=$(($SECONDS - $START_TIME))
PRETTY=$(printf '%dh:%dm:%ds\n' $(($ELAPSED_TIME/3600)) $(($ELAPSED_TIME%3600/60)) $(($ELAPSED_TIME%60)))

log "End execution of Elasticsearch script extension on ${HOSTNAME} in ${PRETTY}"
exit 0
