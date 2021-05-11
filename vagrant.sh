#!/bin/bash

set -e

function read_env() {
    IPS_PREFIX="${IPS_PREFIX:-}"
    WORKER_NODES="${WORKER_NODES:-}"
    CONTROLLER_NODES="${CONTROLLER_NODES:-}"
    CLIENT_IP_SUFFIX="${CLIENT_IP_SUFFIX:-}"
    LB_IP_SUFFIX="${LB_IP_SUFFIX:-}"
    CONTROLLERS_IP_START="${CONTROLLERS_IP_START:-}"
    WORKERS_IP_START="${WORKERS_IP_START:-}"
    export DOMAIN_NAME="${DOMAIN_NAME:-localhost}"
    export INCLUDE_DASHBOARD="${INCLUDE_DASHBOARD:-false}"
    if [ ! "${DOMAIN_NAME}" = "localhost" ]; then
        export FQDN="${DOMAIN_NAME}"
    fi
}

function get_hosts_and_ips() {
    local lb_ip="${IPS_PREFIX}${LB_IP_SUFFIX}"
    local client_ip="${IPS_PREFIX}${CLIENT_IP_SUFFIX}"
    printf "%s\tload-balancer.kubernetes.local\tload-balancer\n" "${lb_ip}" >> /tmp/hosts.tmp
    IPS=( "${lb_ip}" "${client_ip}" )
    local i=0
    while [[ $i -lt ${CONTROLLER_NODES} ]]; do
        controller_ip=${IPS_PREFIX}$(( CONTROLLERS_IP_START + i ))
        IPS+=( "${controller_ip}" )
        printf "%s\tcontroller-%s.kubernetes.local\tcontroller-%s\n" "${controller_ip}" "${i}" "${i}" >> /tmp/hosts.tmp
        ((i = i + 1))
    done
    local j=0
     while [[ $j -lt ${WORKER_NODES} ]]; do
        worker_ip="${IPS_PREFIX}$(( WORKERS_IP_START + j ))"
        IPS+=( "${worker_ip}" )
        printf "%s\tworker-%s.kubernetes.local\tworker-%s\n" "${worker_ip}" "${j}" "${j}" >> /tmp/hosts.tmp
        ((j = j + 1))
    done
}

function install_ssh_pass() {
    if command -v apt &> /dev/null; then
        sudo apt update && sudo apt install sshpass -y
    elif command -v dnf &> /dev/null; then
        sudo dnf install sshpass -y
    elif command -v yum &> /dev/null; then
        sudo yum install sshpass -y
    fi

}

function copy_my_id() {
    if ! command -v sshpass &> /dev/null; then
        install_ssh_pass
    fi
    if ! command -v sshpass &> /dev/null; then
        echo "no sshpass :("
        exit 1
    fi
    sshpass -p 'vagrant' ssh-copy-id "vagrant@${1}"
    ssh "vagrant@${1}" "sudo sed -i -E 's/^#?PasswordAuthentication yes.*/PasswordAuthentication no/g' /etc/ssh/sshd_config && if command -v systemctl &> /dev/null; then sudo systemctl restart ssh; elif [ -f /etc/init.d/ssh ]; then sudo /etc/init.d/ssh restart; else sudo kill -HUP \$(cat /var/run/sshd.pid);fi"
}

my_ssh () {
  if [ -f /home/vagrant/.ssh/id_rsa ]; then
      rm /home/vagrant/.ssh/id_rsa
  fi
  if [ -f /home/vagrant/.ssh/id_rsa.pub ]; then
      rm /home/vagrant/.ssh/id_rsa.pub
  fi
  ssh-keygen -f /home/vagrant/.ssh/id_rsa -t rsa -q -N ''
   _pre="$(echo "${IPS_PREFIX}" | cut -d. -f1)"
  cat > ~/.ssh/config <<EOF
Host ${_pre}.*
    StrictHostKeyChecking no
    UserKnownHostsFile=/dev/null
EOF
}


function main() {
    my_ip="${1:-}"
    if [[ "${my_ip}" = "" ]]; then
        exit 1
    fi
    read_env
    if  [[ "${IPS_PREFIX}" == "" ]] ||
        [[ "${WORKER_NODES}" -lt 0 ]] ||
        [[ "${CONTROLLER_NODES}" -lt 0 ]] ||
        [[ "${CONTROLLERS_IP_START}" -lt 0 ]] ||
        [[ "${CONTROLLERS_IP_START}" -lt 0 ]] ||
        [[ "${LB_IP_SUFFIX}" -le 1 ]] ||
        [[ "${CLIENT_IP_SUFFIX}" -le 1 ]] ; then
        exit 0
    fi
    my_ssh
    get_hosts_and_ips
    for _ip in "${IPS[@]}";do
        if [[ ! "${_ip}" = "${my_ip}" ]];then
            # if we are running with --parallel, we wait for all instances to be up
            n=0
            # try up to 10 times
            until [ "$n" -ge 10 ]; do
                copy_my_id "${_ip}" && break
                n=$((n+1))
                sleep 10
            done
        fi
    done
    printf "\n\n\nhosts:"
    #shellcheck disable=SC2183
    comment=$(printf "%30s");echo "${comment// /#}"
    if [ -f /tmp/hosts.tmp ]; then
        #shellcheck disable=SC2002
        cat /tmp/hosts.tmp | sudo tee -a /etc/hosts
    fi
    #shellcheck disable=SC2183
    comment=$(printf "%30s");echo "${comment// /#}"
    printf "\n\n\n"
}

if [ -f .env ]; then
    echo "reading from .env"
    set -a
    # shellcheck disable=SC1091
    . .env
    # we are in a vagrant vm, keep the default path
    export ETC_HOSTS=/etc/hosts
fi
main "${@}"
ORIGINAL_IFS=$IFS
if [ -d scripts/ ];then
    # bash scripts/01-tools.sh
    # bash scripts/02-certificates.sh
    IFS=" " read -r -a _scripts <<< "$(find scripts/* -maxdepth 1 -print0 | sort -z | xargs --null)"
    for _script in "${_scripts[@]}"; do
        bash "${_script}"
    done
fi
IFS=$ORIGINAL_IFS
exit 0
