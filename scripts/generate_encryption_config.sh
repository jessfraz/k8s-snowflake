#!/bin/bash
set -e
set -o pipefail

generate_encryption_config() {
	ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)

	tmpdir=$(mktemp -d)
	configfile="${tmpdir}/encryption-config.yaml"
	cat > "$configfile" <<-EOF
	kind: EncryptionConfig
	apiVersion: v1
	resources:
	  - resources:
		  - secrets
		providers:
		  - aescbc:
			  keys:
				- name: key1
				  secret: ${ENCRYPTION_KEY}
		   - identity: {}
	EOF

	export ENCRYPTION_CONFIG="$configfile"
	echo "Encryption config generated in ENCRYPTION_CONFIG env var: $ENCRYPTION_CONFIG"
}
