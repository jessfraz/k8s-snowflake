#!/bin/bash
#
# This script provisions a cluster running in azure with clear linux os
# and provisions a kubernetes cluster on it.
#
# The script assumes you already have the azure command line tool `az`.
#
set -e
set -o pipefail

# Check if we have the azure command line.
command -v az >/dev/null 2>&1 || { echo >&2 "This script requires the azure command line tool, az. Aborting."; exit 1; }

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPT_DIR="${DIR}/../scripts"

export RESOURCE_GROUP=${RESOURCE_GROUP:-kubernetes-clear-linux}
export REGION=${REGION:-eastus}
export CONTROLLER_NODE_NAME=${CONTROLLER_NODE_NAME:-controller-node}
export SSH_KEYFILE=${SSH_KEYFILE:-${HOME}/.ssh/id_rsa}
export WORKERS=${WORKERS:-2}
export VM_USER=${VM_USER:-azureuser}

if [[ ! -f "$SSH_KEYFILE" ]]; then
	echo >&2 "SSH_KEYFILE $SSH_KEYFILE does not exist."
	echo >&2 "Change the SSH_KEYFILE variable to a new path or create an ssh key there."
	exit 1
fi
SSH_KEYFILE_VALUE=$(cat "${SSH_KEYFILE}.pub")

PUBLIC_IP_NAME="k8s-public-ip"
VIRTUAL_NETWORK_NAME="k8s-virtual-network"

VM_SIZE="Standard_D2s_v3"
# From:
# 	az vm image list --publisher clear-linux-project --all
OS_SYSTEM="clear-linux-project:clear-linux-os:containers:18860.0.0"

create_resource_group() {
	exists=$(az group exists --name kubernetes-clear-linux | tr -d '[:space:]')

	# Create the resource group if it does not already exist.
	if [[ "$exists" != "true" ]]; then
		echo "Creating resource group $RESOURCE_GROUP in region ${REGION}..."
		az group create --location "$REGION" --name "$RESOURCE_GROUP"
	fi
}

create_virtual_network() {
	echo "Creating virtual network ${VIRTUAL_NETWORK_NAME}..."
	az network vnet create --name "$VIRTUAL_NETWORK_NAME" --resource-group "$RESOURCE_GROUP" \
		--address-prefix 10.240.0.0/16 --subnet-name "k8s-subnet" --subnet-prefix 10.240.0.0/24
}

create_apiserver_ip_address() {
	echo "Creating apiserver public ip address..."
	az network public-ip create --name "$PUBLIC_IP_NAME" --resource-group "$RESOURCE_GROUP"
}

create_controller_node() {
	echo "Creating controller node ${CONTROLLER_NODE_NAME}..."
	az vm create --name "$CONTROLLER_NODE_NAME" --resource-group "$RESOURCE_GROUP" \
		--ssh-key-value "$SSH_KEYFILE_VALUE" \
		--image "$OS_SYSTEM" \
		--admin-username "$VM_USER" \
		--size "$VM_SIZE" \
		--vnet-name "$VIRTUAL_NETWORK_NAME" \
		--subnet "k8s-subnet" \
		--public-ip-address "$PUBLIC_IP_NAME" \
		--nsg "k8s-controller-security-group" \
		--tags "controller,kubernetes"

	# create NSG rule to allow traffic on port 6443
	az network nsg rule create --resource-group "$RESOURCE_GROUP" \
		--nsg-name "k8s-controller-security-group" \
		--name kubeapi --access allow \
		--protocol Tcp --direction Inbound --priority 200 \
		--source-address-prefix "*" \
		--source-port-range "*" \
		--destination-address-prefix "*" \
		--destination-port-range 6443

	# enable ip forwarding
	# enabling IP forwarding for a network interface causes Azure not to
	# check the source/destination IP address.
	# if you don't enable this setting, traffic destined for an IP address
	# other than the NIC that receives it, is dropped by Azure.
	az network nic update --resource-group "$RESOURCE_GROUP" \
		--name "${CONTROLLER_NODE_NAME}VMNic" \
		--ip-forwarding true

	# create the route table
	az network route-table create --resource-group "$RESOURCE_GROUP" \
		--name "k8s-route-table"
}

create_worker_nodes() {
	for i in $(seq 0 "$WORKERS"); do
		worker_node_name="worker-node-${i}"
		echo "Creating worker node ${worker_node_name}..."


		az vm create --name "$worker_node_name" --resource-group "$RESOURCE_GROUP" \
			--public-ip-address-allocation="dynamic" \
			--ssh-key-value "$SSH_KEYFILE_VALUE" \
			--image "$OS_SYSTEM" \
			--admin-username "$VM_USER" \
			--size "$VM_SIZE" \
			--vnet-name "$VIRTUAL_NETWORK_NAME" \
			--subnet "k8s-subnet" \
			--tags "worker,kubernetes"

		# enable ip forwarding
		# enabling IP forwarding for a network interface causes Azure not to
		# check the source/destination IP address.
		# if you don't enable this setting, traffic destined for an IP address
		# other than the NIC that receives it, is dropped by Azure.
		az network nic update --resource-group "$RESOURCE_GROUP" \
			--name "${worker_node_name}VMNic" \
			--ip-forwarding true

		# get the internal ip for the instance
		# this is cloud provider specific
		# Google
		# internal_ip=$(gcloud compute instances describe "$instance" --format 'value(networkInterfaces[0].networkIP)')
		# Azure
		internal_ip=$(az vm show -g "$RESOURCE_GROUP" -n "$worker_node_name" --show-details --query 'privateIps' -o tsv | tr -d '[:space:]')

		# create the routes
		az network route-table route create --resource-group "$RESOURCE_GROUP" \
			--route-table-name "k8s-route-table" \
			--address-prefix "10.200.${i}.0/24" \
			--name "worker-route-${i}" \
			--next-hop-type VirtualAppliance \
			--next-hop-ip-address "$internal_ip"
	done
}

create_resource_group
create_virtual_network
create_apiserver_ip_address
create_controller_node
create_worker_nodes

"${SCRIPT_DIR}/provision.sh"
