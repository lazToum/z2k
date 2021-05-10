#!/bin/bash
# shellcheck disable=SC2002,SC2029

load_balancer="$(cat /etc/hosts | grep balancer | tail -1 | awk '{print $1}')"

# optional: get a certbot certificate on load balancer
_domain_name=${DOMAIN_NAME:-localhost}

cat >lb.sh <<EOFF
#!/bin/bash
kubectl get nodes
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0/aio/deploy/recommended.yaml
echo "sleeping for a while..."
sleep 30
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
EOF

cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
EOF
echo "trying to get a token for dashboard login..."
sleep 5
KUBE_TOKEN="\$(kubectl -n kubernetes-dashboard get secret \$(kubectl -n kubernetes-dashboard get sa/admin-user -o jsonpath="{.secrets[0].name}") -o go-template="{{.data.token | base64decode}}")"
echo "\${KUBE_TOKEN}" > .dashboard_token

mkdir -p ~/bin && cd ~/bin
cat >dashboard.sh <<EOF
#!/bin/bash
while true; do
  /usr/local/bin/kubectl port-forward --address 0.0.0.0 -n kubernetes-dashboard service/kubernetes-dashboard 8888:443
done
EOF
chmod +x dashboard.sh

cat <<EOF | sudo tee /etc/systemd/system/kube-dashboard.service
[Unit]
Description=Kubernetes Dashboard port forwarding
Documentation=https://github.com/kubernetes/kubernetes

[Service]
User=\$(id -u)
Group=\$(id -g)
ExecStart=\$(pwd)/dashboard.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
cat <<EOF | sudo tee /etc/nginx/ssl/${_domain_name}.conf;
server {
    listen 443;
    proxy_pass 127.0.0.1:8888;
}
EOF
sudo systemctl daemon-reload
sudo systemctl enable kube-dashboard && sudo systemctl start kube-dashboard
systemctl status kube-dashboard
sudo systemctl restart nginx
EOFF

function make_certbot() {
  cat >certbot.sh <<EOFF
sudo snap install core && sudo snap refresh core
sudo snap install --classic certbot
sudo ln -s /snap/bin/certbot /usr/bin/certbot
sudo systemctl stop nginx kube-dashboard
sudo certbot certonly --standalone --non-interactive --agree-tos --register-unsafely-without-email -d "${_domain_name}"
sudo mkdir -p /etc/nginx/ssl
cat <<EOF | sudo tee /etc/nginx/ssl/${_domain_name}.conf;
server {
    listen 443 ssl;
    ssl_certificate /etc/letsencrypt/live/${_domain_name}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${_domain_name}/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/${_domain_name}/chain.pem;
    ssl_session_cache shared:le_nginx_SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384";
    proxy_pass 127.0.0.1:8888;
    proxy_ssl on;
    proxy_ssl_session_reuse on;
}
EOF
sudo nginx -t
sudo systemctl start kube-dashboard nginx
EOFF
}
scp lb.sh "${load_balancer}":~/ && ssh "${load_balancer}" bash lb.sh
ssh "${load_balancer}" rm lb.sh
rm lb.sh

if [ ! "${_domain_name}" = "localhost" ] && [ ! "${_domain_name}" = "" ]; then
  make_certbot
  scp certbot.sh "${load_balancer}":~/ && ssh "${load_balancer}" bash certbot.sh
  ssh "${load_balancer}" rm certbot.sh
  rm certbot.sh
fi
_dashboard_token="$(ssh -o StrictHostKeyChecking=no load-balancer cat .dashboard_token)"
ssh "${load_balancer}" rm .dashboard_token

echo "you might be able to login on \"https://${_domain_name}\""
echo "using the token:"
echo "${_dashboard_token}" > .dashboard_token
echo "${_dashboard_token}"
echo "you may also wish to copy it: ($(pwd)/.dashboard_token)"
