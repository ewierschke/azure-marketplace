#!/bin/bash
# Description:
# Configure HTTPD on CentOS 7 as reverse proxy to parameter defined port 
# listening on 443 with self signed cert
#################################################################

usage()
{
    cat << EOT
  Usage:  ${__ScriptName} [options]

  Note:
  If no options are specified, then httpd will be configured as a reverse proxy
  to port 80.

  Options:
  -h  Display this message.
  -P  Backend port serving web application from which httpd should proxy
EOT
}  # ----------  end of function usage  ----------


# Define default values
REV_PROXY_TOPORT=

# Parse command-line parameters
while getopts :h:P: opt
do
    case "${opt}" in
        h)
            usage
            exit 0
            ;;
        P)
            REV_PROXY_TOPORT="${OPTARG}"
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
if [ -z "${REV_PROXY_TOPORT}" ]
then
    echo "No REV_PROXY_TOPORT (-P) was provided, configuring for port 80"
    REV_PROXY_TOPORT=80
fi

revproxport=${REV_PROXY_TOPORT}
myipwspace=$(hostname -I)
myip=$(echo "${myipwspace}" | awk '{gsub(/^ +| +$/,"")} {print $0}')
shortname=$(hostname -s)

# Build self signed cert for use on apache httpd as proxy
echo "Installing deps"
yum -y install mod_ssl openssl httpd
service httpd start
chkconfig httpd on
echo "Open firewall for https"
firewall-cmd --zone=public --permanent --add-service https
firewall-cmd --zone=public --add-service https

# Gotta make SELinux happy...
echo "Configuring SELinux"
if [[ $(getenforce) = "Enforcing" ]] || [[ $(getenforce) = "Permissive" ]]
then
    if [[ $(getsebool httpd_can_network_relay | \
        cut -d ">" -f 2 | sed 's/[ ]*//g') = "off" ]]
    then
        echo "Enabling httpd-based proxying within SELinux"
        setsebool -P httpd_can_network_relay=1
        setsebool -P httpd_can_network_connect=1
    fi
fi

#create 3yr cert
echo "Creating self-signed cert"
cd /root/
openssl req -nodes -sha256 -newkey rsa:2048 -keyout selfsigned.key -out selfsigned.csr -subj "/C=US/ST=ST/L=Loc/O=Org/OU=OU/CN=${shortname}"
openssl x509 -req -sha256 -days 1095 -in selfsigned.csr -signkey selfsigned.key -out selfsigned.crt
cp selfsigned.crt /etc/pki/tls/certs/
cp selfsigned.key /etc/pki/tls/private/
cp selfsigned.csr /etc/pki/tls/private/
# Configure Apache to use self signed cert
echo "Configuring Apache HTTP"
mv /etc/httpd/conf.d/ssl.conf /etc/httpd/conf.d/ssl.conf.bak
cd /etc/httpd/conf.d/

echo "Writing new /etc/httpd/conf.d/ssl.conf"
(
    printf "LoadModule ssl_module modules/mod_ssl.so\n"
    printf "\n"
    printf "Listen %s" "${myip}"
    printf ":443\n"
    printf "\n"
    printf "SSLPassPhraseDialog  builtin\n"
    printf "\n"
    printf "SSLSessionCache         shmcb:/var/cache/mod_ssl/scache(512000)\n"
    printf "SSLSessionCacheTimeout  300\n"
    printf "\n"
    printf "SSLRandomSeed startup file:/dev/urandom  256\n"
    printf "SSLRandomSeed connect builtin\n"
    printf "SSLCryptoDevice builtin\n"
    printf "\n"
    printf "<VirtualHost _default_:443>\n"
    printf "ErrorLog logs/ssl_error_log\n"
    printf "TransferLog logs/ssl_access_log\n"
    printf "LogLevel warn\n"
    printf "SSLEngine On\n"
    printf "\n"
    printf "SSLCertificateFile /etc/pki/tls/certs/selfsigned.crt\n"
    printf "SSLCertificateKeyFile /etc/pki/tls/private/selfsigned.key\n"
    printf "\n"
    printf "BrowserMatch \".*MSIE.*\" nokeepalive ssl-unclean-shutdown downgrade-1.0 force-response-1.0\n"
    printf "\n"
    printf "ServerName %s\n" "${shortname}"
    printf "ServerAlias %s\n" "${shortname}"
    printf "\n"
    printf "ProxyRequests Off\n"
    printf "ProxyPreserveHost On\n"
    printf "ProxyPass / http://%s" "${myip}"
    printf ":%s/\n" "${revproxport}"
    printf "ProxyPassReverse / http://%s" "${myip}"
    printf ":%s/\n" "${revproxport}"
    printf "\n"
    printf "</VirtualHost>\n"
    printf "\n"
    printf "SSLCipherSuite EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH:!aNULL:!eNULL:!EXPORT:!DES:!MD5:!PSK:!RC4\n"
    printf "SSLProtocol All -SSLv2 -SSLv3\n"
    printf "SSLHonorCipherOrder On\n"
    printf "Header always set Strict-Transport-Security \"max-age=63072000; includeSubdomains; preload\"\n"
    printf "Header always set X-Frame-Options DENY\n"
    printf "Header always set X-Content-Type-Options nosniff\n"
    printf "SSLCompression off\n"
    printf "SSLUseStapling on\n"
    printf "SSLStaplingCache \"shmcb:logs/stapling-cache(150000)\"\n"
) > /etc/httpd/conf.d/ssl.conf
chmod 644 /etc/httpd/conf.d/ssl.conf

systemctl enable httpd
