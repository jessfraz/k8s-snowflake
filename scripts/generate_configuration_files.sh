#!/bin/bash
set -e
set -o pipefail

generate_configuration_files() {
	tmpdir=$(mktemp -d)

	# create the kubeconfigs in a temporary directory
	cd "$tmpdir"

	# get the controller node public ip address
	# this is cloud provider specific
	# Google Cloud
	if [[ "$CLOUD_PROVIDER" == "google" ]]; then
		internal_ip=$(gcloud compute addresses describe "$PUBLIC_IP_NAME" --region "$REGION" --format 'value(address)')
	fi
	# Azure
	if [[ "$CLOUD_PROVIDER" == "azure" ]]; then
		internal_ip=$(az vm list-ip-addresses -g "$RESOURCE_GROUP" -o table | grep controller | awk '{print $3}' | tr -d '[:space:]' | tr '\n' ',' | sed 's/,*$//g')
	fi
	# Vagrant
	if [[ "$CLOUD_PROVIDER" == "vagrant" ]]; then
		internal_ip=172.17.8.100
	fi
	# BYO
	if [[ "$CLOUD_PROVIDER" == "byo" ]]; then
		internal_ip=${IPCTRL1}
        fi
	# Generate each workers kubeconfig
	# 	outputs: worker-0.kubeconfig worker-1.kubeconfig worker-2.kubeconfig
	for i in $(seq 0 "$WORKERS"); do
		instance="worker-node-${i}"
		kubectl config set-cluster "$RESOURCE_GROUP" \
			--certificate-authority="${CERTIFICATE_TMP_DIR}/ca.pem" \
			--embed-certs=true \
			--server="https://${internal_ip}:6443" \
			--kubeconfig="${instance}.kubeconfig"

		kubectl config set-credentials "system:node:${instance}" \
			--client-certificate="${CERTIFICATE_TMP_DIR}/${instance}.pem" \
			--client-key="${CERTIFICATE_TMP_DIR}/${instance}-key.pem" \
			--embed-certs=true \
			--kubeconfig="${instance}.kubeconfig"

		kubectl config set-context default \
			--cluster="$RESOURCE_GROUP" \
			--user=system:node:"${instance}" \
			--kubeconfig="${instance}.kubeconfig"

		kubectl config use-context default --kubeconfig="${instance}.kubeconfig"
	done

	# Generate kube-proxy config
	# 	outputs: kube-proxy.kubeconfig
	kubectl config set-cluster "$RESOURCE_GROUP" \
		--certificate-authority="${CERTIFICATE_TMP_DIR}/ca.pem" \
		--embed-certs=true \
		--server="https://${internal_ip}:6443" \
		--kubeconfig=kube-proxy.kubeconfig

	kubectl config set-credentials kube-proxy \
		--client-certificate="${CERTIFICATE_TMP_DIR}/kube-proxy.pem" \
		--client-key="${CERTIFICATE_TMP_DIR}/kube-proxy-key.pem" \
		--embed-certs=true \
		--kubeconfig=kube-proxy.kubeconfig

	kubectl config set-context default \
		--cluster="$RESOURCE_GROUP" \
		--user=kube-proxy \
		--kubeconfig=kube-proxy.kubeconfig

	kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig

	export KUBECONFIG_TMP_DIR="$tmpdir"
	echo "Kubeconfigs generated in KUBECONFIG_TMP_DIR env var: $KUBECONFIG_TMP_DIR"
}
