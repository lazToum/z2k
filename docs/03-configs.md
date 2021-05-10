# Generate configuration files encryption-config.yaml, *.kubeconfig

[../scripts/03-configs.sh](../scripts/03-configs.sh)

```bash

LOAD_BALANCER_IP="$(cat /etc/hosts | grep balancer | tail -1 | awk '{print $1}')"
CLUSTER_NAME=kubernetes-the-hard-way
ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)

function make_config() {
  local _name; _name="${1}"
  local _user; _user="${2}"
  local _server; _server="${3}"
  kubectl config set-cluster "${CLUSTER_NAME}" \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=https://${_server}:6443 \
    --kubeconfig="${_name}.kubeconfig"
  
  kubectl config set-credentials "${_user}" \
    --client-certificate="${_name}.pem" \
    --client-key="${_name}-key.pem" \
    --embed-certs=true \
    --kubeconfig="${_name}.kubeconfig"
  
  kubectl config set-context default \
    --cluster="${CLUSTER_NAME}" \
    --user="${_user}" \
    --kubeconfig="${_name}.kubeconfig"

  kubectl config use-context default --kubeconfig="${_name}.kubeconfig"
}

function encryption_config() {
  cat > encryption-config.yaml <<EOF
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
}
...
```
