#!/bin/bash
set -e

if ! command -v cfssl &> /dev/null; then
    #1.5.0
    cfssl_version="$(curl -w '%{redirect_url}' -o /dev/null -s  https://github.com/cloudflare/cfssl/releases/latest | sed 's:\(.*/tag/v\)\(.*\):\2:')"
    curl -L "https://github.com/cloudflare/cfssl/releases/download/v${cfssl_version}/cfssl_${cfssl_version}_linux_amd64" -o cfssl
    chmod +x cfssl && sudo mv cfssl /usr/local/bin/    
fi

if ! command -v cfssljson &> /dev/null; then
    #1.5.0
    cfssl_version="$(curl -w '%{redirect_url}' -o /dev/null -s  https://github.com/cloudflare/cfssl/releases/latest | sed 's:\(.*/tag/v\)\(.*\):\2:')"
    curl -L "https://github.com/cloudflare/cfssl/releases/download/v${cfssl_version}/cfssljson_${cfssl_version}_linux_amd64" -o cfssljson
    chmod +x cfssljson && sudo mv cfssljson /usr/local/bin/
fi

if ! command -v kubectl &> /dev/null; then
    # v1.21.0
    kubectl_version="$(curl -L -s https://dl.k8s.io/release/stable.txt)"
    curl -LO "https://dl.k8s.io/release/${kubectl_version}/bin/linux/amd64/kubectl"
    chmod +x kubectl && sudo mv kubectl /usr/local/bin/
fi

# validate
cfssl version
cfssljson --version
kubectl version --client --short
