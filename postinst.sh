#!/bin/bash

#always exit cleanly, the virtualbox additions needed this quirk or otherwise it signaled an issue
function cleanup {
	exit 0
}
trap cleanup EXIT

#empty message of the day
echo -n "" > /etc/motd

#enable backports for wireguard in buster
echo 'deb http://deb.debian.org/debian buster-backports main contrib non-free' > /etc/apt/sources.list.d/buster-backports.list
apt update
apt install -y wireguard

#extract the tarball to the root directory, all extracted files will be owned by root:root
#directories that already exist will not be overwritten
tar --directory=/ --strip-components=1 --no-same-owner --owner=root --group=root --no-overwrite-dir --preserve-permissions --extract --gzip --file /tmp/files.tgz

#fix permissions and ownership
chown -R snxbox:snxbox /home/snxbox

exit 0
