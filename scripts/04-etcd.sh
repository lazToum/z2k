#!/bin/bash
# shellcheck disable=SC2002,SC2029
set -e

_ETC_HOSTS="${ETC_HOSTS:-/etc/hosts}"
if [ ! -f "${_ETC_HOSTS}" ];then _ETC_HOSTS=/etc/hosts; fi

ETCD_VER=v3.4.15

function make_setup_script() {
    local _name="${1}"
    local _internal_ip="${2}"
    local _initial_cluster="${3}"
    cat >"${_name}" <<EOFF
#!/bin/bash
function ensure_command() {
    if ! command -v \${1} &> /dev/null; then
        if command -v apt &> /dev/null; then
            sudo apt update && sudo apt install \${2} -y
        elif command -v dnf &> /dev/null; then
            sudo dnf install \${3} -y
        elif command -v yum &> /dev/null; then
            sudo yum install \${3} -y
        fi
    fi
}
ensure_command wget wget wget
ensure_command systemctl systemctl systemd
wget -q --show-progress --https-only --timestamping \
    "https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz"
tar -xvf etcd-${ETCD_VER}-linux-amd64.tar.gz && rm etcd-${ETCD_VER}-linux-amd64.tar.gz
sudo mv etcd-${ETCD_VER}-linux-amd64/etcd* /usr/local/bin/
rm -rf etcd-${ETCD_VER}-linux-amd64
sudo mkdir -p /etc/etcd /var/lib/etcd
sudo chmod 700 /var/lib/etcd
sudo cp ca.pem kubernetes-key.pem kubernetes.pem /etc/etcd/
cat <<EOF | sudo tee /etc/systemd/system/etcd.service
[Unit]
Description=etcd
Documentation=https://github.com/coreos

[Service]
Type=notify
ExecStart=/usr/local/bin/etcd \\
    --name \$(hostname -s) \\
    --cert-file=/etc/etcd/kubernetes.pem \\
    --key-file=/etc/etcd/kubernetes-key.pem \\
    --peer-cert-file=/etc/etcd/kubernetes.pem \\
    --peer-key-file=/etc/etcd/kubernetes-key.pem \\
    --trusted-ca-file=/etc/etcd/ca.pem \\
    --peer-trusted-ca-file=/etc/etcd/ca.pem \\
    --peer-client-cert-auth \\
    --client-cert-auth \\
    --initial-advertise-peer-urls https://${_internal_ip}:2380 \\
    --listen-peer-urls https://${_internal_ip}:2380 \\
    --listen-client-urls https://${_internal_ip}:2379,https://127.0.0.1:2379 \\
    --advertise-client-urls https://${_internal_ip}:2379 \\
    --initial-cluster-token etcd-cluster-0 \\
    --initial-cluster ${_initial_cluster} \\
    --initial-cluster-state new \\
    --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable etcd
sudo systemctl start etcd &>/dev/null || :
sleep 5
sudo systemctl restart etcd &>/dev/null || :
sudo ETCDCTL_API=3 etcdctl member list \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/etcd/ca.pem \
    --cert=/etc/etcd/kubernetes.pem \
    --key=/etc/etcd/kubernetes-key.pem 2> /dev/null || :
EOFF

}
ORIGINAL_IFS=$IFS
IFS=" " read -r -a _controller_names <<< "$(cat "${_ETC_HOSTS}" | grep controller | awk '{print $2}' | cut -d. -f1 | xargs)"
IFS=" " read -r -a _controller_ips <<< "$(cat "${_ETC_HOSTS}" | grep controller | awk '{print $1}' | xargs)"
initial_cluster="$(cat "${_ETC_HOSTS}" | grep controller | awk '{print $3"=https://"$1":2380"}' | xargs | sed -e "s/[[:space:]]/,/g")"
for i in "${!_controller_names[@]}"; do
    _controller="${_controller_names[$i]}"
    _ip="${_controller_ips[$i]}"
    make_setup_script "etcd-${_controller}.sh" "${_ip}" "${initial_cluster}"
    # shellcheck disable=SC2029
    scp "etcd-${_controller}.sh" "${_ip}":~/ && ssh "${_ip}" bash "etcd-${_controller}.sh"
    ssh "${_ip}" rm "etcd-${_controller}.sh"
    rm "etcd-${_controller}.sh"
done
IFS=$ORIGINAL_IFS
