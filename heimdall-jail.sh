#!/bin/sh

# Install Heimdall Dashboard (https://github.com/linuxserver/Heimdall)
# in a FreeNAS jail

# https://forum.freenas-community.org/t/install-heimdall-dashboard-in-a-jail-script-freenas-11-2/35

# Check for root privileges
if ! [ $(id -u) = 0 ]; then
   echo "This script must be run with root privileges"
   exit 1
fi

#####
#
# General configuration
#
#####

# Initialize defaults
JAIL_NAME="heimdall"
JAIL_IP=""
DEFAULT_GW_IP=""
POOL_PATH=""
FILE="v2.6.1.tar.gz"
DNS_PLUGIN=""
CONFIG_NAME="heimdall-config"

# Check for heimdall-config and set configuration
SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "${SCRIPT}")
if ! [ -e "${SCRIPTPATH}"/"${CONFIG_NAME}" ]; then
  echo "${SCRIPTPATH}/${CONFIG_NAME} must exist."
  exit 1
fi
. "${SCRIPTPATH}"/"${CONFIG_NAME}"

# Error checking and config sanity check
if [ -z "${JAIL_IP}" ]; then
  echo 'Configuration error: JAIL_IP must be set'
  exit 1
fi
if [ -z "${DEFAULT_GW_IP}" ]; then
  echo 'Configuration error: DEFAULT_GW_IP must be set'
  exit 1
fi
if [ -z "${POOL_PATH}" ]; then
  echo 'Configuration error: POOL_PATH must be set'
  exit 1
fi

# Extract IP and netmask, sanity check netmask
IP=$(echo ${JAIL_IP} | cut -f1 -d/)
NETMASK=$(echo ${JAIL_IP} | cut -f2 -d/)
if [ "${NETMASK}" = "${IP}" ]
then
  NETMASK="24"
fi
if [ "${NETMASK}" -lt 8 ] || [ "${NETMASK}" -gt 30 ]
then
  NETMASK="24"
fi

RELEASE=$(freebsd-version | cut -d - -f -1)"-RELEASE"
# If release is 13.1-RELEASE, change to 13.2-RELEASE
if [ "${RELEASE}" = "13.1-RELEASE" ]; then
  RELEASE="13.2-RELEASE"
fi

mountpoint=$(zfs get -H -o value mountpoint $(iocage get -p)/iocage)

# Create the jail, pre-installing needed packages
cat <<__EOF__ >/tmp/pkg.json
{
  "pkgs":[
  "nano", 
  "caddy", 
  "php82", 
  "php82-mbstring", 
  "php82-zip", 
  "php82-tokenizer", 
  "php82-pdo", 
  "php82-pdo_sqlite", 
  "php82-filter", 
  "php82-xml", 
  "php82-ctype", 
  "php82-dom",
  "php82-fileinfo",
  "sqlite3", 
  "php82-session", 
  "go", 
  "git"
  ]
}
__EOF__

if ! iocage create --name "${JAIL_NAME}" -p /tmp/pkg.json -r "${RELEASE}" \
  ip4_addr="vnet0|${IP}/${NETMASK}" defaultrouter="${DEFAULT_GW_IP}" boot="on" \
  host_hostname="${JAIL_NAME}" vnet="on"
then
	echo "Failed to create jail"
	exit 1
fi
rm /tmp/pkg.json

# Store Caddyfile and data outside the jail
mkdir -p "${POOL_PATH}"/apps/heimdall
iocage exec "${JAIL_NAME}" mkdir -p /usr/local/www/
iocage fstab -a "${JAIL_NAME}" "${POOL_PATH}"/apps/heimdall /usr/local/www nullfs rw 0 0

# Create Caddyfile
cat <<__EOF__ >"${mountpoint}"/jails/"${JAIL_NAME}"/root/usr/local/www/Caddyfile
:80 {
	encode gzip

	log {
		output file /var/log/heimdall_access.log
	}

	root * /usr/local/www/html/public
	file_server

	php_fastcgi 127.0.0.1:9000

	# Add reverse proxy directives here if desired

}
__EOF__

# Download and install Heimdall
iocage exec "${JAIL_NAME}" mkdir -p /usr/local/www/html
iocage exec "${JAIL_NAME}" fetch -o /tmp https://github.com/linuxserver/Heimdall/archive/"${FILE}"
iocage exec "${JAIL_NAME}" tar zxf /tmp/"${FILE}" --strip 1 -C /usr/local/www/html/
iocage exec "${JAIL_NAME}" mkdir -p /usr/local/www/html/storage/app/public/icons
iocage exec "${JAIL_NAME}" sh -c 'find /usr/local/www/ -type d -print0 | xargs -0 chmod 2775'
iocage exec "${JAIL_NAME}" touch /usr/local/www/html/database/app.sqlite
iocage exec "${JAIL_NAME}" chmod 664 /usr/local/www/html/database/app.sqlite
iocage exec "${JAIL_NAME}" chown -R www:www /usr/local/www/html/
iocage exec "${JAIL_NAME}" sysrc php_fpm_enable=YES
iocage exec "${JAIL_NAME}" sysrc caddy_enable=YES
iocage exec "${JAIL_NAME}" sysrc caddy_config=/usr/local/www/Caddyfile
iocage exec "${JAIL_NAME}" cp /usr/local/www/html/.env.example /usr/local/www/html/.env
iocage exec "${JAIL_NAME}" sh -c 'cd /usr/local/www/html/ && php artisan key:generate'
iocage exec "${JAIL_NAME}" service php-fpm start
iocage exec "${JAIL_NAME}" service caddy start
