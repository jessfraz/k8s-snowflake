#!/bin/bash
#
# This script provisions a cluster running in bare/vsphere/kvm/xen with clear linux os
# and provisions a kubernetes cluster on it.
#
# The script assumes you have all nodes ready and ssh configured from where you plan to run from.
#
set -e
set -o pipefail

export CLOUD_PROVIDER="byo"

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPT_DIR="${DIR}/../scripts"

# Get the existing node information to pass onto the provisioner sript
echo "Type the controller node hostname:"
read CONTROLLER_NODE_NAME
echo "Type the controller node IP:"
read IPCTRL1
# User below might need to be changed depending on your needs.
export SSH_KEYFILE=${SSH_KEYFILE:-${HOME}/.ssh/id_rsa}
export WORKERS=${WORKERS:-2}
export VM_USER=${VM_USER:-root}
export CONTROLLER_NODE_NAME IPCTRL1

if [[ ! -f "$SSH_KEYFILE" ]]; then
	echo >&2 "SSH_KEYFILE $SSH_KEYFILE does not exist."
	echo >&2 "Change the SSH_KEYFILE variable to a new path or create an ssh key there (HOME/.ssh/id_rsa)."
	exit 1
fi
SSH_KEYFILE_VALUE=$(cat "${SSH_KEYFILE}.pub")

# Test SSH connectivity
echo "Testing SSH connectivity"
ssh -q -o BatchMode=yes -o ConnectTimeout=10 ${VM_USER}@${CONTROLLER_NODE_NAME} "touch /tmp/byo.node" | exit && echo $host "$CONTROLLER_NODE_NAME: SSH Connection...OK" || echo $host "$CONTROLLER_NODE_NAME: SSH Connection...FAILED" | exit 1
ssh -q -o BatchMode=yes -o ConnectTimeout=10 ${VM_USER}@${IPCTRL1} exit && echo $host "$IPCTRL1: SSH Connection...OK" || echo $host "$IPCTRL1: SSH Connection...FAILED" | exit 1
for i in $(seq 0 "$WORKERS"); do
        worker_node_name="worker-node-${i}"
        ssh -q ${VM_USER}@${worker_node_name} exit && echo $host "$worker_node_name: SSH Connection...OK" || echo $host "$worker_node_name: SSH Connection...FAILED" | exit 1
        theip=$(host ${worker_node_name} | awk '/has address/ { print $4 }')
        ssh -q ${VM_USER}@${theip} exit && echo $host "$theip: SSH Connection...OK" || echo $host "$theip: SSH Connection...FAILED" | exit 1
done

"${SCRIPT_DIR}/provision.sh"
