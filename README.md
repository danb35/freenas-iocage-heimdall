# freenas-iocage-heimdall
Script to create a FreeNAS jail and install [Heimdall Dashboard](https://heimdall.site/) in it

# Installation
Change to a convenient directory, clone the repository using `git clone https://github.com/danb35/freenas-iocage-heimdall`, change to the freenas-iocage-heimdall directory, and create a configuration file called `heimdall-config` with your favorite text editor (if you don't have a favorite text editor, `nano` is a good choice--run `nano heimdall-config`).  Then run the script with `script heimdall.log ./heimdall-jail.sh`.

## Configuration options
In its minimal form, the configuration file would look like this:
```
JAIL_IP="192.168.1.78"
DEFAULT_GW_IP="192.168.1.1"
POOL_PATH="/mnt/tank"
```

* JAIL_IP:  The IP address to assign the jail.  You may optionally specify a netmask in CIDR notion.  If none is specified, the default is /24.  Values of less than 8 bits or more than 30 bits will also result in a 24-bit netmask.
* DEFAULT_GW_IP:  The IP address of your default gateway.
* POOL_PATH:  The path to your main data pool (e.g., `/mnt/tank`).  The Caddyfile and Heimdall installation files (i.e., the web pages themselves) will be stored there, in $POOL_PATH/apps/heimdall.  If you have more than one pool, choose the one you want to use for this purpose.
* FILE:  Optional.  The filename to download, which identifies the version of Heimdall to download.  Default is 2.2.2.  To check for a more recent release, see the [Heimdall release page](https://github.com/linuxserver/Heimdall/releases).
* DNS_PLUGIN:  Optional.  If you want to compile Caddy using a DNS validation plugin, specify it here.  To see the available plugins, go to the [Caddy download page](https://caddyserver.com/download).  Only enter the actual name of the plugin--e.g., if the plugin is listed with a package name of `github.com/caddy-dns/cloudflare`, enter only `cloudflare`.  **Note:** This will not configure the installation to use this plugin--you'll still need to handle that in your Caddyfile.  It will, however, make the plugin available.
* JAIL_NAME:  Optional.  The name of the jail.  If not given, will default to "heimdall".

## Post-install configuration
This script uses the [Caddy](https://caddyserver.com/) web server, which supports automatic HTTPS, reverse proxying, and many other powerful features.  It is configured using a Caddyfile, which is stored at `/usr/local/www/Caddyfile` in your jail, and under `/apps/heimdall/` on your main data pool.  You can edit it as desired to enable these or other features.  For further information, see [my Caddy script](https://github.com/danb35/freenas-iocage-caddy), specifically the included `Caddyfile.example`, or the [Caddy docs](https://caddyserver.com/docs/caddyfile).

# Support
Questions and discussion should be directed to https://forum.freenas-community.org/t/install-heimdall-dashboard-in-a-jail-script-freenas-11-2/35
