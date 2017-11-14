#!/bin/bash
#
# This script generates certificates for nodes.
# It takes in an array of instance names and creates
# ca, client, and server certificates.
#
# Outputs: the temporary directory where the certificates can be found.
#
set -e
set -o pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CA_CONFIG_DIR="${DIR}/../ca"

generate_certificates() {
	instances=( "$@" )

	tmpdir=$(mktmp -d)

	# create the certificates in a temporary directory
	cd "$tmpdir"

	# generate the CA certificate and private key
	# 	outputs: ca-key.pem ca.pem
	cfssl gencert -initca "${CA_CONFIG_DIR}/csr.json" | cfssljson -bare ca

	# create the client and server certificates

	# create the admin client cert
	# 	outputs: admin-key.pem admin.pem
	cfssl gencert \
		-ca="${tmpdir}/ca.pem" \
		-ca-key="${tmpdir}/ca-key.pem" \
		-config="$CA_CONFIG_DIR}/config.json" \
		-profile=kubernetes \
		"${CA_CONFIG_DIR}/admin-csr.json" | cfssljson -bare admin

	# create the kubelet client certificates
	# 	outputs: worker-0-key.pem worker-0.pem worker-1-key.pem worker-1.pem...
	config_tmpdir=$(mktmp -d)
	for instance in "${instances[@]}"; do
		instance_csr_config="${config_tmpdir}/${instance}-csr.json"
		sed "s/INSTANCE/${instance}/g" "${CA_CONFIG_DIR}/instance-csr.json" > "$instance_csr_config"

		# get the external ip for the instance
		# this is cloud provider specific
		# Google
		# external_ip=$(gcloud compute instances describe "$instance" --format 'value(networkInterfaces[0].accessConfigs[0].natIP)')
		# Azure
		external_ip=$(az vm show -g "$RESOURCE_GROUP" -n "$instance" --show-details --query 'publicIps' -o tsv)

		# get the internal ip for the instance
		# this is cloud provider specific
		# Google
		# internal_ip=$(gcloud compute instances describe "$instance" --format 'value(networkInterfaces[0].networkIP)')
		# Azure
		internal_ip=$(az vm show -g "$RESOURCE_GROUP" -n "$instance" --show-details --query 'privateIps' -o tsv)

		# generate the certificates
		cfssl gencert \
			-ca="${tmpdir}/ca.pem" \
			-ca-key="${tmpdir}/ca-key.pem" \
			-config="$CA_CONFIG_DIR}/config.json" \
			-hostname="${instance},${external_ip},${internal_ip}" \
			-profile=kubernetes \
			"$instance_csr_config" | cfssljson -bare "$instance"
	done

	# create the kube-proxy client certificate
	# 	outputs: kube-proxy-key.pem kube-proxy.pem
	cfssl gencert \
		-ca="${tmpdir}/ca.pem" \
		-ca-key="${tmpdir}/ca-key.pem" \
		-config="$CA_CONFIG_DIR}/config.json" \
		-profile=kubernetes \
		"${CA_CONFIG_DIR}/kube-proxy-csr.json" | cfssljson -bare kube-proxy

	# get the controller node public ip address
	# this is cloud provider specific
	# Google
	# public_address=$(gcloud compute addresses describe "$CONTROLLER_NODE_NAME" --region "$(gcloud config get-value compute/region)" --format 'value(address)')
	# Azure
	public_address=$(az network public-ip show -g "$RESOURCE_GROUP" --name "k8s-public-ip" --query 'ipAddress' -o tsv)

	# create the kube-apiserver client certificate
	# 	outputs: kubernetes-key.pem kubernetes.pem
	cfssl gencert \
		-ca="${tmpdir}/ca.pem" \
		-ca-key="${tmpdir}/ca-key.pem" \
		-config="$CA_CONFIG_DIR}/config.json" \
		-hostname="10.32.0.1,10.240.0.10,10.240.0.11,10.240.0.12,${public_address},127.0.0.1,kubernetes.default" \
		-profile=kubernetes \
		"${CA_CONFIG_DIR}/kubernetes-csr.json" | cfssljson -bare kubernetes

	echo "$tmpdir"
}

generate_certificates "$@"
