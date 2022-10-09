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
* FILE:  Optional.  The filename to download, which identifies the version of Heimdall to download.  Default is 2.4.9.  To check for a more recent release, see the [Heimdall release page](https://github.com/linuxserver/Heimdall/releases).  As of this writing (2 April 2022), updates are very frequent; if a more recent version has been released, set this variable to the full file name of the download, e.g., `FILE="v2.5.1.tar.gz"`.
* JAIL_NAME:  Optional.  The name of the jail.  If not given, will default to "heimdall".

## Post-install configuration
This script uses the [Caddy](https://caddyserver.com/) web server, which supports automatic HTTPS, reverse proxying, and many other powerful features.  It is configured using a Caddyfile, which is stored at `/usr/local/www/Caddyfile` in your jail, and under `/apps/heimdall/` on your main data pool.  You can edit it as desired to enable these or other features.  For further information, see [my Caddy script](https://github.com/danb35/freenas-iocage-caddy), specifically the included `Caddyfile.example`, or the [Caddy docs](https://caddyserver.com/docs/caddyfile).

This script installs Caddy from the FreeBSD binary package, which does not include any [DNS validation plugins](https://caddyserver.com/download).  If you need to use these, you'll need to build Caddy from source.  The tools to do this are installed in the jail.  To build Caddy, run these commands:
```
go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
cp /root/go/bin/xcaddy /usr/local/bin/xcaddy
xcaddy build --output /usr/local/bin/caddy --with github.com/caddy-dns/${DNS_PLUGIN}
```
...with `${DNS_PLUGIN}` representing the name of the plugin, listed on the page linked above.  You'll then need to modify your configuration as described in the Caddy docs.

## Self-signed or local CA
If you're using self-signed certs, or a local certificate authority, for any of your local resources, you'll need to add the relevant root certificate to the trust store for your jail, or Heimdall won't be able to communicate securely with those resources.  To do this,

* Enter the jail with `iocage console heimdall`
* Place a copy of the cert in `/usr/share/certs/trusted/(descriptive cert name).pem`.
* `cd /etc/ssl/certs`
* `openssl x509 -noout -hash -in /usr/share/certs/trusted/(descriptive cert name).pem`
* This will return a hash value like `e94f1467`
* `ln -s /usr/share/certs/trusted/(descriptive cert name).pem (hash value).0`
* Exit and restart the jail

# Support
Questions and discussion should be directed to https://forum.freenas-community.org/t/install-heimdall-dashboard-in-a-jail-script-freenas-11-2/35
