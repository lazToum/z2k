# Client tools installation

- cfssl, cfssljson, kubectl: [../scripts/01-tools.sh](../scripts/01-tools.sh)

```bash
#1.5.0
cfssl_version="$(curl -w '%{redirect_url}' -o /dev/null -s  https://github.com/cloudflare/cfssl/releases/latest | sed 's:\(.*/tag/v\)\(.*\):\2:')"

# v1.21.0
kubectl_version="$(curl -L -s https://dl.k8s.io/release/stable.txt)"

curl -L "https://github.com/cloudflare/cfssl/releases/download/v${cfssl_version}/cfssl_${cfssl_version}_linux_amd64" -o cfssl
curl -L "https://github.com/cloudflare/cfssl/releases/download/v${cfssl_version}/cfssljson_${cfssl_version}_linux_amd64" -o cfssljson
curl -LO "https://dl.k8s.io/release/${kubectl_version}/bin/linux/amd64/kubectl"

chmod +x cfssl cfssljson kubectl
sudo mv cfssl cfssljson kubectl /usr/local/bin/

# validate
cfssl version
cfssljson --version
kubectl version --client --short

```
