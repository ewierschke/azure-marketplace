#!/bin/bash
# Description:
# Configure HTTPD on CentOS 7 for certificate based authentication
# Creates a cert to be trusted by HTTPD for later pickup/xfer
#################################################################
__ScriptName="clientnodecertauth.sh"

log()
{
    logger -i -t "${__ScriptName}" -s -- "$1" 2> /dev/console
    echo "$1"
}  # ----------  end of function log  ----------

die()
{
    [ -n "$1" ] && log "$1"
    log "httpd client cert config failed"'!'
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
  -E  URL from which to download environment specific export zip file.
EOT
}  # ----------  end of function usage  ----------


# Define default values
EXPORT_CRED_URL=

# Parse command-line parameters
while getopts :h:E: opt
do
    case "${opt}" in
        h)
            usage
            exit 0
            ;;
        E)
            EXPORT_CRED_URL="${OPTARG}"
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
if [ -z "${EXPORT_CRED_URL}" ]
then
    log "No EXPORT_CRED_URL (-E) was provided, won't export cert"
fi

if [ ! -z "${EXPORT_CRED_URL}" ]
then
    yum -y install wget unzip 
    JOIN_TRIM=https://raw.githubusercontent.com/ewierschke/armtemplates/runwincustdata/scripts/join-trim.sh
    retry 5 wget --timeout=10 \
        "${JOIN_TRIM}" -O /root/join-trim.sh|| \
        die "Could not download join-trim.sh"
    chmod 755 /root/join-trim.sh

    retry 5 wget --timeout=10 \
        "${EXPORT_CRED_URL}" -O /root/export.zip|| \
        die "Could not download ldap cert"
    unzip -o /root/export.zip -d /root

    #get content into variables
    log "Getting creds from export file..."
    yum -y install epel-release
    yum -y install python-pip jq
    pip install pyyaml
    python -c 'import sys, yaml, json; json.dump(yaml.load(sys.stdin), sys.stdout, indent=4)' < /root/export.sls > /root/export.json
    key1=$(jq '.key' /root/export.json)
    pass1=$(jq '.encrypted_password' /root/export.json)
    key1=$(sed -e 's/^"//' -e 's/"$//' <<<"$key1")
    pass1=$(sed -e 's/^"//' -e 's/"$//' <<<"$pass1")
    clearpass=$(/root/join-trim.sh "${pass1}" "${key1}")
    log "Populated cred variables..."
fi

#create 3yr cert
log "Creating self-signed app cert"
cd /root/
openssl req -nodes -sha256 -newkey rsa:2048 -keyout app1.key -out app1.csr -subj "/C=US/ST=ST/L=Loc/O=Org/OU=OU/CN=app1"
openssl x509 -req -sha256 -days 1095 -in app1.csr -signkey app1.key -out app1.pem
cp app1.pem /etc/pki/tls/certs/

# Configure Apache to require app1 cert
log "Configuring Apache HTTP for cert auth"
cp /etc/httpd/conf.d/ssl.conf /etc/httpd/conf.d/ssl.conf.authbak
cd /etc/httpd/conf.d/

#add app1.pem as httpd trusted ca
log "Adding app1.pem single cert as Apache HTTP trusted ca for cert auth"
sed -i '/SSLCertificateKeyFile*/a SSLCACertificateFile \/etc\/pki\/tls\/certs\/app1.pem' /etc/httpd/conf.d/ssl.conf

#add virtualhost settings and auth requiring app1 cn
sed -i 's|</VirtualHost>|SSLVerifyClient require\nSSLVerifyDepth 1\n</VirtualHost>\n\n<Location "/">\nSSLOptions +FakeBasicAuth\nSSLRequireSSL\nSSLRequire %{SSL_CLIENT_S_DN_CN}  eq "app1"\n</Location>\n|' /etc/httpd/conf.d/ssl.conf

#restart httpd
log "Restarting Apache HTTP"
service httpd restart

#create p12
if [ ! -z "${clearpass}" ]
then
    log "Exporting cert for later pickup"
    openssl pkcs12 -export -in /root/app1.pem -inkey /root/app1.key -out /root/app1.p12 -password pass:"${clearpass}"
fi

#todo upload p12 to ?
