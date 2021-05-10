#!/bin/bash
# shellcheck disable=SC2002,SC2029

# v1.21.0
kubectl_version="$(curl -L -s https://dl.k8s.io/release/stable.txt)"

function make_setup_script() {
    local _name="${1}"
    local _servers_count="${2}"
    local _internal_ip="${3}"
    local _external_ip="${4}"
    local _etcd_servers="${5}"
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
mkdir -p ~/.kube
if [ -f admin.kubeconfig ];then
  if [ ! -f ~/.kube/config ]; then
      cp admin.kubeconfig ~/.kube/config
  fi
fi
sudo mkdir -p /etc/kubernetes/config
wget -q --show-progress --https-only --timestamping \
    "https://storage.googleapis.com/kubernetes-release/release/${kubectl_version}/bin/linux/amd64/kube-apiserver" \
    "https://storage.googleapis.com/kubernetes-release/release/${kubectl_version}/bin/linux/amd64/kube-controller-manager" \
    "https://storage.googleapis.com/kubernetes-release/release/${kubectl_version}/bin/linux/amd64/kube-scheduler" \
    "https://storage.googleapis.com/kubernetes-release/release/${kubectl_version}/bin/linux/amd64/kubectl"
chmod +x kube-apiserver kube-controller-manager kube-scheduler kubectl
sudo mv kube-apiserver kube-controller-manager kube-scheduler kubectl /usr/local/bin/
sudo mkdir -p /var/lib/kubernetes/

sudo mv ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem \
    service-account-key.pem service-account.pem \
    encryption-config.yaml /var/lib/kubernetes/

cat <<EOF | sudo tee /etc/systemd/system/kube-apiserver.service
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-apiserver \\
  --advertise-address=${_internal_ip} \\
  --allow-privileged=true \\
  --apiserver-count=${_servers_count} \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/log/audit.log \\
  --authorization-mode=Node,RBAC \\
  --bind-address=0.0.0.0 \\
  --client-ca-file=/var/lib/kubernetes/ca.pem \\
  --enable-admission-plugins=NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \\
  --etcd-cafile=/var/lib/kubernetes/ca.pem \\
  --etcd-certfile=/var/lib/kubernetes/kubernetes.pem \\
  --etcd-keyfile=/var/lib/kubernetes/kubernetes-key.pem \\
  --etcd-servers=${_etcd_servers} \\
  --event-ttl=1h \\
  --encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml \\
  --kubelet-certificate-authority=/var/lib/kubernetes/ca.pem \\
  --kubelet-client-certificate=/var/lib/kubernetes/kubernetes.pem \\
  --kubelet-client-key=/var/lib/kubernetes/kubernetes-key.pem \\
  --runtime-config='api/all=true' \\
  --service-account-key-file=/var/lib/kubernetes/service-account.pem \\
  --service-account-signing-key-file=/var/lib/kubernetes/service-account-key.pem \\
  --service-account-issuer=https://${_external_ip}:6443 \\
  --service-cluster-ip-range=10.32.0.0/24 \\
  --service-node-port-range=30000-32767 \\
  --tls-cert-file=/var/lib/kubernetes/kubernetes.pem \\
  --tls-private-key-file=/var/lib/kubernetes/kubernetes-key.pem \\
  --v=2 \\
  --kubelet-preferred-address-types=InternalIP,InternalDNS,Hostname,ExternalIP,ExternalDNS
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo mv kube-controller-manager.kubeconfig /var/lib/kubernetes/
cat <<EOF | sudo tee /etc/systemd/system/kube-controller-manager.service
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \\
  --bind-address=0.0.0.0 \\
  --cluster-cidr=10.200.0.0/16 \\
  --cluster-name=kubernetes \\
  --cluster-signing-cert-file=/var/lib/kubernetes/ca.pem \\
  --cluster-signing-key-file=/var/lib/kubernetes/ca-key.pem \\
  --kubeconfig=/var/lib/kubernetes/kube-controller-manager.kubeconfig \\
  --leader-elect=true \\
  --root-ca-file=/var/lib/kubernetes/ca.pem \\
  --service-account-private-key-file=/var/lib/kubernetes/service-account-key.pem \\
  --service-cluster-ip-range=10.32.0.0/24 \\
  --use-service-account-credentials=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo mv kube-scheduler.kubeconfig /var/lib/kubernetes/

cat <<EOF | sudo tee /etc/kubernetes/config/kube-scheduler.yaml
apiVersion: kubescheduler.config.k8s.io/v1beta1
kind: KubeSchedulerConfiguration
clientConnection:
  kubeconfig: "/var/lib/kubernetes/kube-scheduler.kubeconfig"
leaderElection:
  leaderElect: true
EOF
cat <<EOF | sudo tee /etc/systemd/system/kube-scheduler.service
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-scheduler \\
  --config=/etc/kubernetes/config/kube-scheduler.yaml \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable kube-apiserver kube-controller-manager kube-scheduler
sudo systemctl start kube-apiserver kube-controller-manager kube-scheduler
ensure_command nginx nginx nginx
cat > kubernetes.default.svc.cluster.local <<EOF
server {
  listen      80;
  server_name kubernetes.default.svc.cluster.local;

  location /healthz {
     proxy_pass    https://127.0.0.1:6443/healthz;
     proxy_ssl_trusted_certificate /var/lib/kubernetes/ca.pem;
  }
}
EOF
sudo mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
sudo mv kubernetes.default.svc.cluster.local \
    /etc/nginx/sites-available/kubernetes.default.svc.cluster.local

sudo ln -s /etc/nginx/sites-available/kubernetes.default.svc.cluster.local /etc/nginx/sites-enabled/
sudo systemctl restart nginx
sudo systemctl enable nginx
kubectl cluster-info --kubeconfig admin.kubeconfig
curl -H "Host: kubernetes.default.svc.cluster.local" -i http://127.0.0.1/healthz
cat <<EOF | kubectl apply --kubeconfig admin.kubeconfig -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:kube-apiserver-to-kubelet
rules:
  - apiGroups:
      - ""
    resources:
      - nodes/proxy
      - nodes/stats
      - nodes/log
      - nodes/spec
      - nodes/metrics
    verbs:
      - "*"
EOF
cat <<EOF | kubectl apply --kubeconfig admin.kubeconfig -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:kube-apiserver
  namespace: ""
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kube-apiserver-to-kubelet
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: kubernetes
EOF
EOFF
}

function setup_load_balancer() {
    local controllers_entries; controllers_entries="$(cat /etc/hosts | grep controller | awk '{print "\tserver "$1":6443;"}')"
cat >"lb.sh" <<EOFF
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
ensure_command systemctl systemctl systemd
ensure_command nginx nginx nginx
ensure_command nginx nginx nginx
sudo systemctl start nginx && sudo systemctl enable nginx
sudo mkdir -p /etc/nginx/ssl
echo "include /etc/nginx/kubernetes.conf;" | sudo tee -a /etc/nginx/nginx.conf;

cat <<EOF | sudo tee /etc/nginx/kubernetes.conf
stream {
    upstream kubernetes {
${controllers_entries}
    }
    server {
        listen 6443;
        proxy_pass kubernetes;
    }
    include /etc/nginx/ssl/*conf;
}
EOF
sudo systemctl restart nginx
EOFF
    scp "lb.sh" "${1}":~/ && ssh "${1}" bash "lb.sh"
    ssh "${1}" rm "lb.sh"
    rm "lb.sh"
}
ORIGINAL_IFS=$IFS
IFS=" " read -r -a _controller_names <<< "$(cat /etc/hosts | grep controller | awk '{print $2}' | cut -d. -f1 | xargs)"
IFS=" " read -r -a _controller_ips <<< "$(cat /etc/hosts | grep controller | awk '{print $1}' | xargs)"
etcd_servers="$(cat /etc/hosts | grep controller | awk '{print "https://"$1":2379"}' | xargs | sed -e "s/[[:space:]]/,/g")"
servers_count="${#_controller_names[@]}"
load_balancer="$(cat /etc/hosts | grep balancer | tail -1 | awk '{print $1}')"
for i in "${!_controller_names[@]}"; do
    _controller="${_controller_names[$i]}"
    _ip="${_controller_ips[$i]}"
    make_setup_script "setup-${_controller}.sh" "${servers_count}" "${_ip}" "${load_balancer}" "${etcd_servers}"
    scp "setup-${_controller}.sh" "${_ip}":~/ && ssh "${_ip}" bash "setup-${_controller}.sh"
    ssh "${_ip}" rm "setup-${_controller}.sh"
    rm "setup-${_controller}.sh"
done
setup_load_balancer "${load_balancer}"
curl --cacert certs/ca.pem  "https://${load_balancer}:6443/version"
IFS=$ORIGINAL_IFS
