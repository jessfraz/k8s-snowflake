#!/bin/bash
set -e
set -o pipefail

# From https://github.com/kubernetes/kubernetes/releases
# OR
# curl -sSL https://storage.googleapis.com/kubernetes-release/release/stable.txt
KUBERNETES_VERSION=v1.8.3

# From https://github.com/containernetworking/plugins/releases
# OR
# curl -sSL https://api.github.com/repos/containernetworking/plugins/releases/latest | jq .tag_name
CNI_VERSION=v0.6.0

# From https://github.com/Azure/azure-container-networking/releases
# OR
# curl -sSL https://api.github.com/repos/Azure/azure-container-networking/releases/latest | jq .tag_name
AZURE_CNI_VERSION=v0.91

# From https://github.com/kubernetes-incubator/cri-containerd/releases
# OR
# curl -sSL https://api.github.com/repos/kubernetes-incubator/cri-containerd/releases/latest | jq .tag_name
CRI_CONTAINERD_VERSION=1.0.0-alpha.1

install_cni() {
	local download_uri="https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-amd64-${CNI_VERSION}.tgz"
	local cni_bin="/opt/cni/bin"

	# make the needed directories
	mkdir -p "$cni_bin" /etc/cni/net.d

	curl -sSL "$download_uri" | tar -xz -C "$cni_bin"

	chmod +x "${cni_bin}"/*
	# touch /etc/hosts if it does not already exist (in case you ain't running clear linux on Azure)
	if [[ ! -f /etc/hosts ]]; then
		touch /etc/hosts
	fi
}

install_azure_cni() {
	local download_uri="https://github.com/Azure/azure-container-networking/releases/download/${AZURE_CNI_VERSION}/azure-vnet-cni-linux-amd64-${AZURE_CNI_VERSION}.tgz"
	local cni_bin="/opt/cni/bin"
	local cni_opt="/etc/cni/net.d"

	# make the needed directories
	mkdir -p "$cni_bin" "$cni_opt"

	curl -sSL "$download_uri" | tar -xz -C "$cni_bin"

	# move config file
	mv "${cni_bin}/10-azure.conf" "$cni_opt"
	chmod 600 "${cni_opt}/10-azure.conf"

	# remove bridge config
	rm "${cni_opt}/10-bridge.conf"

	chmod +x "${cni_bin}"/*

	# Dump ebtables rules.
	/sbin/ebtables -t nat --list

	# touch /etc/hosts if it does not already exist
	if [[ ! -f /etc/hosts ]]; then
		touch /etc/hosts
	fi
}

install_cri_containerd() {
	# TODO: fix this when this is merged https://github.com/kubernetes-incubator/cri-containerd/pull/415
	# local download_uri="https://github.com/kubernetes-incubator/cri-containerd/releases/download/v${CRI_CONTAINERD_VERSION}/cri-containerd-${CRI_CONTAINERD_VERSION}.tar.gz"
	local download_uri="https://misc.j3ss.co/tmp/cri-containerd-${CRI_CONTAINERD_VERSION}-dirty.tar.gz"

	curl -sSL "$download_uri" | tar -xz -C /
}

install_kubernetes_components() {
	local download_uri="https://storage.googleapis.com/kubernetes-release/release/${KUBERNETES_VERSION}/bin/linux/amd64"

	curl -sSL "${download_uri}/kube-proxy" > /usr/bin/kube-proxy
	curl -sSL "${download_uri}/kubelet" > /usr/bin/kubelet
	curl -sSL "${download_uri}/kubectl" > /usr/bin/kubectl

	chmod +x /usr/bin/kube*

	# make the needed directories
	mkdir -p /var/lib/kubernetes /var/run/kubernetes /var/lib/kubelet /var/lib/kube-proxy
}

configure() {
	# get the hostname
	hostname=$(hostname -s)
	# get the worker number
		worker=$(echo "$hostname" | grep -Eo '[0-9]+$')
	pod_cidr="10.200.${worker}.0/24"

	# update the cni bridge conf file
	if [[ -f /etc/cni/net.d/10-bridge.conf ]]; then
		sed -i "s#POD_CIDR#${pod_cidr}#g" /etc/cni/net.d/10-bridge.conf
	fi

	# update the kubelet systemd service file
	sed -i "s#POD_CIDR#${pod_cidr}#g" /etc/systemd/system/kubelet.service
	sed -i "s/HOSTNAME/${hostname}/g" /etc/systemd/system/kubelet.service

	# update the kube-proxy systemd service file
	sed -i "s#POD_CIDR#${pod_cidr}#g" /etc/systemd/system/kube-proxy.service
	sed -i "s/HOSTNAME/${hostname}/g" /etc/systemd/system/kube-proxy.service

	systemctl daemon-reload
	systemctl enable containerd cri-containerd kubelet kube-proxy
	systemctl start containerd cri-containerd kubelet kube-proxy
}

install_kubernetes_worker(){
	# TODO: remove this when you switch to container os on google cloud
	if [[ "$CLOUD_PROVIDER" == "google" ]]; then
		sudo apt-get -y install socat
	fi
	if [[ "$CLOUD_PROVIDER" == "vagrant" ]]; then
		sudo apt-get -y install socat
	fi

	install_cni
	if [[ "$CLOUD_PROVIDER" == "azure" ]]; then
		install_azure_cni
	fi

	install_cri_containerd
	install_kubernetes_components
	configure
}

install_kubernetes_worker
