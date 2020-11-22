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
FILE="2.2.2.tar.gz"
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
mountpoint=$(zfs get -H -o value mountpoint $(iocage get -p)/iocage)

# Create the jail, pre-installing needed packages
cat <<__EOF__ >/tmp/pkg.json
{
  "pkgs":[
  "nano", "php73", "php73-mbstring", "php73-zip", "php73-tokenizer", 
  "php73-openssl", "php73-pdo", "php73-pdo_sqlite", "php73-filter", "php73-xml", 
  "php73-ctype", "php73-json", "sqlite3", "php73-session", "php73-hash",
  "go", "git"
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
iocage fstab -a "${JAIL_NAME}" "${POOL_PATH}"/apps/heimdall /usr/local/www nullfs rw 0 0

# Build xcaddy, use it to build Caddy
if ! iocage exec "${JAIL_NAME}" "go get -u github.com/caddyserver/xcaddy/cmd/xcaddy"
then
  echo "Failed to get xcaddy, terminating."
  exit 1
fi
if ! iocage exec "${JAIL_NAME}" go build -o /usr/local/bin/xcaddy github.com/caddyserver/xcaddy/cmd/xcaddy
then
  echo "Failed to build xcaddy, terminating."
  exit 1
fi
if [ -n "${DNS_PLUGIN}" ]; then
  if ! iocage exec "${JAIL_NAME}" xcaddy build --output /usr/local/bin/caddy --with github.com/caddy-dns/"${DNS_PLUGIN}"
  then
    echo "Failed to build Caddy with ${DNS_PLUGIN} plugin, terminating."
    exit 1
  fi  
else
  if ! iocage exec "${JAIL_NAME}" xcaddy build --output /usr/local/bin/caddy
  then
    echo "Failed to build Caddy without plugin, terminating."
    exit 1
  fi  
fi

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

# Create Caddyfile
cat <<__EOF__ >"${mountpoint}"/jails/"${JAIL_NAME}"/root/usr/local/www/Caddyfile
*:80 {
	encode gzip

	log {
		output file /var/log/heimdall_access.log
		format single_field common_log
	}

	root * /usr/local/www/html/public
	file_server

	php_fastcgi 127.0.0.1:9000

	# Add reverse proxy directives here if desired

}
__EOF__

# Create Caddy rc script
cat <<__EOF__ >"${mountpoint}"/jails/"${JAIL_NAME}"/root/usr/local/etc/rc.d/caddy
#!/bin/sh
#
# $FreeBSD$
#

# PROVIDE: caddy
# REQUIRE: LOGIN DAEMON NETWORKING
# KEYWORD: shutdown

# Add the following lines to /etc/rc.conf.local or /etc/rc.conf
# to enable this service:
# caddy_enable (bool):   Set to NO by default. Set it to YES to enable caddy.
#
# caddy_config (string): Optional full path for caddy config file
# caddy_adapter (string):  Optional adapter type if the configuration is not in caddyfile format
# caddy_extra_flags (string):  Optional flags passed to caddy start
# caddy_logfile (string):     Set to "/var/log/caddy.log" by default.
#                             Defines where the process log file is written, this is not a web access log

. /etc/rc.subr

name=caddy
rcvar=caddy_enable
desc="Caddy 2 is a powerful, enterprise-ready, open source web server with automatic HTTPS written in Go"

load_rc_config $name

# Defaults
: ${caddy_enable:=NO}
: ${caddy_config:="/usr/local/etc/Caddyfile"}
: ${caddy_adapter:=caddyfile}
: ${caddy_extra_flags:=""}
: ${caddy_logfile="/var/log/caddy.log"}

command="/usr/local/bin/${name}"
caddy_flags="--config ${caddy_config} --adapter ${caddy_adapter}"
pidfile="/var/run/${name}.pid"

required_files="${caddy_config} ${command}"

# Extra Commands
extra_commands="validate reload"
start_cmd="${command} start ${caddy_flags} ${caddy_extra_flags} --pidfile ${pidfile} >> ${caddy_logfile} 2>&1"
validate_cmd="${command} validate ${caddy_flags}"
reload_cmd="${command} reload ${caddy_flags}"

run_rc_command "$1"
__EOF__

iocage exec "${JAIL_NAME}" chmod +x /usr/local/etc/rc.d/caddy

iocage exec "${JAIL_NAME}" cp /usr/local/www/html/.env.example /usr/local/www/html/.env
iocage exec "${JAIL_NAME}" sh -c 'cd /usr/local/www/html/ && php artisan key:generate'
iocage exec "${JAIL_NAME}" service php-fpm start
iocage exec "${JAIL_NAME}" service caddy start
