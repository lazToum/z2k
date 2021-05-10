#!/bin/bash
# shellcheck disable=SC2002,SC2029
set -e

_ETC_HOSTS="${ETC_HOSTS:-/etc/hosts}"
if [ ! -f "${_ETC_HOSTS}" ];then _ETC_HOSTS=/etc/hosts; fi

# v1.21.0
kubectl_version="$(curl -L -s https://dl.k8s.io/release/stable.txt)"
# 1.21.0
cri_tools_version="$(curl -w '%{redirect_url}' -o /dev/null -s https://github.com/kubernetes-sigs/cri-tools/releases/latest | sed 's:\(.*/tag/v\)\(.*\):\2:')"
# 1.0.rc93
runc_version="$(curl -w '%{redirect_url}' -o /dev/null -s https://github.com/opencontainers/runc/releases/latest | sed 's:\(.*/tag/v\)\(.*\):\2:')"
# 0.9.1
cni_plugins_version="$(curl -w '%{redirect_url}' -o /dev/null -s https://github.com/containernetworking/plugins/releases/latest | sed 's:\(.*/tag/v\)\(.*\):\2:')"
# 1.5.0
containerd_version="$(curl -w '%{redirect_url}' -o /dev/null -s https://github.com/containerd/containerd/releases/latest | sed 's:\(.*/tag/v\)\(.*\):\2:')"

function make_setup_script() {
    local _name="${1}"
    local _hostname="${2}"
    cat >"${_name}" <<EOFF
if command -v apt &> /dev/null; then
    sudo apt update && sudo apt install -y socat conntrack ipset wget systemd kmod btrfs-progs
elif command -v dnf &> /dev/null; then
    sudo dnf install install -y socat conntrack ipset wget systemd kmod btrfs-progs-devel
elif command -v yum &> /dev/null; then
    sudo yum install install -y socat conntrack ipset wget systemd kmod btrfs-progs-devel
fi
 if [ ! $(ls /dev/kmsg 2>/dev/null) ] ;then
    sudo ln -s /dev/console /dev/kmsg
fi
mkdir -p ~/.kube
if [ -f admin.kubeconfig ];then
  if [ ! -f ~/.kube/config ]; then
      cp admin.kubeconfig ~/.kube/config
  fi
fi
sudo sysctl net.ipv4.ip_forward=1
if [ ! "\$(sysctl net.ipv4.ip_forward | cut -d= -f2 | tr -d " " 2>/dev/null || echo 0)" = "1" ];then
    echo 'sysctl net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf
fi
sudo swapoff -a &>/dev/null
wget -q --show-progress --https-only --timestamping \
  "https://github.com/kubernetes-sigs/cri-tools/releases/download/v${cri_tools_version}/crictl-v${cri_tools_version}-linux-amd64.tar.gz" \
  "https://github.com/opencontainers/runc/releases/download/v${runc_version}/runc.amd64" \
  "https://github.com/containernetworking/plugins/releases/download/v${cni_plugins_version}/cni-plugins-linux-amd64-v${cni_plugins_version}.tgz" \
  "https://github.com/containerd/containerd/releases/download/v${containerd_version}/containerd-${containerd_version}-linux-amd64.tar.gz" \
  "https://storage.googleapis.com/kubernetes-release/release/${kubectl_version}/bin/linux/amd64/kubectl" \
  "https://storage.googleapis.com/kubernetes-release/release/${kubectl_version}/bin/linux/amd64/kube-proxy" \
  "https://storage.googleapis.com/kubernetes-release/release/${kubectl_version}/bin/linux/amd64/kubelet"

URL=https://storage.googleapis.com/gvisor/releases/release/latest
wget \${URL}/runsc \${URL}/runsc.sha512 \\
     \${URL}/gvisor-containerd-shim \${URL}/gvisor-containerd-shim.sha512 \\
     \${URL}/containerd-shim-runsc-v1 \${URL}/containerd-shim-runsc-v1.sha512
sha512sum -c runsc.sha512 \\
    -c gvisor-containerd-shim.sha512 \\
    -c containerd-shim-runsc-v1.sha512
rm -f *.sha512
chmod a+rx runsc gvisor-containerd-shim containerd-shim-runsc-v1
sudo mv runsc gvisor-containerd-shim containerd-shim-runsc-v1 /usr/local/bin/

sudo mkdir -p \
  /etc/cni/net.d \
  /opt/cni/bin \
  /var/lib/kubelet \
  /var/lib/kube-proxy \
  /var/lib/kubernetes \
  /var/run/kubernetes \
  /var/run/containerd

mkdir containerd
  tar -xvf "crictl-v${cri_tools_version}-linux-amd64.tar.gz"
  tar -xvf "containerd-${containerd_version}-linux-amd64.tar.gz" -C containerd
  sudo tar -xvf "cni-plugins-linux-amd64-v${cni_plugins_version}.tgz" -C /opt/cni/bin/
  sudo mv runc.amd64 runc
  chmod +x crictl kubectl kube-proxy kubelet runc
  sudo mv crictl kubectl kube-proxy kubelet runc /usr/local/bin/
  sudo mv containerd/bin/* /bin/
  rm "crictl-v${cri_tools_version}-linux-amd64.tar.gz" "containerd-${containerd_version}-linux-amd64.tar.gz" "cni-plugins-linux-amd64-v${cni_plugins_version}.tgz" &>/dev/null

sudo mkdir -p /etc/containerd/

cat << EOF | sudo tee /etc/containerd/config.toml
[plugins]
  [plugins.cri.containerd]
    snapshotter = "overlayfs"
    [plugins.cri.containerd.default_runtime]
      runtime_type = "io.containerd.runtime.v1.linux"
      runtime_engine = "/usr/local/bin/runc"
      runtime_root = ""
    [plugins.cri.containerd.untrusted_workload_runtime]
      runtime_type = "io.containerd.runtime.v1.linux"
      runtime_engine = "/usr/local/bin/runsc"
      runtime_root = "/var/run/containerd/runsc"
EOF

cat <<EOF | sudo tee /etc/systemd/system/containerd.service
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target

[Service]
ExecStartPre=/sbin/modprobe overlay
ExecStart=/bin/containerd
Restart=always
RestartSec=5
Delegate=yes
KillMode=process
OOMScoreAdjust=-999
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity

[Install]
WantedBy=multi-user.target
EOF

sudo mv "${_hostname}-key.pem" "${_hostname}.pem" /var/lib/kubelet/
sudo mv "${_hostname}.kubeconfig" /var/lib/kubelet/kubeconfig
sudo mv ca.pem /var/lib/kubernetes/

cat <<EOF | sudo tee /var/lib/kubelet/kubelet-config.yaml
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: "/var/lib/kubernetes/ca.pem"
authorization:
  mode: Webhook
clusterDomain: "cluster.local"
clusterDNS:
  - "10.32.0.10"

resolvConf: "/run/systemd/resolve/resolv.conf"
runtimeRequestTimeout: "15m"
streamingConnectionIdleTimeout: "24h"
tlsCertFile: "/var/lib/kubelet/${_hostname}.pem"
tlsPrivateKeyFile: "/var/lib/kubelet/${_hostname}-key.pem"
EOF

cat <<EOF | sudo tee /etc/systemd/system/kubelet.service
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=containerd.service
Requires=containerd.service

[Service]
ExecStart=/usr/local/bin/kubelet \\
  --config=/var/lib/kubelet/kubelet-config.yaml \\
  --container-runtime=remote \\
  --container-runtime-endpoint=unix:///var/run/containerd/containerd.sock \\
  --image-pull-progress-deadline=2m \\
  --kubeconfig=/var/lib/kubelet/kubeconfig \\
  --network-plugin=cni \\
  --register-node=true \\
  --v=2 \\
  --hostname-override="${_hostname}" \\
  --fail-swap-on=false
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo mv kube-proxy.kubeconfig /var/lib/kube-proxy/kubeconfig

cat <<EOF | sudo tee /var/lib/kube-proxy/kube-proxy-config.yaml
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
clientConnection:
  kubeconfig: "/var/lib/kube-proxy/kubeconfig"
mode: "iptables"
clusterCIDR: "10.200.0.0/16"
EOF

cat <<EOF | sudo tee /etc/systemd/system/kube-proxy.service
[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-proxy \\
  --config=/var/lib/kube-proxy/kube-proxy-config.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable containerd kubelet kube-proxy
sudo systemctl start containerd kubelet kube-proxy
sudo systemctl status containerd kubelet kube-proxy
EOFF
}

ORIGINAL_IFS=$IFS
IFS=" " read -r -a _worker_names <<< "$(cat "${_ETC_HOSTS}" | grep worker | awk '{print $2}' | cut -d. -f1 | xargs)"
for i in "${!_worker_names[@]}"; do
    _worker="${_worker_names[i]}"
    make_setup_script "setup-${_worker}.sh" "${_worker}"
    scp "setup-${_worker}.sh" "${_worker}":~/ && ssh "${_worker}" bash "setup-${_worker}.sh"
    ssh "${_worker}" rm "setup-${_worker}.sh"
    rm "setup-${_worker}.sh"
done
IFS=$ORIGINAL_IFS
sleep 5
a_controller="$(cat "${_ETC_HOSTS}" | grep controller | tail -1 | awk '{ print $1 }')"
ssh "${a_controller}" "kubectl get nodes"
