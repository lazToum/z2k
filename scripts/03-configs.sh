#!/bin/bash
# shellcheck disable=SC2002

# set -xe

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

function to_controllers() {
  local _controllers
  IFS=" " read -r -a _controllers <<< "$(cat /etc/hosts | grep controller | awk '{print $1}' | xargs)"
  for _controller in "${_controllers[@]}"; do
    scp  -o StrictHostKeyChecking=no admin.kubeconfig kube-controller-manager.kubeconfig kube-scheduler.kubeconfig encryption-config.yaml "${_controller}":~/
  done
}

function to_workers() {
  local _workers
  IFS=" " read -r -a _workers <<< "$(cat /etc/hosts | grep worker | awk '{print $2}' | cut -d. -f1 | xargs)"
  for _worker in "${_workers[@]}"; do
    scp -o StrictHostKeyChecking=no ca.pem "${_worker}.kubeconfig" kube-proxy.kubeconfig "${_worker}":~/
  done
}

function main() {
  IFS=" " read -r -a _workers <<< "$(cat /etc/hosts | grep worker | awk '{print $2}' | cut -d. -f1 | xargs)"
  for _worker in "${_workers[@]}"; do
    make_config "${_worker}" "system:node:${_worker}" "${LOAD_BALANCER_IP}"
  done
  make_config "kube-proxy" "system:kube-proxy" "${LOAD_BALANCER_IP}"
  make_config "kube-controller-manager" "system:kube-controller-manager" "127.0.0.1"
  make_config "kube-scheduler" "system:kube-scheduler" "127.0.0.1"
  make_config "admin" "admin" "127.0.0.1"
  encryption_config
  to_controllers
  to_workers
}

if [ ! -d ./certs ];then
  exit 1
fi
if [ ! -f ./certs/ca.pem ];then
  exit
fi
ORIGINAL_IFS=$IFS
cd certs || exit 1
main
cd ..
IFS=$ORIGINAL_IFS