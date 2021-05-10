#!/bin/bash
# shellcheck disable=SC2002,SC2029
set -e

_ETC_HOSTS="${ETC_HOSTS:-/etc/hosts}"
if [ ! -f "${_ETC_HOSTS}" ];then _ETC_HOSTS=/etc/hosts; fi

load_balancer="$(cat "${_ETC_HOSTS}" | grep balancer | tail -1 | awk '{print $1}')"

# v1.21.0
kubectl_version="$(curl -L -s https://dl.k8s.io/release/stable.txt)"
cat >lb.sh <<EOFF
#!/bin/bash
if [ ! "\$(sysctl net.ipv4.ip_forward | cut -d= -f2 | tr -d " " 2>/dev/null || echo 0)" = "1" ];then
    echo 'sysctl net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf
fi
sudo sysctl net.ipv4.ip_forward=1

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
ensure_command jq jq jq
ensure_command curl curl curl
curl -LO "https://dl.k8s.io/release/${kubectl_version}/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/
kubectl config set-cluster kubernetes-the-hard-way \\
    --certificate-authority=ca.pem \\
    --embed-certs=true \\
    --server="https://localhost:6443"

kubectl config set-credentials admin \\
  --client-certificate=admin.pem \\
  --client-key=admin-key.pem

kubectl config set-context kubernetes-the-hard-way \\
  --cluster=kubernetes-the-hard-way \\
  --user=admin

kubectl config use-context kubernetes-the-hard-way

kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=\$(kubectl version | base64 | tr -d '\n')&env.IPALLOC_RANGE=10.200.0.0/16"
# coredns
curl -LO "https://raw.githubusercontent.com/coredns/deployment/master/kubernetes/coredns.yaml.sed"
curl -LO "https://raw.githubusercontent.com/coredns/deployment/master/kubernetes/deploy.sh"
chmod +x ./deploy.sh
./deploy.sh -i 10.32.0.10 | sed 's/# replicas: not specified here:/replicas: 2/' | kubectl apply -f -
sleep 30
rm deploy.sh coredns.yaml.sed
echo "test connectivity: 3 exposed nginx pods, 1 nginx svc, one busybox to access them"
cat << EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
    name: nginx
spec:
    selector:
        matchLabels:
            run: nginx
    replicas: 3
    template:
        metadata:
            labels:
                run: nginx
        spec:
            containers:
            - name: test-nginx
              image: nginx
              ports:
              - containerPort: 80
EOF
kubectl expose deployment/nginx
cat << EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: busybox
  labels:
    app: busybox
spec:
  replicas: 1
  strategy:
    type: RollingUpdate
  selector:
    matchLabels:
      app: busybox
  template:
    metadata:
      labels:
        app: busybox
    spec:
      containers:
      - name: busybox
        image: yauritux/busybox-curl
        imagePullPolicy: IfNotPresent
        command: ['sh', '-c', 'echo Container 1 is Running ; sleep 3600']
EOF
echo "sleeping for a while...."
sleep 60
kubectl get pods -o wide
pod_name=\$(kubectl get pods -l app=busybox -o jsonpath="{.items[0].metadata.name}")
nginx_one="\$(kubectl get ep nginx -o custom-columns="ip:subsets[0].addresses[0].ip" | tail -1)"
nginx_two="\$(kubectl get ep nginx -o custom-columns="ip:subsets[0].addresses[1].ip" | tail -1)"
nginx_three="\$(kubectl get ep nginx -o custom-columns="ip:subsets[0].addresses[2].ip" | tail -1)"
nginx_svc="\$(kubectl get svc nginx -o custom-columns="ip:spec.clusterIP" | tail -1)"
echo "nginx1: \${nginx_one}"
echo "nginx2: \${nginx_two}"
echo "nginx2: \${nginx_three}"
echo "nginx_svc: \${nginx_svc}"
kubectl exec "\${pod_name}" -- curl -m 10 -I "\${nginx_one}"
kubectl exec "\${pod_name}" -- curl -m 10 -I "\${nginx_two}"
kubectl exec "\${pod_name}" -- curl -m 10 -I "\${nginx_three}"
kubectl exec "\${pod_name}" -- curl -m 10 -I "\${nginx_svc}"
echo "test ccoredns"
kubectl exec -ti \$pod_name -- nslookup kubernetes
# let's keep them, and cleanup later from the dashboard ui
# kubectl delete deployment busybox
# kubectl delete deployment nginx
# kubectl delete svc nginx

EOFF

scp lb.sh certs/ca.pem certs/ca-key.pem certs/admin.pem certs/admin-key.pem "${load_balancer}":~/ && ssh "${load_balancer}" bash lb.sh
ssh "${load_balancer}" rm lb.sh
rm lb.sh
