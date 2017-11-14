#!/bin/bash
#
# This script provisions controller and worker nodes to run kubernetes.
#
set -e
set -o pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# get the controller node public ip address
# this is cloud provider specific
# Google
# public_address=$(gcloud compute addresses describe "$CONTROLLER_NODE_NAME" --region "$(gcloud config get-value compute/region)" --format 'value(address)')
# Azure
controller_ip=$(az network public-ip show -g "$RESOURCE_GROUP" --name "k8s-public-ip" --query 'ipAddress' -o tsv | tr -d '[:space:]')

echo "Provisioning kubernetes cluster for resource group $RESOURCE_GROUP..."

do_certs(){
	echo "Generating certificates locally with cfssl..."
	# shellcheck disable=SC1090
	source "${DIR}/generate_certificates.sh"
	# Make sure we have cfssl installed first
	install_cfssl
	generate_certificates
	echo "Certificates successfully generated in ${CERTIFICATE_TMP_DIR}!"

	echo "Copying certs to controller node..."
	scp "${CERTIFICATE_TMP_DIR}/ca.pem" "${CERTIFICATE_TMP_DIR}/ca-key.pem" "${CERTIFICATE_TMP_DIR}/kubernetes.pem" "${CERTIFICATE_TMP_DIR}/kubernetes-key.pem" "${VM_USER}@${controller_ip}":~/

	echo "Copying certs to worker nodes..."
	for i in $(seq 1 "$WORKERS"); do
		instance="worker-node-${i}"

		# get the external ip for the instance
		# this is cloud provider specific
		# Google
		# external_ip=$(gcloud compute instances describe "$instance" --format 'value(networkInterfaces[0].accessConfigs[0].natIP)')
		# Azure
		external_ip=$(az vm show -g "$RESOURCE_GROUP" -n "$instance" --show-details --query 'publicIps' -o tsv | tr -d '[:space:]')

		# Copy the certificates
		scp "${CERTIFICATE_TMP_DIR}/ca.pem" "${CERTIFICATE_TMP_DIR}/${instance}-key.pem" "${CERTIFICATE_TMP_DIR}/${instance}.pem" "${VM_USER}@${external_ip}":~/
	done
}

do_kubeconfigs(){
	echo "Generating kubeconfigs locally with kubectl..."
	# shellcheck disable=SC1090
	source "${DIR}/generate_configuration_files.sh"
	generate_configuration_files
	echo "Kubeconfigs successfully generated in ${KUBECONFIG_TMP_DIR}!"

	echo "Copying kubeconfigs to worker nodes..."
	for i in $(seq 1 "$WORKERS"); do
		instance="worker-node-${i}"

		# get the external ip for the instance
		# this is cloud provider specific
		# Google
		# external_ip=$(gcloud compute instances describe "$instance" --format 'value(networkInterfaces[0].accessConfigs[0].natIP)')
		# Azure
		external_ip=$(az vm show -g "$RESOURCE_GROUP" -n "$instance" --show-details --query 'publicIps' -o tsv | tr -d '[:space:]')

		# Copy the kubeconfigs
		scp "${KUBECONFIG_TMP_DIR}/${instance}.kubeconfig" "${KUBECONFIG_TMP_DIR}/kube-proxy.kubeconfig" "${VM_USER}@${external_ip}":~/
	done
}

do_encryption_config(){
	echo "Generating encryption config locally..."
	# shellcheck disable=SC1090
	source "${DIR}/generate_encryption_config.sh"
	generate_encryption_config
	echo "Encryption config successfully generated in ${ENCRYPTION_CONFIG}!"

	echo "Copying encryption config to controller node..."
	scp "$ENCRYPTION_CONFIG" "${VM_USER}@${controller_ip}":~/
}

do_etcd(){
	echo "Moving certficates to correct location for etcd on controller node..."
	ssh "${VM_USER}@${controller_ip}" sudo mkdir -p /etc/etcd/
	ssh "${VM_USER}@${controller_ip}" sudo mv ca.pem kubernetes-key.pem kubernetes.pem /etc/etcd/

	echo "Copying etcd.service to controller node..."
	scp "${DIR}/../etc/systemd/system/etcd.service" "${VM_USER}@${controller_ip}":~/
	ssh "${VM_USER}@${controller_ip}" sudo mkdir -p /etc/systemd/system/
	ssh "${VM_USER}@${controller_ip}" sudo mv etcd.service /etc/systemd/system/

	echo "Copying etcd install script to controller node..."
	scp "${DIR}/install_etcd.sh" "${VM_USER}@${controller_ip}":~/

	echo "Running install_etcd.sh on controller node..."
	ssh "${VM_USER}@${controller_ip}" sudo ./install_etcd.sh
}

do_k8s_controller(){
	echo "Moving certficates to correct location for k8s on controller node..."
	ssh "${VM_USER}@${controller_ip}" sudo mkdir -p /var/lib/kubernetes/
	ssh "${VM_USER}@${controller_ip}" sudo mv ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem encryption-config.yaml /var/lib/kubernetes/

	services=( kube-apiserver.service kube-scheduler.service kube-controller-manager.service )
	for service in "${services[@]}"; do
		echo "Copying $service to controller node..."
		scp "${DIR}/../etc/systemd/system/${service}" "${VM_USER}@${controller_ip}":~/
		ssh "${VM_USER}@${controller_ip}" sudo mkdir -p /etc/systemd/system/
		ssh "${VM_USER}@${controller_ip}" sudo mv "$service" /etc/systemd/system/
	done

	echo "Copying k8s controller install script to controller node..."
	scp "${DIR}/install_kubernetes_controller.sh" "${VM_USER}@${controller_ip}":~/

	echo "Running install_kubernetes_controller.sh on controller node..."
	ssh "${VM_USER}@${controller_ip}" sudo ./install_kubernetes_controller.sh
}

# TODO: uncomment these
do_certs
do_kubeconfigs
do_encryption_config
do_etcd
do_k8s_controller
