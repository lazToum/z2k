#!/bin/bash

set -e

function read_env() {
    if [ -f .env ]; then
      echo "reading from .env"
      set -a
      # shellcheck disable=SC1091
      . .env
    fi
    IPS_PREFIX="${IPS_PREFIX:-}"
    WORKER_NODES="${WORKER_NODES:-}"
    CONTROLLER_NODES="${CONTROLLER_NODES:-}"
    CLIENT_IP_SUFFIX="${CLIENT_IP_SUFFIX:-}"
    LB_IP_SUFFIX="${LB_IP_SUFFIX:-}"
    CONTROLLERS_IP_START="${CONTROLLERS_IP_START:-}"
    WORKERS_IP_START="${WORKERS_IP_START:-}"
    export DOMAIN_NAME="${DOMAIN_NAME:-localhost}"
    export INCLUDE_DASHBOARD="${INCLUDE_DASHBOARD:-false}"
    export DASHBOARD_FORWARDED_PORT="${DASHBOARD_FORWARDED_PORT:-8888}"
    export DASHBOARD_LB_PORT="${DASHBOARD_LB_PORT:-443}"
    if [ ! "${DOMAIN_NAME}" = "localhost" ]; then
        export FQDN="${DOMAIN_NAME}"
    fi
    # we are in a vagrant vm, keep the default path
    export ETC_HOSTS=/etc/hosts
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
        # centos
        if [ ! "$(hostnamectl | grep centos 2>/dev/null || echo "no")" = "no" ];then
            sudo yum  -y install epel-release && sudo yum --enablerepo=epel -y install sshpass
        else
            # fedora?
            sudo dnf install sshpass -y
        fi
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
    cat > script.sh <<EOF
sudo sed -i -E 's/^#?PasswordAuthentication yes.*/PasswordAuthentication no/g' /etc/ssh/sshd_config
if command -v systemctl &> /dev/null; then
    if command -v apt &> /dev/null; then
        sudo systemctl restart ssh
    else
        sudo systemctl restart sshd
    fi
elif [ -f /etc/init.d/ssh ]; then
    sudo /etc/init.d/ssh restart
else
    sudo kill -HUP \$(cat /var/run/sshd.pid)
fi
EOF
    sshpass -p 'vagrant' ssh-copy-id "vagrant@${1}"
    scp script.sh "vagrant@${1}:~/"
    ssh "vagrant@${1}" bash script.sh
    ssh "vagrant@${1}" rm script.sh
    rm script.sh
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
chmod 600 ~/.ssh/config && chown vagrant ~/.ssh/config
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
            # let's wait for all instances to be up in case we are running with --parallel
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


main "${@}"
if [ -f z2k.sh ];then
  bash z2k.sh --skip-checks
fi
exit 0
