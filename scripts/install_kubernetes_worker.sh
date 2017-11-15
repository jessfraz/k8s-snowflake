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
}

install_cri_containerd() {
	# TODO: fix this
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
	# get the pod cidr range
	# this is different per cloud service
	# Google
	# pod_cidr=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/attributes/pod-cidr)
	# Azure
	address=$(curl -H "Metadata:true" "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/subnet/0/address?api-version=2017-08-01&format=text")
	prefix=$(curl -H "Metadata:true" "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/subnet/0/prefix?api-version=2017-08-01&format=text")
	pod_cidr="${address}/${prefix}"

	# get the hostname
	hostname=$(hostname -s)

	# update the cni bridge conf file
	sed -i "s#POD_CIDR#${pod_cidr}#g" /etc/cni/net.d/10-bridge.conf

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
	install_cni
	install_cri_containerd
	install_kubernetes_components
	configure
}

install_kubernetes_worker
