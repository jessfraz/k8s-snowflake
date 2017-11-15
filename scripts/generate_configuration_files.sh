#!/bin/bash
set -e
set -o pipefail

generate_configuration_files() {
	tmpdir=$(mktemp -d)

	# create the kubeconfigs in a temporary directory
	cd "$tmpdir"

	# get the controller node public ip address
	# this is cloud provider specific
	# Google
	# internal_ip=$(gcloud compute addresses describe "$CONTROLLER_NODE_NAME" --region "$(gcloud config get-value compute/region)" --format 'value(address)')
	# Azure
	internal_ip=$(az vm list-ip-addresses -g kubernetes-clear-linux -o table | grep controller | awk '{print $3}' | tr -d '[:space:]' | tr '\n' ',' | sed 's/,*$//g')

	# Generate each workers kubeconfig
	# 	outputs: worker-0.kubeconfig worker-1.kubeconfig worker-2.kubeconfig
	for i in $(seq 1 "$WORKERS"); do
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
