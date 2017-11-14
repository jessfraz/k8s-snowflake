#!/bin/bash
#
# This script provisions controller and worker nodes to run kubernetes.
#
set -e
set -o pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "Provisioning kubernetes cluster for resource group $RESOURCE_GROUP..."

echo "Generating certificates locally with cfssl..."
# shellcheck disable=SC1090
source "${DIR}/generate_certificates.sh"
# Make sure we have cfssl installed first
install_cfssl
generate_certificates
echo "Certificates successfully generated in ${CERTIFICATE_TMP_DIR}!"

echo "Generating kubeconfigs locally with kubectl..."
# shellcheck disable=SC1090
source "${DIR}/generate_configuration_files.sh"
generate_configuration_files
echo "Kubeconfigs successfully generated in ${KUBECONFIG_TMP_DIR}!"

echo "Generating encryption config locally..."
# shellcheck disable=SC1090
source "${DIR}/generate_encryption_config.sh"
generate_encryption_config
echo "Encryption config successfully generated in ${ENCRYPTION_CONFIG}!"
