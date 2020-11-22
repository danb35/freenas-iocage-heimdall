#!/bin/sh

# Install Heimdall Dashboard (https://github.com/linuxserver/Heimdall)
# in a FreeNAS jail

# https://forum.freenas-community.org/t/install-heimdall-dashboard-in-a-jail-script-freenas-11-2/35

# Set these variables as appropriate
# FILE should be set to the version number of the latest release, with .tar.gz added
JAIL_NAME="heimdall"
JAIL_IP=192.168.1.204
DEFAULT_GW_IP=192.168.1.1
CERT_EMAIL="nobody@example.com"
FILE="2.2.2.tar.gz"

# Don't change anything below here
RELEASE=$(freebsd-version | cut -d - -f -1)"-RELEASE"
mountpoint=$(zfs get -H -o value mountpoint $(iocage get -p)/iocage)

# Create the jail, pre-installing needed packages
cat <<__EOF__ >/tmp/pkg.json
{
  "pkgs":[
  "nano", "caddy", "php72", "php72-mbstring", "php72-zip", "php72-tokenizer", 
  "php72-openssl", "php72-pdo", "php72-pdo_sqlite", "php72-filter", "php72-xml", 
  "php72-ctype", "php72-json", "sqlite3", "php72-session", "php72-hash"
  ]
}
__EOF__

if ! iocage create --name "${JAIL_NAME}" -p /tmp/pkg.json -r "${RELEASE}" \
  ip4_addr="vnet0|${JAIL_IP}/24" defaultrouter="${DEFAULT_GW_IP}" boot="on" \
  host_hostname="${JAIL_NAME}" vnet="on"
then
	echo "Failed to create jail"
	exit 1
fi
rm /tmp/pkg.json

iocage exec "${JAIL_NAME}" mkdir -p /usr/local/www/html
iocage exec "${JAIL_NAME}" fetch -o /tmp https://github.com/linuxserver/Heimdall/archive/"${FILE}"
iocage exec "${JAIL_NAME}" tar zxf /tmp/"${FILE}" --strip 1 -C /usr/local/www/html/
iocage exec "${JAIL_NAME}" mkdir -p /usr/local/www/html/storage/app/public/icons
iocage exec "${JAIL_NAME}" chown -R www:www /usr/local/www/html/
iocage exec "${JAIL_NAME}" sh -c 'find /usr/local/www/ -type d -print0 | xargs -0 chmod 2775'
iocage exec "${JAIL_NAME}" touch /usr/local/www/html/database/app.sqlite
iocage exec "${JAIL_NAME}" chmod 664 /usr/local/www/html/database/app.sqlite
iocage exec "${JAIL_NAME}" sysrc php_fpm_enable=YES
iocage exec "${JAIL_NAME}" sysrc caddy_enable=YES
iocage exec "${JAIL_NAME}" sysrc caddy_cert_email="${CERT_EMAIL}"

# Create Caddyfile
cat <<__EOF__ >"${mountpoint}"/jails/"${JAIL_NAME}"/root/usr/local/www/Caddyfile
*:80 {
gzip
root /usr/local/www/html/public
        fastcgi / 127.0.0.1:9000 php {
                env PATH /bin
        }
rewrite {
  r .*
  ext / .config
  to /index.php/{query}
}
}
__EOF__

iocage exec "${JAIL_NAME}" cp /usr/local/www/html/.env.example /usr/local/www/html/.env
iocage exec "${JAIL_NAME}" sh -c 'cd /usr/local/www/html/ && php artisan key:generate'
iocage exec "${JAIL_NAME}" service php-fpm start
iocage exec "${JAIL_NAME}" service caddy start
