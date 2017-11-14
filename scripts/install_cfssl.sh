#!/bin/bash
set -e
set -o pipefail

# From https://pkg.cfssl.org/
CFSSL_VERSION="1.2"

install_cfssl() {
	local download_uri="https://pkg.cfssl.org/R${CFSSL_VERSION}"

	curl -sSL "${download_uri}/cfssl_linux-amd64" > /usr/local/bin/cfssl
	curl -sSL "${download_uri}/cfssljson_linux-amd64" > /usr/local/bin/cfssljson

	chmod +x /usr/local/bin/cfssl*
}

install_cfssl
