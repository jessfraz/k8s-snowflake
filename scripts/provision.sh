#!/bin/bash
#
# This script provisions controller and worker nodes to run kubernetes.
#
set -e
set -o pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "Provisioning kubernetes cluster for resource group $RESOURCE_GROUP..."

echo "Generating certificates locally with cfssl..."
source "${DIR}/generate_certificates.sh"
# Make sure we have cfssl installed first
install_cfssl
generate_certificates "$@"
echo "Certificates successfully generated in ${CERTIFICATE_TMP_DIR}!"
