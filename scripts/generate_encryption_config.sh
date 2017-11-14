#!/bin/bash
set -e
set -o pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

generate_encryption_config() {
	ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)

	tmpdir=$(mktemp -d)
	configfile="${tmpdir}/encryption-config.yaml"
	sed "s#SECRET#${ENCRYPTION_KEY}#g" "${DIR}/../etc/encryption-config.yaml" > "$configfile"

	export ENCRYPTION_CONFIG="$configfile"
	echo "Encryption config generated in ENCRYPTION_CONFIG env var: $ENCRYPTION_CONFIG"
}
