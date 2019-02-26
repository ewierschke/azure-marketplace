#!/bin/bash

# License: https://github.com/elastic/azure-marketplace/blob/master/LICENSE.txt
#
# Russ Cam (Elastic)
#

export DEBIAN_FRONTEND=noninteractive

#########################
# HELP
#########################

help()
{
    echo "This script installs Java on CentOS using the openjdk-8-jdk rpm package"
    echo ""
    echo "Options:"
    echo "   -h         this help message"
}

log()
{
    echo \[$(date +%d%m%Y-%H:%M:%S)\] \["install_java"\] "$1"
    echo \[$(date +%d%m%Y-%H:%M:%S)\] \["install_java"\] "$1" >> /var/log/arm-install.log
}

#########################
# Parameter handling
#########################

while getopts h optname; do
    log "Option $optname set with value ${OPTARG}"
  case ${optname} in
    h)  #show help
      help
      exit 2
      ;;
    \?) #unrecognized option - show help
      echo -e \\n"Option -${BOLD}$OPTARG${NORM} not allowed."
      help
      exit 2
      ;;
  esac
done

install_java()
{
    # Max retry count
    MAX_RETRY=5 
    log "Installing Java"
    RETRY=0
    while [ $RETRY -lt $MAX_RETRY ]; do
        log "Retry $RETRY: installing epel-release..."
        yum -y install epel-release
        if [ $? -ne 0 ]; then
            let RETRY=RETRY+1
        else
            break
        fi
    done
    if [ $RETRY -eq $MAX_RETRY ]; then
        log "Failed to download epel-release for java-1.8.0-openjdk install."
        exit 1
    fi
    yum -y install java-1.8.0-openjdk
    log "installed java"
}

install_java
