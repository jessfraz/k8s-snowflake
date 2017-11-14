#!/bin/bash
#
# This script generates certificates for nodes.
#
set -e
set -o pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CA_CONFIG_DIR="${DIR}/../ca"

# From https://pkg.cfssl.org/
CFSSL_VERSION="1.2"

install_cfssl() {
	# exit early if we already have cfssl installed
	command -v cfssljson >/dev/null 2>&1 && { echo "cfssl & cfssljson are already installed. Skipping installation."; return 0; }

	local download_uri="https://pkg.cfssl.org/R${CFSSL_VERSION}"

	sudo curl -sSL "${download_uri}/cfssl_linux-amd64" -o /usr/local/bin/cfssl
	sudo curl -sSL "${download_uri}/cfssljson_linux-amd64" -o /usr/local/bin/cfssljson

	sudo chmod +x /usr/local/bin/cfssl*

	echo "Successfully installed cfssl & cfssljson!"
}

generate_certificates() {
	tmpdir=$(mktemp -d)

	# create the certificates in a temporary directory
	cd "$tmpdir"

	# generate the CA certificate and private key
	# 	outputs: ca-key.pem ca.pem
	echo "Generating CA certificate and private key..."
	cfssl gencert -initca "${CA_CONFIG_DIR}/csr.json" | cfssljson -bare ca

	# create the client and server certificates

	# create the admin client cert
	# 	outputs: admin-key.pem admin.pem
	echo "Generating admin client certificate..."
	cfssl gencert \
		-ca="${tmpdir}/ca.pem" \
		-ca-key="${tmpdir}/ca-key.pem" \
		-config="${CA_CONFIG_DIR}/config.json" \
		-profile=kubernetes \
		"${CA_CONFIG_DIR}/admin-csr.json" | cfssljson -bare admin

	# create the kubelet client certificates
	# 	outputs: worker-0-key.pem worker-0.pem worker-1-key.pem worker-1.pem...
	for i in $(seq 1 "$WORKERS"); do
		instance="worker-node-${i}"
		instance_csr_config="${tmpdir}/${instance}-csr.json"
		sed "s/INSTANCE/${instance}/g" "${CA_CONFIG_DIR}/instance-csr.json" > "$instance_csr_config"

		# get the external ip for the instance
		# this is cloud provider specific
		# Google
		# external_ip=$(gcloud compute instances describe "$instance" --format 'value(networkInterfaces[0].accessConfigs[0].natIP)')
		# Azure
		external_ip=$(az vm show -g "$RESOURCE_GROUP" -n "$instance" --show-details --query 'publicIps' -o tsv | tr -d '[:space:]')

		# get the internal ip for the instance
		# this is cloud provider specific
		# Google
		# internal_ip=$(gcloud compute instances describe "$instance" --format 'value(networkInterfaces[0].networkIP)')
		# Azure
		internal_ip=$(az vm show -g "$RESOURCE_GROUP" -n "$instance" --show-details --query 'privateIps' -o tsv | tr -d '[:space:]')

		# generate the certificates
		echo "Generating certificate for ${instance}..."
		cfssl gencert \
			-ca="${tmpdir}/ca.pem" \
			-ca-key="${tmpdir}/ca-key.pem" \
			-config="${CA_CONFIG_DIR}/config.json" \
			-hostname="${instance},${external_ip},${internal_ip}" \
			-profile=kubernetes \
			"$instance_csr_config" | cfssljson -bare "$instance"
	done

	# create the kube-proxy client certificate
	# 	outputs: kube-proxy-key.pem kube-proxy.pem
	echo "Generating kube-proxy client certificate..."
	cfssl gencert \
		-ca="${tmpdir}/ca.pem" \
		-ca-key="${tmpdir}/ca-key.pem" \
		-config="${CA_CONFIG_DIR}/config.json" \
		-profile=kubernetes \
		"${CA_CONFIG_DIR}/kube-proxy-csr.json" | cfssljson -bare kube-proxy

	# get the controller node public ip address
	# this is cloud provider specific
	# Google
	# public_address=$(gcloud compute addresses describe "$CONTROLLER_NODE_NAME" --region "$(gcloud config get-value compute/region)" --format 'value(address)')
	# Azure
	public_address=$(az network public-ip show -g "$RESOURCE_GROUP" --name "k8s-public-ip" --query 'ipAddress' -o tsv | tr -d '[:space:]')
	# get the controller internal ips
	internal_ips=$(az vm list-ip-addresses -g kubernetes-clear-linux -o table | grep controller | awk '{print $3}' | tr -d '[:space:]' | tr '\n' ',' | sed 's/,*$//g')

	# create the kube-apiserver client certificate
	# 	outputs: kubernetes-key.pem kubernetes.pem
	echo "Generating kube-apiserver client certificate..."
	cfssl gencert \
		-ca="${tmpdir}/ca.pem" \
		-ca-key="${tmpdir}/ca-key.pem" \
		-config="${CA_CONFIG_DIR}/config.json" \
		-hostname="${internal_ips},${public_address},127.0.0.1,kubernetes.default" \
		-profile=kubernetes \
		"${CA_CONFIG_DIR}/kubernetes-csr.json" | cfssljson -bare kubernetes

	export CERTIFICATE_TMP_DIR="$tmpdir"
	echo "Certs generated in CERTIFICATE_TMP_DIR env var: $CERTIFICATE_TMP_DIR"
}
