#!/bin/bash
# Description:
# Configure HTTPD on CentOS 7 for LDAPS based authentication
# Requires URL to credential file containing properly yaml formatted content,
#  public certificate of LDAP server in order to make LDAPS/636 connection
#  and DN of an LDAP group to be granted access to HTTPD
# Pulls domain name from executing servers' network settings
#################################################################
__ScriptName="kibananodeldapsauth.sh"

set -e
set -o pipefail

log()
{
    logger -i -t "${__ScriptName}" -s -- "$1" 2> /dev/console
    echo "$1"
}  # ----------  end of function log  ----------

die()
{
    [ -n "$1" ] && log "$1"
    log "httpd ldaps (kibananodeldapsauth.sh) config failed"'!'
    exit 1
}  # ----------  end of function die  ----------

retry()
{
    # Make an arbitrary number of attempts to execute an arbitrary command,
    # passing it arbitrary parameters. Convenient for working around
    # intermittent errors (which occur often with poor repo mirrors).
    #
    # Returns the exit code of the command.
    local n=0
    local try=$1
    local cmd="${*: 2}"
    local result=1
    [[ $# -le 1 ]] && {
        echo "Usage $0 <number_of_retry_attempts> <Command>"
        exit $result
    }

    echo "Will try $try time(s) :: $cmd"

    if [[ "${SHELLOPTS}" == *":errexit:"* ]]
    then
        set +e
        local ERREXIT=1
    fi

    until [[ $n -ge $try ]]
    do
        sleep $n
        $cmd
        result=$?
        test $result -eq 0 && break || {
            ((n++))
            echo "Attempt $n, command failed :: $cmd"
        }
    done

    if [[ "${ERREXIT}" == "1" ]]
    then
        set -e
    fi

    return $result
}  # ----------  end of function retry  ----------

usage()
{
    cat << EOT
  Usage:  ${__ScriptName} [options]

  Note:
  If no options are specified, HTTPD cannot be configured for ldaps auth. This 
  script assumes previous execution of httpdrevproxyselfsigned.sh and should not
  be run twice in a row without first re-reunning httpdrevproxyselfsigned.sh

  Options:
  -h  Display this message.
  -C  URL from which to download LDAP server public certificate to be added to 
      HTTPD configuration for LDAPS authentication.
  -E  URL from which to download environment specific content zip file.
  -G  DN of the LDAP group to allow access to HTTPD
EOT
}  # ----------  end of function usage  ----------


# Define default values
LDAPS_CERT=
ENV_CONTENT_URL=
LDAP_GROUP_DN=

# Parse command-line parameters
while getopts :h:C:E:G: opt
do
    case "${opt}" in
        h)
            usage
            exit 0
            ;;
        C)
            LDAPS_CERT="${OPTARG}"
            ;;
        E)
            ENV_CONTENT_URL="${OPTARG}"
            ;;
        G)
            LDAP_GROUP_DN="${OPTARG}"
            ;;
        \?)
            usage
            echo "ERROR: unknown parameter \"$OPTARG\""
            exit 1
            ;;
    esac
done
shift $((OPTIND-1))

# Validate parameters
if [ -z "${LDAPS_CERT}" ]
then
    log "No LDAPS_CERT (-C) was provided, can't configure HTTPD for LDAPS auth"
    exit 1
fi
if [ -z "${ENV_CONTENT_URL}" ]
then
    log "No ENV_CONTENT_URL (-E) was provided, can't configure HTTPD for LDAPS auth"
    exit 1
fi
if [ -z "${LDAP_GROUP_DN}" ]
then
    log "No LDAP_GROUP_DN (-G) was provided, can't configure HTTPD for LDAPS auth"
    exit 1
fi

yum -y install wget unzip 
if [ -n "${LDAPS_CERT}" ]
then
    # download LDAPS certificate not in public chain
    log "Downloading cert for LDAP DCs not in public chain"
    retry 5 wget --timeout=10 \
    "${LDAPS_CERT}" -O /etc/pki/tls/certs/envCA.cer|| \
    die "Could not download ldap cert"
fi

JOIN_TRIM=https://raw.githubusercontent.com/ewierschke/armtemplates/runwincustdata/scripts/join-trim.sh
retry 5 wget --timeout=10 \
    "${JOIN_TRIM}" -O /root/join-trim.sh|| \
    die "Could not download join-trim.sh"
chmod 755 /root/join-trim.sh

retry 5 wget --timeout=10 \
    "${ENV_CONTENT_URL}" -O /root/content.zip|| \
    die "Could not download env content.zip"
unzip -o /root/content.zip -d /root

#get content into variables
log "Getting creds from env file..."
yum -y install epel-release
yum-config-manager --enable epel
yum -y install python-pip jq
pip install pyyaml
python -c 'import sys, yaml, json; json.dump(yaml.load(sys.stdin), sys.stdout, indent=4)' < /root/env.sls > /root/env.json
key1=$(jq '.key' /root/env.json)
pass1=$(jq '.encrypted_password' /root/env.json)
key1=$(sed -e 's/^"//' -e 's/"$//' <<<"$key1")
pass1=$(sed -e 's/^"//' -e 's/"$//' <<<"$pass1")
clearpass=$(/root/join-trim.sh "${pass1}" "${key1}")
user=$(jq '.username' /root/env.json)
user=$(sed -e 's/^"//' -e 's/"$//' <<<"$user")
log "Populated cred variables..."

#get current suffix from network
## need to validate against system handed multiple IP4.DOMAIN entries
log "Populating domain based variables..."
yum -y install bind-utils
#dnsservers=($(tail -n 2 /etc/resolv.conf | awk '{print $2}'))
#dns1=$(nslookup ${dnsservers[0]} | awk '{print $4}')
#dns1=${dns1::-1}
domain=$(dnsdomainname)
#nmcli doesn't work b/c azure nic not controlled by nm
#domain=$(nmcli dev show | grep DOMAIN | awk '{print $2}')
dcarray=($(host -t srv _ldap._tcp."${domain}" | awk '{print $8}'))
dc1=${dcarray[0]::-1}
dc2=${dcarray[1]::-1}
#convert to dn format
dn=$(sed -e 's/\./,dc=/g' <<<"$domain")
fulldn=dc=${dn}
log "Populated domain based variables..."

#to-do add check to validate LDAP_GROUP_DN against dn of domain

#validate variables populated from env and content.zip
if [ -z "${dc1}" ]
then
    log "dc1 var didn't populate check for dns suffix in nmcli output and ad zones"
    exit 1
fi
if [ -z "${dc2}" ]
then
    log "dc2 var didn't populate check for dns suffix in nmcli output and ad zones"
    exit 1
fi
if [ -z "${fulldn}" ]
then
    log "fulldn var didn't populate check for dns suffix in nmcli output and appropriate conversion to dn"
    exit 1
fi
if [ -z "${user}" ]
then
    log "user var didn't populate check content.zip contents"
    exit 1
fi
if [ -z "${clearpass}" ]
then
    log "clearpass var didn't populate check content.zip contents and proper execution of join-trim"
    exit 1
fi

#adjust httpd config
log "Configuring Apache HTTP for cert auth"
yum -y install mod_ldap
cp /etc/httpd/conf.d/ssl.conf /etc/httpd/conf.d/ssl.conf.preauthbak
cd /etc/httpd/conf.d/

#add ldap cert as httpd trusted globalcert
sed -i 's|LoadModule ssl_module modules/mod_ssl.so|LoadModule ssl_module modules/mod_ssl.so\n\nLDAPVerifyServerCert off\nLDAPTrustedMode SSL\nLDAPTrustedGlobalCert CA_BASE64 /etc/pki/tls/certs/envCA.cer\n|' /etc/httpd/conf.d/ssl.conf

#add location section requiring membership in ldap group to auth
sed -i 's|</VirtualHost>|</VirtualHost>\n\n<Location "/">\nAuthName "AD authentication"\nAuthBasicProvider ldap\nAuthType Basic\nAuthLDAPGroupAttribute member\nAuthLDAPGroupAttributeIsDN On\nAuthLDAPURL ldaps://<dc1>:636/<fulldn>?sAMAccountName?sub?(objectClass=*)\nAuthLDAPURL ldaps://<dc2>:636/<fulldn>?sAMAccountName?sub?(objectClass=*)\nAuthLDAPBindDN "<user><fulldn>"\nAuthLDAPBindPassword <password>\nRequire ldap-group <groupfulldn>\n</Location>\n|' /etc/httpd/conf.d/ssl.conf

#replace placeholders with variables
sed -i "s|<dc1>|${dc1}|" /etc/httpd/conf.d/ssl.conf
sed -i "s|<dc2>|${dc2}|" /etc/httpd/conf.d/ssl.conf
sed -i "s|<fulldn>|${fulldn}|g" /etc/httpd/conf.d/ssl.conf
sed -i "s|<user>|${user}|" /etc/httpd/conf.d/ssl.conf
sed -i "s|<password>|${clearpass}|" /etc/httpd/conf.d/ssl.conf
sed -i "s|<groupfulldn>|${LDAP_GROUP_DN}|" /etc/httpd/conf.d/ssl.conf

#increase logging
sed -i "s|LogLevel warn|LogLevel debug|" /etc/httpd/conf.d/ssl.conf

## conf file syntax must be correct, cert file has to exist, module has to be installed for successful restart
#restart httpd
log "Restarting Apache HTTP"
service httpd restart

