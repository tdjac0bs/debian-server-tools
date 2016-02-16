#!/bin/bash --version
#
# Clone a server by reinstalling packages and copying settings.
#

exit 0

# Save on the "donor"

apt-get install -y debconf-utils
cd /var/backups/
# Create etc-blacklist.txt from these
echo "/etc/modprobe.d
/etc/network/interfaces
/etc/fstab
/etc/mdadm/mdadm.conf
/etc/udev
/etc/hostname
/etc/hosts
/etc/resolv.conf
/etc/mailname
/etc/courier/me" > exclude.list
while read -r F; do find ${F} -type f; done < exclude.list > etc-blacklist.txt
ls /etc/ssh/ssh_host_*_key* >> etc-blacklist.txt
debconf-get-selections > debconf.selections
dpkg --get-selections > packages.selection
tar --exclude-from=etc-blacklist.txt \
    -vczf server.tar.gz debconf.selections packages.selection etc-blacklist.txt /etc/*


# Restore on the "clone"

# Check hardware
clear; fdisk -l /dev/sd?
cat /proc/mdstat
pvdisplay && lvs
ifconfig

# Clean package cache
apt-get clean
rm -vrf /var/lib/apt/lists/*
apt-get clean
apt-get autoremove --purge -y

# Compare kernels
#scp server.tar.gz ${HOST}:
mkdir /root/clone; cd /root/clone/
tar -vxf ../server.tar.gz
clear; dpkg -l | grep -E "^\S+\s+linux-"
grep "^linux-image" packages.selection

# Remove systemd
apt-get update
apt-get purge -y rpcbind ntp dbus
apt-get install -y apt-transport-https apt-listchanges apt-utils dselect
dpkg -s systemd &> /dev/null && apt-get install -y sysvinit-core sysvinit-utils \
    && cp -v /usr/share/sysvinit/inittab /etc/inittab
read -r -s -p 'Ctrl + D to reboot ' || reboot
apt-get remove -y --purge --auto-remove systemd
echo -e 'Package: *systemd*\nPin: origin ""\nPin-Priority: -1' > /etc/apt/preferences.d/systemd

# Restore /etc
cd /root/clone/
chmod -c 0755 ./etc
mv -vf /etc/ /root/etc && mv -vf ./etc /
# Inspect changes in /etc
while read -r F; do diff -u "${F/etc/root/etc}" "$F"; done < etc-blacklist.txt | less
# Restore blacklisted files
cat etc-blacklist.txt | xargs -I%% cp -vf /root%% %%
# Recreate homes
sed -ne 's/^\(\S\+\):x:1[0-9][0-9][0-9]:.*$/\1/p' /etc/passwd | xargs -n1 mkhomedir_helper
#tar -C /home/ -xvf ../homes.tar.gz

# Check hardware again
clear; fdisk -l /dev/sd?
cat /proc/mdstat
pvdisplay && lvs
ifconfig

# Restore packages
dselect update
clear; debconf-set-selections < debconf.selections
# @FIXME Question type: error

# Package blacklist
grep -E "^(vmware|linux-image|mdadm|lvm|grub|systemd)" packages.selection
dpkg -l | grep -E "^\S+\s+(vmware|linux-image|mdadm|lvm|grub|systemd)"
# Match these with the currently installed packages
editor packages.selection

# Install packages
dpkg --clear-selections && dpkg --set-selections < packages.selection
apt-get dselect-upgrade -y

# Check installes files and SSH
debsums -c
dpkg -l | grep "ssh" || echo 'no SSH !!!'
netstat -anp | grep "ssh" || echo 'no SSH !!!'
ls -l /home/viktor/.ssh/

# Check services from server.yml

## Data dirs

/opt
/root
/srv
/usr/local
/var
/var/lib/mysql
/var/cache
/var/mail
/var/spool
/var/tmp
(recreate dirs ??? owner,perms)

## Special handling dirs

/var/mail
/var/lib/mysql
/media/backup
