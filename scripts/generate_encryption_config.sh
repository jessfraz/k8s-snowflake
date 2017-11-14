#!/bin/bash
#
# Outputs: the file where the encryption config can be found
#
set -e
set -o pipefail

generate_encryption_config() {
	ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)

	tmpdir=$(mktmp -d)
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

	echo "$configfile"
}

generate_encryption_config
