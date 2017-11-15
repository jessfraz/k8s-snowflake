#!/bin/bash
#
# This script provisions controller and worker nodes to run kubernetes.
#
set -e
set -o pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# get the controller node public ip address
# this is cloud provider specific
# Google Cloud
if [[ "$CLOUD_PROVIDER" == "google" ]]; then
	controller_ip=$(gcloud compute instances describe "$CONTROLLER_NODE_NAME" --format 'value(networkInterfaces[0].accessConfigs[0].natIP)')
	#controller_ip=$(gcloud compute addresses describe "$PUBLIC_IP_NAME" --region "$REGION" --format 'value(address)')
fi
# Azure
if [[ "$CLOUD_PROVIDER" == "azure" ]]; then
	controller_ip=$(az network public-ip show -g "$RESOURCE_GROUP" --name "$PUBLIC_IP_NAME" --query 'ipAddress' -o tsv | tr -d '[:space:]')
fi

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
	scp -i "$SSH_KEYFILE" "${CERTIFICATE_TMP_DIR}/ca.pem" "${CERTIFICATE_TMP_DIR}/ca-key.pem" "${CERTIFICATE_TMP_DIR}/kubernetes.pem" "${CERTIFICATE_TMP_DIR}/kubernetes-key.pem" "${VM_USER}@${controller_ip}":~/

	echo "Copying certs to worker nodes..."
	for i in $(seq 0 "$WORKERS"); do
		instance="worker-node-${i}"

		# get the external ip for the instance
		# this is cloud provider specific
		# Google Cloud
		if [[ "$CLOUD_PROVIDER" == "google" ]]; then
			external_ip=$(gcloud compute instances describe "$instance" --format 'value(networkInterfaces[0].accessConfigs[0].natIP)')
		fi
		# Azure
		if [[ "$CLOUD_PROVIDER" == "azure" ]]; then
			external_ip=$(az vm show -g "$RESOURCE_GROUP" -n "$instance" --show-details --query 'publicIps' -o tsv | tr -d '[:space:]')
		fi

		# Copy the certificates
		scp -i "$SSH_KEYFILE" "${CERTIFICATE_TMP_DIR}/ca.pem" "${CERTIFICATE_TMP_DIR}/${instance}-key.pem" "${CERTIFICATE_TMP_DIR}/${instance}.pem" "${VM_USER}@${external_ip}":~/
	done
}

do_kubeconfigs(){
	echo "Generating kubeconfigs locally with kubectl..."
	# shellcheck disable=SC1090
	source "${DIR}/generate_configuration_files.sh"
	generate_configuration_files
	echo "Kubeconfigs successfully generated in ${KUBECONFIG_TMP_DIR}!"

	echo "Copying kubeconfigs to worker nodes..."
	for i in $(seq 0 "$WORKERS"); do
		instance="worker-node-${i}"

		# get the external ip for the instance
		# this is cloud provider specific
		# Google Cloud
		if [[ "$CLOUD_PROVIDER" == "google" ]]; then
			external_ip=$(gcloud compute instances describe "$instance" --format 'value(networkInterfaces[0].accessConfigs[0].natIP)')
		fi
		# Azure
		if [[ "$CLOUD_PROVIDER" == "azure" ]]; then
			external_ip=$(az vm show -g "$RESOURCE_GROUP" -n "$instance" --show-details --query 'publicIps' -o tsv | tr -d '[:space:]')
		fi

		# Copy the kubeconfigs
		scp -i "$SSH_KEYFILE" "${KUBECONFIG_TMP_DIR}/${instance}.kubeconfig" "${KUBECONFIG_TMP_DIR}/kube-proxy.kubeconfig" "${VM_USER}@${external_ip}":~/
	done
}

do_encryption_config(){
	echo "Generating encryption config locally..."
	# shellcheck disable=SC1090
	source "${DIR}/generate_encryption_config.sh"
	generate_encryption_config
	echo "Encryption config successfully generated in ${ENCRYPTION_CONFIG}!"

	echo "Copying encryption config to controller node..."
	scp -i "$SSH_KEYFILE" "$ENCRYPTION_CONFIG" "${VM_USER}@${controller_ip}":~/
}

do_etcd(){
	echo "Moving certficates to correct location for etcd on controller node..."
	ssh -i "$SSH_KEYFILE" "${VM_USER}@${controller_ip}" sudo mkdir -p /etc/etcd/
	ssh -i "$SSH_KEYFILE" "${VM_USER}@${controller_ip}" sudo cp ca.pem kubernetes-key.pem kubernetes.pem /etc/etcd/

	echo "Copying etcd.service to controller node..."
	scp -i "$SSH_KEYFILE" "${DIR}/../etc/systemd/system/etcd.service" "${VM_USER}@${controller_ip}":~/
	ssh -i "$SSH_KEYFILE" "${VM_USER}@${controller_ip}" sudo mkdir -p /etc/systemd/system/
	ssh -i "$SSH_KEYFILE" "${VM_USER}@${controller_ip}" sudo mv etcd.service /etc/systemd/system/

	echo "Copying etcd install script to controller node..."
	scp -i "$SSH_KEYFILE" "${DIR}/install_etcd.sh" "${VM_USER}@${controller_ip}":~/

	echo "Running install_etcd.sh on controller node..."
	ssh -i "$SSH_KEYFILE" "${VM_USER}@${controller_ip}" sudo ./install_etcd.sh

	# cleanup the script after install
	ssh -i "$SSH_KEYFILE" "${VM_USER}@${controller_ip}" rm install_etcd.sh
}

do_k8s_controller(){
	echo "Moving certficates to correct location for k8s on controller node..."
	ssh -i "$SSH_KEYFILE" "${VM_USER}@${controller_ip}" sudo mkdir -p /var/lib/kubernetes/
	ssh -i "$SSH_KEYFILE" "${VM_USER}@${controller_ip}" sudo mv ca.pem kubernetes-key.pem kubernetes.pem ca-key.pem encryption-config.yaml /var/lib/kubernetes/

	ssh -i "$SSH_KEYFILE" "${VM_USER}@${controller_ip}" sudo mkdir -p /etc/systemd/system/
	services=( kube-apiserver.service kube-scheduler.service kube-controller-manager.service )
	for service in "${services[@]}"; do
		echo "Copying $service to controller node..."
		scp -i "$SSH_KEYFILE" "${DIR}/../etc/systemd/system/${service}" "${VM_USER}@${controller_ip}":~/
		ssh -i "$SSH_KEYFILE" "${VM_USER}@${controller_ip}" sudo mv "$service" /etc/systemd/system/
	done

	echo "Copying k8s controller install script to controller node..."
	scp -i "$SSH_KEYFILE" "${DIR}/install_kubernetes_controller.sh" "${VM_USER}@${controller_ip}":~/

	echo "Running install_kubernetes_controller.sh on controller node..."
	ssh -i "$SSH_KEYFILE" "${VM_USER}@${controller_ip}" sudo ./install_kubernetes_controller.sh

	# cleanup the script after install
	ssh -i "$SSH_KEYFILE" "${VM_USER}@${controller_ip}" rm install_kubernetes_controller.sh

	echo "Copying k8s rbac configs to controller node..."
	scp -i "$SSH_KEYFILE" "${DIR}/../etc/cluster-role-"*.yaml "${VM_USER}@${controller_ip}":~/

	echo "Copying k8s pod configs to controller node..."
	scp -i "$SSH_KEYFILE" "${DIR}/../etc/pod-"*.yaml "${VM_USER}@${controller_ip}":~/

	echo "Copying k8s kube-dns config to controller node..."
	scp -i "$SSH_KEYFILE" "${DIR}/../etc/kube-dns.yaml" "${VM_USER}@${controller_ip}":~/

	# get the internal ip for the instance
	# this is cloud provider specific
	# Google Cloud
	if [[ "$CLOUD_PROVIDER" == "google" ]]; then
		internal_ip=$(gcloud compute instances describe "$CONTROLLER_NODE_NAME" --format 'value(networkInterfaces[0].networkIP)')
	fi
	# Azure
	if [[ "$CLOUD_PROVIDER" == "azure" ]]; then
		internal_ip=$(az vm show -g "$RESOURCE_GROUP" -n "$CONTROLLER_NODE_NAME" --show-details --query 'privateIps' -o tsv | tr -d '[:space:]')
	fi

	# configure cilium to use etcd tls
	tmpd=$(mktemp -d)
	ciliumconfig="${tmpd}/cilium.yaml"
	sed "s#ETCD_CA#$(base64 -w 0 "${CERTIFICATE_TMP_DIR}/ca.pem")#" "${DIR}/../etc/cilium.yaml" > "$ciliumconfig"
	sed -i "s#ETCD_CLIENT_KEY#$(base64 -w 0 "${CERTIFICATE_TMP_DIR}/kubernetes-key.pem")#" "$ciliumconfig"
	sed -i "s#ETCD_CLIENT_CERT#$(base64 -w 0 "${CERTIFICATE_TMP_DIR}/kubernetes.pem")#" "$ciliumconfig"
	sed -i "s#INTERNAL_IP#${internal_ip}#" "$ciliumconfig"

	echo "Copying k8s cilium config to controller node..."
	scp -i "$SSH_KEYFILE" "$ciliumconfig" "${VM_USER}@${controller_ip}":~/

	# cleanup
	rm -rf "$tmpd"

	# wait for kube-apiserver service to come up
	# TODO: make this not a shitty sleep you goddamn savage
	sleep 10

	# get the component statuses for sanity
	ssh -i "$SSH_KEYFILE" "${VM_USER}@${controller_ip}" kubectl get componentstatuses

	# create the pod permissive security policy
	ssh -i "$SSH_KEYFILE" "${VM_USER}@${controller_ip}" kubectl apply -f pod-security-policy-permissive.yaml
	ssh -i "$SSH_KEYFILE" "${VM_USER}@${controller_ip}" kubectl apply -f pod-security-policy-restricted.yaml

	# create the rbac cluster roles
	ssh -i "$SSH_KEYFILE" "${VM_USER}@${controller_ip}" kubectl apply -f cluster-role-kube-apiserver-to-kubelet.yaml
	ssh -i "$SSH_KEYFILE" "${VM_USER}@${controller_ip}" kubectl apply -f cluster-role-binding-kube-apiserver-to-kubelet.yaml
	ssh -i "$SSH_KEYFILE" "${VM_USER}@${controller_ip}" kubectl apply -f cluster-role-restricted.yaml
	ssh -i "$SSH_KEYFILE" "${VM_USER}@${controller_ip}" kubectl apply -f cluster-role-binding-restricted.yaml

	# create kube-dns
	ssh -i "$SSH_KEYFILE" "${VM_USER}@${controller_ip}" kubectl apply -f kube-dns.yaml

	# create cilium
	ssh -i "$SSH_KEYFILE" "${VM_USER}@${controller_ip}" kubectl apply -f cilium.yaml
}

do_k8s_worker(){
	for i in $(seq 0 "$WORKERS"); do
		instance="worker-node-${i}"

		# get the external ip for the instance
		# this is cloud provider specific
		# Google Cloud
		if [[ "$CLOUD_PROVIDER" == "google" ]]; then
			external_ip=$(gcloud compute instances describe "$instance" --format 'value(networkInterfaces[0].accessConfigs[0].natIP)')
		fi
		# Azure
		if [[ "$CLOUD_PROVIDER" == "azure" ]]; then
			external_ip=$(az vm show -g "$RESOURCE_GROUP" -n "$instance" --show-details --query 'publicIps' -o tsv | tr -d '[:space:]')
		fi

		echo "Moving certficates to correct location for k8s on ${instance}..."
		ssh -i "$SSH_KEYFILE" "${VM_USER}@${external_ip}" sudo mkdir -p /var/lib/kubelet/
		ssh -i "$SSH_KEYFILE" "${VM_USER}@${external_ip}" sudo mv "${instance}-key.pem" "${instance}.pem" /var/lib/kubelet/
		ssh -i "$SSH_KEYFILE" "${VM_USER}@${external_ip}" sudo mkdir -p /var/lib/kubernetes/
		ssh -i "$SSH_KEYFILE" "${VM_USER}@${external_ip}" sudo mv ca.pem /var/lib/kubernetes/
		ssh -i "$SSH_KEYFILE" "${VM_USER}@${external_ip}" sudo mv "${instance}.kubeconfig" /var/lib/kubelet/kubeconfig
		ssh -i "$SSH_KEYFILE" "${VM_USER}@${external_ip}" sudo mkdir -p /var/lib/kube-proxy/
		ssh -i "$SSH_KEYFILE" "${VM_USER}@${external_ip}" sudo mv kube-proxy.kubeconfig /var/lib/kube-proxy/kubeconfig

		scp -i "$SSH_KEYFILE" "${DIR}/../etc/cni/net.d/"*.conf "${VM_USER}@${external_ip}":~/

		echo "Moving cni configs to correct location for k8s on ${instance}..."
		ssh -i "$SSH_KEYFILE" "${VM_USER}@${external_ip}" sudo mkdir -p /etc/cni/net.d/
		ssh -i "$SSH_KEYFILE" "${VM_USER}@${external_ip}" sudo mv 10-bridge.conf 99-loopback.conf /etc/cni/net.d/

		echo "Copying k8s worker install script to ${instance}..."
		scp -i "$SSH_KEYFILE" "${DIR}/install_kubernetes_worker.sh" "${VM_USER}@${external_ip}":~/

		ssh -i "$SSH_KEYFILE" "${VM_USER}@${external_ip}" sudo mkdir -p /etc/systemd/system/
		services=( kubelet.service kube-proxy.service )
		for service in "${services[@]}"; do
			echo "Copying $service to ${instance}..."
			scp -i "$SSH_KEYFILE" "${DIR}/../etc/systemd/system/${service}" "${VM_USER}@${external_ip}":~/
			ssh -i "$SSH_KEYFILE" "${VM_USER}@${external_ip}" sudo mv "$service" /etc/systemd/system/
		done

		echo "Running install_kubernetes_worker.sh on ${instance}..."
		ssh -i "$SSH_KEYFILE" "${VM_USER}@${external_ip}" sudo ./install_kubernetes_worker.sh

		# cleanup the script after install
		ssh -i "$SSH_KEYFILE" "${VM_USER}@${external_ip}" rm install_kubernetes_worker.sh
	done
}

do_end_checks(){
	if [[ "$CLOUD_PROVIDER" == "google" ]]; then
		controller_ip=$(gcloud compute addresses describe "$PUBLIC_IP_NAME" --region "$REGION" --format 'value(address)')
	fi

	# check that we can reach the kube-apiserver externally
	echo "Testing a curl to the apiserver..."
	curl --cacert "${CERTIFICATE_TMP_DIR}/ca.pem" "https://${controller_ip}:6443/version"
	echo ""
}

do_local_kubeconfig(){
	# setup local kubectl
	kubectl config set-cluster "$RESOURCE_GROUP" \
		--certificate-authority="${CERTIFICATE_TMP_DIR}/ca.pem" \
		--embed-certs=true \
		--server="https://${controller_ip}:6443"

	kubectl config set-credentials admin \
		--client-certificate="${CERTIFICATE_TMP_DIR}/admin.pem" \
		--client-key="${CERTIFICATE_TMP_DIR}/admin-key.pem" \
		--embed-certs=true

	kubectl config set-context "$RESOURCE_GROUP" \
		--cluster="$RESOURCE_GROUP" \
		--user=admin

	kubectl config use-context "$RESOURCE_GROUP"

	echo "Checking get nodes..."
	kubectl get nodes
}

do_certs
do_kubeconfigs
do_encryption_config
do_etcd
do_k8s_controller
do_k8s_worker
do_end_checks
do_local_kubeconfig
