#!/bin/bash
#
# This script provisions a cluster running in google cloud with container os
# and provisions a kubernetes cluster on it.
#
# The script assumes you already have the google cloud command line tool `gcloud`.
#
set -e
set -o pipefail

export CLOUD_PROVIDER="google"

# Check if we have the gcloud command line tool.
command -v gcloud >/dev/null 2>&1 || { echo >&2 "This script requires the google cloud command line tool, gcloud. Aborting."; exit 1; }

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPT_DIR="${DIR}/../scripts"

export RESOURCE_GROUP=${RESOURCE_GROUP:-kubernetes-clear-linux-snowflake}
export REGION=${REGION:-us-east1}
export ZONE=${ZONE:-us-east1c}
export CONTROLLER_NODE_NAME=${CONTROLLER_NODE_NAME:-controller-node}
export SSH_KEYFILE=${SSH_KEYFILE:-${HOME}/.ssh/id_rsa}
export WORKERS=${WORKERS:-2}
export VM_USER=${VM_USER:-azureuser}

if [[ ! -f "$SSH_KEYFILE" ]]; then
	echo >&2 "SSH_KEYFILE $SSH_KEYFILE does not exist."
	echo >&2 "Change the SSH_KEYFILE variable to a new path or create an ssh key there."
	exit 1
fi

# set a default region
gcloud config set compute/region "$REGION"

# set a default zone
gcloud config set compute/zone "$ZONE"

export PUBLIC_IP_NAME="k8s-public-ip"
VIRTUAL_NETWORK_NAME="k8s-virtual-network"

VM_SIZE="n1-standard-1"
# TODO: change this to container os, slacker
IMAGE_FAMILY="ubuntu-1604-lts"
IMAGE_PROJECT="ubuntu-os-cloud"

create_virtual_network() {
	echo "Creating virtual network ${VIRTUAL_NETWORK_NAME}..."
	gcloud compute networks create "$VIRTUAL_NETWORK_NAME" --mode custom
	gcloud compute networks subnets create "k8s-subnet" \
		--network "$VIRTUAL_NETWORK_NAME" \
		--range 10.240.0.0/24

	# create firewall rules
	gcloud compute firewall-rules create "$VIRTUAL_NETWORK_NAME-allow-internal" \
		--allow tcp,udp,icmp \
		--network "$VIRTUAL_NETWORK_NAME" \
		--source-ranges 10.240.0.0/24,10.200.0.0/16
	gcloud compute firewall-rules create "$VIRTUAL_NETWORK_NAME-allow-external" \
		--allow tcp:22,tcp:6443,icmp \
		--network "$VIRTUAL_NETWORK_NAME" \
		--source-ranges 0.0.0.0/0
}

create_apiserver_ip_address() {
	echo "Creating apiserver public ip address..."
	gcloud compute addresses create "$PUBLIC_IP_NAME" \
		--region "$REGION"
}

create_controller_node() {
	echo "Creating controller node ${CONTROLLER_NODE_NAME}..."
	gcloud compute instances create "$CONTROLLER_NODE_NAME" \
		--async \
		--boot-disk-size 200GB \
		--can-ip-forward \
		--image-family "$IMAGE_FAMILY" \
		--image-project "$IMAGE_PROJECT" \
		--machine-type "$VM_SIZE" \
		--private-network-ip 10.240.0.10 \
		--scopes compute-rw,storage-ro,service-management,service-control,logging-write,monitoring \
		--subnet "k8s-subnet" \
		--tags "controller,kubernetes"
}

create_worker_nodes() {
	for i in $(seq 0 "$WORKERS"); do
		worker_node_name="worker-node-${i}"
		echo "Creating worker node ${worker_node_name}..."

		gcloud compute instances create "$worker_node_name" \
			--async \
			--boot-disk-size 200GB \
			--can-ip-forward \
			--image-family "$IMAGE_FAMILY" \
			--image-project "$IMAGE_PROJECT" \
			--machine-type "$VM_SIZE" \
			--private-network-ip "10.240.0.2${i}" \
			--scopes compute-rw,storage-ro,service-management,service-control,logging-write,monitoring \
			--subnet "k8s-subnet" \
			--tags "worker,kubernetes"

		# configure routes
		gcloud compute routes create "${worker_node_name}-route" \
			--network "$VIRTUAL_NETWORK_NAME" \
			--next-hop-address 10.240.0.2${i} \
			--destination-range 10.200.${i}.0/24
	done
}

create_loadbalancer(){
	gcloud compute target-pools create kubernetes-target-pool
	gcloud compute target-pools add-instances kubernetes-target-pool \
		--instances "$CONTROLLER_NODE_NAME"

	public_ip=$(gcloud compute addresses describe "$PUBLIC_IP_NAME" --region "$REGION" --format 'value(name)')

	gcloud compute forwarding-rules create "${PUBLIC_IP_NAME}-forwarding-rule" \
		--address "$PUBLIC_IP_NAME" \
		--ports 6443 \
		--region "$REGION" \
		--target-pool kubernetes-target-pool
}

create_virtual_network
create_apiserver_ip_address
create_controller_node
create_worker_nodes
create_loadbalancer

"${SCRIPT_DIR}/provision.sh"
