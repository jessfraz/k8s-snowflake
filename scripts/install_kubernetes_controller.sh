#!/bin/bash
set -e
set -o pipefail

# From https://github.com/kubernetes/kubernetes/releases
# OR
# curl -sSL https://storage.googleapis.com/kubernetes-release/release/stable.txt
KUBERNETES_VERSION=v1.8.3

install_kubernetes_controller() {
	local download_uri="https://storage.googleapis.com/kubernetes-release/release/${KUBERNETES_VERSION}/bin/linux/amd64"

	curl -sSL "${download_uri}/kube-apiserver" > /usr/bin/kube-apiserver
	curl -sSL "${download_uri}/kube-controller-manager" > /usr/bin/kube-controller-manager
	curl -sSL "${download_uri}/kube-scheduler" > /usr/bin/kube-scheduler
	curl -sSL "${download_uri}/kubectl" > /usr/bin/kubectl

	chmod +x /usr/bin/kube*

	# make the needed directories
	mkdir -p /var/lib/kubernetes

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
	# update the kube-apiserver systemd service file
	sed -i "s/INTERNAL_IP/${internal_ip}/g" /etc/systemd/system/kube-apiserver.service

	# update the kube-controller-manager systemd service file
	sed -i "s/INTERNAL_IP/${internal_ip}/g" /etc/systemd/system/kube-controller-manager.service

	# update the kube-scheduler systemd service file
	sed -i "s/INTERNAL_IP/${internal_ip}/g" /etc/systemd/system/kube-scheduler.service

	systemctl daemon-reload
	systemctl enable kube-apiserver kube-controller-manager kube-scheduler
	systemctl start kube-apiserver kube-controller-manager kube-scheduler
}

install_kubernetes_controller
