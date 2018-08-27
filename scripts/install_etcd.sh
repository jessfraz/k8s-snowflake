#!/bin/bash
set -e
set -o pipefail

# From https://github.com/coreos/etcd/releases
# OR
# curl -sSL https://api.github.com/repos/coreos/etcd/releases/latest | jq .tag_name
ETCD_VERSION="v3.2.9"

install_etcd() {
	local download_uri="https://github.com/coreos/etcd/releases/download/${ETCD_VERSION}/etcd-${ETCD_VERSION}-linux-amd64.tar.gz"

	curl -sSL "$download_uri" | tar -v -C /usr/bin -xz --strip-components=1

	chmod +x /usr/bin/etcd*

	# make the needed directories
	mkdir -p /etc/etcd /var/lib/etcd

	# get the internal ip
	# this is cloud provider specific
	# Vagrant
	if grep vagrant ~/.ssh/authorized_keys > /dev/null; then
		internal_ip="172.17.8.100"
	fi
	# Google Cloud
	if [[ -z "$internal_ip" ]]; then
		internal_ip=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip || true)
	fi
	# Azure
	if [[ -z "$internal_ip" ]]; then
		internal_ip=$(curl -H "Metadata:true" "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/privateIpAddress?api-version=2017-08-01&format=text")
	fi

	# each etcd member must have a unique name within an etcd cluster
	# set the etcd name to match the hostname of the current compute instance
	etcd_name=$(hostname -s)

	# update the etcd systemd service file
	sed -i "s/INTERNAL_IP/${internal_ip}/g" /etc/systemd/system/etcd.service
	sed -i "s/ETCD_NAME/${etcd_name}/g" /etc/systemd/system/etcd.service

	systemctl daemon-reload
	systemctl enable etcd
	systemctl start etcd
}

install_etcd
