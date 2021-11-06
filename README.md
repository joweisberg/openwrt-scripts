# openwrt-scripts
 OpenWrt scripts for USB-3.0, WPA3, SFTP, SMB, NFS, DDNS, SQM QoS, Acme, OpenVPN, IKEv2/IPsec, adblock, watchcat, mSMTP

## Functionalities
- Create a generic script to install OpenWrt automatically on each releases
  - Wi-Fi ssid and password
  - Wi-Fi Guest setup
  - TimeZone [settings](http://openwrt/cgi-bin/luci/admin/system/system)
  - Dynamic DNS [settings](http://openwrt/cgi-bin/luci/admin/services/ddns)
  - DHCP Static Leases [settings](http://openwrt/cgi-bin/luci/admin/network/dhcp)
  - Host entries [settings](http://openwrt/cgi-bin/luci/admin/network/hosts)
  - Manage Firewall - Zone (wan/lan/guest/vpn) [settings](http://openwrt/cgi-bin/luci/admin/network/firewall)
  - Firewall - Port Forwards [settings](http://openwrt/cgi-bin/luci/admin/network/firewall/forwards)
- Manage USB-3.0 and UAS Storage
- Use USB Dongle LTE/4G as wan interface
- Enable WPA3 Wi-Fi security encryption - WPA2/WPA3 (PSK/SAE)

Legend
- :heavy_check_mark: include by default
- :question: optional depend on config env file

List of packages / services
  - SFTP fileserver :heavy_check_mark:
  - Samba SMB/CIFS fileserver :question:
  - NFS fileserver :question:
  - Dynamic DNS for external IP naming :heavy_check_mark:
  - SQM QoS (aka Smart Queue Management) :question:
  - Satistics with collectd :question:
  - Acme certificates and [script](https://raw.githubusercontent.com/Neilpang/acme.sh/master/acme.sh) :heavy_check_mark:
  - uHTTPd UI :heavy_check_mark:
  - OpenVPN :question:
    - Generate OpenVPN certificates files
    - Set server for clients to access to local network with local gateway (based on username/password)
    - Set server point Site-to-Site config with domain suffix capability (based on username/password)
    - Import existing client config file
  - IKEv2/IPsec VPN server with strongSwan :question:
    - Set server for clients to access to local network with local gateway (based on username/password)
  - adblock :heavy_check_mark:
  - Block ip addresses that track attacks, spyware, viruses :heavy_check_mark:
  - watchcat (periodic reboot or reboot on internet drop) :heavy_check_mark:
  - mSMTP :heavy_check_mark:

## How to use with OpenWrt

1. Backup current [config](http://openwrt/cgi-bin/luci/admin/system/flash) (*.tar.gz) and keep:
  - /etc/shadow to *keep the default login/password*
  - /etc/acme/<sub.domain.com> to *keep current Acme certificates*
  - /et/easy-rsa/pki to *keep current OpenVPN certificates*
2. Add this [repository](https://github.com/joweisberg/openwrt-scripts) files under /root folder on your .tar.gz backup file
3. **Create** your own **/root/opkg-install.env** file based the [example]((https://raw.githubusercontent.com/joweisberg/openwrt-scripts/main/opkg-install.env-example) and add it on your .tar.gz backup file (optional, can be done by script)
4. **Flash new firmware image** and **Restore** with your new .tar.gz backup file
5. Open ssh terminal to connect to OpenWrt and
```bash
$ ssh openwrt
```
6. Start the installation setup and follow the questions
```bash
$ /root/opkg-install.sh 2>&1 | tee /var/log/opkg-install.log
```

## Hardware tested / Firmware downloads
* [Linksys WRT1900ACS v2](https://openwrt.org/toh/views/toh_fwdownload?dataflt%5BModel*%7E%5D=WRT1900ACS)
* [TP-Link Archer C7 v2](https://openwrt.org/toh/views/toh_fwdownload?dataflt%5BModel*~%5D=Archer+c7&dataflt%5BVersions*~%5D=V2)
* [TP-Link Archer C7 v5](https://openwrt.org/toh/views/toh_fwdownload?dataflt%5BModel*~%5D=Archer+c7&dataflt%5BVersions*~%5D=V5)

### Supported OpenWrt build version

| OpenWrt release | My Branches/Tag | Supported / Tested |
| --- | --- | --- |
| [18.06](https://openwrt.org/releases/18.06/start) | [19.07](https://github.com/joweisberg/openwrt-scripts/tree/19.07) | :heavy_check_mark: |
| [19.07](https://openwrt.org/releases/19.07/start) | [19.07](https://github.com/joweisberg/openwrt-scripts/tree/19.07) | :heavy_check_mark: |
| [21.02](https://openwrt.org/releases/21.02/start) | [Current](https://github.com/joweisberg/openwrt-scripts) | :heavy_check_mark: |

## Requirements
- [SanDisk Ultra Fit 16Go Clé USB 3.1](https://www.amazon.fr/gp/product/B077Y149DL)
- [HUAWEI USB Dongle E3372H LTE/4G](https://www.amazon.fr/gp/product/B011BRKPLE) (optional)

## Steps available

1. Create and moving Rootfs & Swap on new USB storage
2. Rebuild Rootfs on existing USB storage
3. Start OpenWrt setup installation

## Usage
```bash
$ /root/opkg-install.sh 2>&1 | tee /var/log/opkg-install.log
```

## How to setup and use variables
[opkg-install.env-example](https://raw.githubusercontent.com/joweisberg/openwrt-scripts/main/opkg-install.env-example)

## USB default partitions architecture
| Device | Type | Label | Default size |
| --- | --- | --- | --- |
| sda |
| ├─sda1 | swap | | 2 x existing RAM with max of 512Mb |
| ├─sda2 | ext4 | rootfs_data | 4Go |
| └─sda3 | vfat | data | 10Go --> mount point /mnt/data |

---

### Screenshots

- :construction: TBD :construction:

---

### Output sample when "Create and moving Rootfs & Swap on new USB storage"

```bash
:construction: TBD :construction:
```

### Output sample when "Rebuild Rootfs on existing USB storage"

```bash
* Set access rights on uploaded files
*
* You are connected to the internet.
*
* Create and moving Rootfs & Swap on new USB storage? [y/N]
* Rebuild Rootfs on existing USB storage? [y/N] y
* Please unplug USB storage <enter to continue>...
* Checking for updates, please wait...
* Package USB 3.0 disk management
* Package ext4/FAT
* Package mounted partitions
* Package exFAT/ntfs
* Package hd-idle
* Package SFTP fileserver
* Package wget
* Install utilities packages
* Please plug back in USB storage <enter to continue>...
*
* List of available USB devices:
*
NAME   FSTYPE LABEL       UUID                                 FSAVAIL FSUSE% MOUNTPOINT
sda
├─sda1 swap
├─sda2 ext4   rootfs_data 98d50326-db8a-4314-ba22-2d91864e3381
└─sda3 vfat   data        8FC8-3FAD
sdb
└─sdb1 ext4   htpc-backup e7dd7bf0-2a4b-4d2a-9251-713479cdf1f3
*
* Enter swap device? </dev/sda1>
* Enter rootfs_data device? </dev/sda2>
*
* Format partitions on swap/ext4
*
* Partitions detail for /dev/sda:
NAME   FSTYPE LABEL       UUID                                 FSAVAIL FSUSE% MOUNTPOINT
sda
├─sda1 swap
├─sda2 ext4   rootfs_data 98d50326-db8a-4314-ba22-2d91864e3381
└─sda3 vfat   data        8FC8-3FAD
*
* Remove utilities packages
* UCI config fstab
* Enable all mounted partitions
* Please check mounted partitions http://openwrt/cgi-bin/luci/admin/system/mounts
* Copy /overlay on /dev/sda2 partition...
*
*
*
* Reboot to complete the Rootfs & Swap on USB Storage <enter to continue>...
```

### Output sample when "Start OpenWrt setup installation"

```bash
* Set access rights on uploaded files
*
* You are connected to the internet.
*
* Create and moving Rootfs & Swap on new USB storage? [y/N]
* Rebuild Rootfs on existing USB storage? [y/N]
*
* The current setup:
*
*
* Do you accept this setup? [Y/n]
* UCI config luci
* UCI config timezone
* UCI config lan network
* UCI config Guest network
* UCI config dhcp
* UCI config firewall
* UCI config firewall redirect
* UCI config firewall rule
* UCI config wireless
* UCI config dhcp static leases
* UCI config dhcp host
* UCI config dhcp domain
* Checking for updates, please wait...
* Package Advanced Reboot UI
* Package USB 3.0 disk management
* Package ext4/FAT/exFAT/ntfs
* Package mounted partitions
* UCI enable mounted partitions
* UCI mount partitions
* Package hd-idle
* UCI config hd-idle
* Package WPA2/WPA3 Personal (PSK/SAE) mixed mode
* UCI config WPA2/WPA3 (PSK/SAE)
* Package SFTP fileserver
* Package Samba SMB/CIFS fileserver for 'Network Shares'
* UCI config samba
* Set Samba as local master = yes
* Package NFS fileserver
* UCI config nfs
* Package Dynamic DNS for external IP naming
* UCI config ddns
* Package firewall rtsp nat helper
* Add firewall rtsp config
* Package SQM QoS (aka Smart Queue Management)
* UCI config SQM QoS
* Package for ACME script
* Install ACME script
[Mon Oct 18 06:55:59 UTC 2021] It is recommended to install socat first.
[Mon Oct 18 06:55:59 UTC 2021] We use socat for standalone server if you use standalone mode.
[Mon Oct 18 06:55:59 UTC 2021] If you don't use standalone mode, just ignore this warning.
[Mon Oct 18 06:55:59 UTC 2021] Installing to /etc/acme
cp: can't stat 'acme.sh': No such file or directory
[Mon Oct 18 06:55:59 UTC 2021] Install failed, can not copy acme.sh
[Mon Oct 18 06:56:00 UTC 2021] Installing from online archive.
[Mon Oct 18 06:56:00 UTC 2021] Downloading https://github.com/acmesh-official/acme.sh/archive/master.tar.gz
[Mon Oct 18 06:56:05 UTC 2021] Extracting master.tar.gz
[Mon Oct 18 06:56:14 UTC 2021] It is recommended to install socat first.
[Mon Oct 18 06:56:14 UTC 2021] We use socat for standalone server if you use standalone mode.
[Mon Oct 18 06:56:14 UTC 2021] If you don't use standalone mode, just ignore this warning.
[Mon Oct 18 06:56:14 UTC 2021] Installing to /etc/acme
[Mon Oct 18 06:56:14 UTC 2021] Installed to /etc/acme/acme.sh
[Mon Oct 18 06:56:20 UTC 2021] OK
[Mon Oct 18 06:56:20 UTC 2021] Install success!
[Mon Oct 18 06:56:27 UTC 2021] Upgrade success!
* Package Acme UI
* UCI config acme
* Get ACME certificates
[Mon Oct 18 06:56:34 UTC 2021] Domains not changed.
[Mon Oct 18 06:56:34 UTC 2021] Skip, Next renewal time is: Fri Nov  5 07:50:47 UTC 2021
[Mon Oct 18 06:56:34 UTC 2021] Add '--force' to force to renew.
* Package uHTTPd UI
* UCI config uHTTPd
* Package VPN client with OpenVPN
* Set OpenVPN config files
* Set OpenVPN certificates files with network & firewall config
* UCI config firewall for IKEv2/IPsec VPN server
* UCI config network/interface for IKEv2/IPsec VPN server
* UCI config network/zone for IKEv2/IPsec VPN server
* UCI config network/route for IKEv2/IPsec VPN server
* UCI config dhcp/dnsmasq for IKEv2/IPsec VPN server
* Link ACME cetificates for IKEv2/IPsec VPN server
* Package IKEv2/IPsec VPN server with strongSwan
* Set config files for IKEv2/IPsec VPN server with strongSwan
* UCI config remove default firewall - Traffic Rules for IKEv2/IPsec VPN server
* Package adblock
* UCI config adblock
* Block ip addresses that track attacks, spyware, viruses
* Enable crontab 'Scheduled Taks'
* Package watchcat (periodic reboot or reboot on internet drop)
* UCI config watchcat
* Package mSMTP mail client
* Set mSMTP account free,gmail
* Set timezone Europe/Paris
* Package wget
* Package iperf3
* Set iperf3 server at startup
* Add custom scripts
* Remove duplicated conffile
*
*
*
* Get ACME certificates command line to run, if necessary!
/etc/acme/acme.sh --home /etc/acme --upgrade > /etc/acme/log.txt 2>&1 && /root/fw-redirect.sh /root/fw-redirect.sh \'Allow-http\' on && /etc/acme/acme.sh --home /etc/acme --renew-all --standalone --force 2>&1 | tee -a /etc/acme/log.txt; /root/fw-redirect.sh \'Allow-http\' off && /usr/sbin/ipsec restart
*
*
*
* Reboot to complete the installation? [Y/n]
```
