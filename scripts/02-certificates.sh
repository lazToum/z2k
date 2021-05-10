#!/bin/bash
# shellcheck disable=SC2002

# set -xe
# override if needed with env vars:
_COUNTRY="${CERT_COUNTRY:-US}"
_CITY="${CERT_CITY:-Portland}"
_STATE="${CERT_STATE:-Oregon}"
_EXPIRY="${CERT_EXPIRY:-8760h}"
_ORG="${CERT_ORG:-Kubernetes}"
_CA_ORG_UNIT="${CA_CERT_ORG_UNIT:-CA}"
_CERT_ORG_UNIT="${CERT_ORG_UNIT:-"Kubernetes the hard way"}"
_CN="${FQDN:-Kubernetes}"

function make_ca() {
  cat > ca-config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "${_EXPIRY}"
    },
    "profiles": {
      "kubernetes": {
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "expiry": "${_EXPIRY}"
      }
    }
  }
}
EOF

  cat > ca-csr.json <<EOF
{
  "CN": "${_CN}",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "${_COUNTRY}",
      "L": "${_CITY}",
      "O": "${_ORG}",
      "OU": "${_CA_ORG_UNIT}",
      "ST": "${_STATE}"
    }
  ]
}
EOF
  cfssl gencert -initca ca-csr.json | cfssljson -bare ca
}


function make_cert() {
  _name="${1}"
  _cn="${2}"
  _o="${3}"
  _hostnames="${4:-}"
  cat > "${_name}-csr.json" <<EOF
{
  "CN": "${_cn}",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "${_COUNTRY}",
      "L": "${_CITY}",
      "O": "${_o}",
      "OU": "${_CERT_ORG_UNIT}",
      "ST": "${_STATE}"
    }
  ]
}
EOF

if [ ! "${_hostnames}" = "" ];then
  cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  -hostname="${_hostnames}" \
  "${_name}-csr.json" | cfssljson -bare "${_name}"
else
  cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  "${_name}-csr.json" | cfssljson -bare "${_name}"
fi
}

function get_remote_ips() {
  ssh -o StrictHostKeyChecking=no "${1}" ip --brief address | grep -v lo | awk '{print $3}' | cut -d/ -f1 | xargs | sed 's/ /,/g'
}

function make_worker_certs() {
  IFS=" " read -r -a _workers <<< "$(cat /etc/hosts | grep worker | awk '{print $2}' | xargs)"
  for i in "${!WORKERS[@]}"; do
    __worker="${WORKERS[$i]}"
    __host="${_workers[$i]}"
    __worker_ips="$(get_remote_ips "${__worker}")"
    make_cert "${__worker}" "system:node:${__worker}" "system:nodes" "${__worker},${__host},${__worker_ips}"
  done
}

function get_kube_hostnames_and_ips() {
  __common="10.32.0.1,127.0.0.1,localhost,kubernetes.default"
  __me="$(ip --brief address | grep -v lo | awk '{print $3}' | cut -d/ -f1 | xargs | sed 's/ /,/g')"
  __controller_hosts="$(cat /etc/hosts | grep controller | xargs | sed -e "s/[[:space:]]/,/g")"
  __worker_hosts="$(cat /etc/hosts | grep worker | xargs | sed -e "s/[[:space:]]/,/g")"
  __load_balancer_hosts="$(cat /etc/hosts | grep balancer | xargs | sed -e "s/[[:space:]]/,/g")"
  __load_balancer="$(echo "$__load_balancer_hosts" | cut -d, -f1)"
  __lb_ips="$(get_remote_ips "${__load_balancer}")"
  echo "${__common},${__me},$(hostname -s),${__controller_hosts},${CONTROLLER_IPS},${__worker_hosts},${WORKER_IPS},${__load_balancer_hosts},${__lb_ips}"
}

function to_controllers() {
  for __controller in "${CONTROLLERS[@]}"; do
    scp  -o StrictHostKeyChecking=no ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem service-account-key.pem service-account.pem "${__controller}":~/
  done
}

function to_workers() {
  for __worker in "${WORKERS[@]}"; do
    scp -o StrictHostKeyChecking=no ca.pem "${__worker}-key.pem" "${__worker}.pem" "${__worker}":~/
  done
}

function ensure_command() {
    if ! command -v "${1}" &> /dev/null; then
        if command -v apt &> /dev/null; then
            sudo apt update && sudo apt install "${2}" -y
        elif command -v dnf &> /dev/null; then
            sudo dnf install "${3}" -y
        elif command -v yum &> /dev/null; then
            sudo yum install "${3}" -y
        fi
    fi
}

function main() {
  make_ca
  make_cert admin admin system:masters
  make_worker_certs
  make_cert kube-controller-manager system:kube-controller-manager system:kube-controller-manager
  make_cert kube-proxy system:kube-proxy system:kube-proxier
  make_cert kube-scheduler system:kube-scheduler system:kube-scheduler
  make_cert service-account service-accounts Kubernetes
  make_cert kubernetes kubernetes Kubernetes "$(get_kube_hostnames_and_ips)"
  to_controllers
  to_workers
}


ORIGINAL_IFS=$IFS
rm -rf certs && mkdir -p certs && cd certs || exit 1
ensure_command ip iproute2 iproute
IFS=" " read -r -a CONTROLLERS <<< "$(cat /etc/hosts | grep controller | awk '{print $2}' | cut -d. -f1 | xargs)"
IFS=" " read -r -a WORKERS <<< "$(cat /etc/hosts | grep worker | awk '{print $2}' | cut -d. -f1 | xargs)"
WORKER_IPS=""
for _w in "${WORKERS[@]}"; do
  WORKER_IPS="$(get_remote_ips "${_w}"),${WORKER_IPS}"
done
WORKER_IPS="${WORKER_IPS::-1}"
echo "#############################################"
echo "workers: ${WORKER_IPS}"
echo "#############################################"
CONTROLLER_IPS=""
for _c in "${CONTROLLERS[@]}"; do
  CONTROLLER_IPS="$(get_remote_ips "${_c}"),${CONTROLLER_IPS}"
done
CONTROLLER_IPS="${CONTROLLER_IPS::-1}"
echo "#############################################"
echo "controllers: ${CONTROLLER_IPS}"
echo "#############################################"
main
cd ..
IFS=$ORIGINAL_IFS
