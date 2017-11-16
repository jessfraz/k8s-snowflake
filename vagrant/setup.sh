#!/bin/bash
#
# This script provisions a cluster running in Vagrant with ubuntu os
# and provisions a kubernetes cluster on it.
#
# The script assumes you already have Vagrant and VirtualBox installed.
#
set -e
set -o pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPT_DIR="${DIR}/../scripts"

export CLOUD_PROVIDER="vagrant"
export VM_USER="vagrant"
export WORKERS=${WORKERS:-0}

export SSH_CONFIG="${DIR}/../.vagrant/ssh_config"
export SSH_KEYFILE="${HOME}/.vagrant.d/insecure_private_key"
export SSH_OPTIONS="-F ${SSH_CONFIG}"
export RESOURCE_GROUP=${RESOURCE_GROUP:-kubernetes-clear-linux-snowflake}

if [[ $1 == "clean" ]]; then
  vagrant destroy -f
else
  vagrant up
  vagrant ssh-config > "${SSH_CONFIG}"
  "${SCRIPT_DIR}/provision.sh"
fi
