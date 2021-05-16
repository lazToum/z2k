#!/bin/bash
# shellcheck disable=SC2002,SC2029
set -e

_ETC_HOSTS="${ETC_HOSTS:-/etc/hosts}"
if [ ! -f "${_ETC_HOSTS}" ];then _ETC_HOSTS=/etc/hosts; fi
INCLUDE_DASHBOARD="${INCLUDE_DASHBOARD:-false}"
load_balancer="$(cat "${_ETC_HOSTS}" | grep balancer | tail -1 | awk '{print $1}')"
one_controller="$(cat "${_ETC_HOSTS}" | grep controller | tail -1 | awk '{print $1}')"

function test_encryption() {
    ssh "${load_balancer}" "kubectl create secret generic kubernetes-the-hard-way --from-literal=\"mykey=mydata\""
    sleep 5
    echo "checikng for: k8s:enc:aescbc:v1:key1"
    ssh "${one_controller}" "sudo ETCDCTL_API=3 etcdctl get --endpoints=https://127.0.0.1:2379 --cacert=/etc/etcd/ca.pem --cert=/etc/etcd/kubernetes.pem --key=/etc/etcd/kubernetes-key.pem /registry/secrets/default/kubernetes-the-hard-way | hexdump -C   -e'100/1 \"%_p\"' | grep k8s:enc:aescbc:v1:key1"
    ssh "${one_controller}" "sudo ETCDCTL_API=3 etcdctl get --endpoints=https://127.0.0.1:2379 --cacert=/etc/etcd/ca.pem --cert=/etc/etcd/kubernetes.pem --key=/etc/etcd/kubernetes-key.pem /registry/secrets/default/kubernetes-the-hard-way | hexdump -C"
    # cleanup
    ssh "${load_balancer}" "kubectl delete secret kubernetes-the-hard-way"
}

function test_deploy_exec_svc() {
cat >lb.sh <<EOFF
#!/bin/bash
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
if [ "${INCLUDE_DASHBOARD}" = "false" ]; then
  echo "cleanup..."
  kubectl delete deployment busybox
  kubectl delete deployment nginx
  kubectl delete svc nginx
fi
EOFF
}

# one last:
# if [ "${INCLUDE_DASHBOARD}" = "false" ]; then
    # port forwaring (in case we don't want the dashboard installation on the next step)
# fi
test_encryption
test_deploy_exec_svc
scp lb.sh certs/ca.pem certs/ca-key.pem certs/admin.pem certs/admin-key.pem "${load_balancer}":~/ && ssh "${load_balancer}" "bash lb.sh && rm lb.sh"
rm lb.sh
