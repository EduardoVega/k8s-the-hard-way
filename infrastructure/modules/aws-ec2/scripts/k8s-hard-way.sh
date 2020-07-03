#!/bin/bash

set -xe

# Variables
K8S_VERSION="v1.18.0"
CNI_PLUGINS="v0.8.5"
ETCD_VER="v3.4.7"
LOAD_BALANCER="k8s-frozenmango-145957a6439e6d74.elb.us-east-1.amazonaws.com"
CP01="10.0.0.120"
CP02="10.0.1.58"
CP03="10.0.2.36"
CP01_NAME="ip-$(echo $CP01 | sed 's/\./-/g')"
CP02_NAME="ip-$(echo $CP02 | sed 's/\./-/g')"
CP03_NAME="ip-$(echo $CP03 | sed 's/\./-/g')"
W01="10.0.10.49"
W02="10.0.11.45"
W03="10.0.12.105"
SSH_KEY="/home/ubuntu/ssh-key.pem"
UUID=$(dbus-uuidgen)
TOKEN_ID=${UUID:0:6}
TOKEN_SECRET=${UUID:7:16}
TOKEN_EXPIRATION=$(date -d "$(date -u +%Y-%m-%dT%H:%M:%SZ) + 1 months" +%Y-%m-%dT%H:%M:%SZ)


# Work directory
mkdir -p /opt/k8s
cd /opt/k8s

##################################################
# PKI
##################################################

# Comment line starting with RANDFILE in /etc/ssl/openssl.cnf definition to avoid permission issues
sed -i '0,/RANDFILE/{s/RANDFILE/\#&/}' /etc/ssl/openssl.cnf

# Create CA certificate
openssl genrsa -out ca.key 2048
openssl req -new -key ca.key -subj "/CN=KUBERNETES-CA" -out ca.csr
openssl x509 -req -in ca.csr -signkey ca.key -CAcreateserial  -out ca.crt -days 1000

# Generate Admin user certificate
openssl genrsa -out admin.key 2048
openssl req -new -key admin.key -subj "/CN=admin/O=system:masters" -out admin.csr
openssl x509 -req -in admin.csr -CA ca.crt -CAkey ca.key -CAcreateserial  -out admin.crt -days 1000

# Generate kube controller manager certificate
openssl genrsa -out kube-controller-manager.key 2048
openssl req -new -key kube-controller-manager.key -subj "/CN=system:kube-controller-manager" -out kube-controller-manager.csr
openssl x509 -req -in kube-controller-manager.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out kube-controller-manager.crt -days 1000

# Generate kube proxy certificate
openssl genrsa -out kube-proxy.key 2048
openssl req -new -key kube-proxy.key -subj "/CN=system:kube-proxy" -out kube-proxy.csr
openssl x509 -req -in kube-proxy.csr -CA ca.crt -CAkey ca.key -CAcreateserial  -out kube-proxy.crt -days 1000

# Generate kube scheduler certificate
openssl genrsa -out kube-scheduler.key 2048
openssl req -new -key kube-scheduler.key -subj "/CN=system:kube-scheduler" -out kube-scheduler.csr
openssl x509 -req -in kube-scheduler.csr -CA ca.crt -CAkey ca.key -CAcreateserial  -out kube-scheduler.crt -days 1000

# Generate kube API server certificate
cat > openssl.cnf <<EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = kubernetes
DNS.2 = kubernetes.default
DNS.3 = kubernetes.default.svc
DNS.4 = kubernetes.default.svc.cluster.local
DNS.5 = ${LOAD_BALANCER}
IP.1 = 10.96.0.1
IP.2 = ${CP01}
IP.3 = ${CP02}
IP.4 = ${CP03}
IP.5 = 127.0.0.1
EOF

openssl genrsa -out kube-apiserver.key 2048
openssl req -new -key kube-apiserver.key -subj "/CN=kube-apiserver" -out kube-apiserver.csr -config openssl.cnf
openssl x509 -req -in kube-apiserver.csr -CA ca.crt -CAkey ca.key -CAcreateserial  -out kube-apiserver.crt -extensions v3_req -extfile openssl.cnf -days 1000

# Generate ETCD certificate
cat > openssl-etcd.cnf <<EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names
[alt_names]
IP.1 = ${CP01}
IP.2 = ${CP02}
IP.3 = ${CP03}
IP.4 = 127.0.0.1
EOF

openssl genrsa -out etcd-server.key 2048
openssl req -new -key etcd-server.key -subj "/CN=etcd-server" -out etcd-server.csr -config openssl-etcd.cnf
openssl x509 -req -in etcd-server.csr -CA ca.crt -CAkey ca.key -CAcreateserial  -out etcd-server.crt -extensions v3_req -extfile openssl-etcd.cnf -days 1000

# Generate service account certificate
openssl genrsa -out service-account.key 2048
openssl req -new -key service-account.key -subj "/CN=service-accounts" -out service-account.csr
openssl x509 -req -in service-account.csr -CA ca.crt -CAkey ca.key -CAcreateserial  -out service-account.crt -days 1000

# Create k8s directory in other nodes
for instance in $CP02 $CP03 $W01 $W02 $W03; do
    ssh -i ${SSH_KEY} -t -oStrictHostKeyChecking=no ubuntu@${instance} "sudo mkdir -p /opt/k8s; sudo chmod 777 /opt/k8s"  
done

# Copy CA, API server, etcd and service account certs to controller planes
for instance in $CP02 $CP03; do
  scp -i ${SSH_KEY} \
    ca.crt ca.key \
    kube-apiserver.key kube-apiserver.crt \
    service-account.key service-account.crt \
    etcd-server.key etcd-server.crt \
    ubuntu@${instance}:/opt/k8s
done

##################################################
# CLIENT KUBECONFIG
##################################################

# Create config file for kube proxy
kubectl config set-cluster kubernetes-the-hard-way \
--certificate-authority=ca.crt \
--embed-certs=true \
--server=https://${LOAD_BALANCER}:6443 \
--kubeconfig=kube-proxy.kubeconfig

kubectl config set-credentials system:kube-proxy \
--client-certificate=kube-proxy.crt \
--client-key=kube-proxy.key \
--embed-certs=true \
--kubeconfig=kube-proxy.kubeconfig

kubectl config set-context default \
--cluster=kubernetes-the-hard-way \
--user=system:kube-proxy \
--kubeconfig=kube-proxy.kubeconfig

kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig

# Create config file for kube controller manager
kubectl config set-cluster kubernetes-the-hard-way \
--certificate-authority=ca.crt \
--embed-certs=true \
--server=https://127.0.0.1:6443 \
--kubeconfig=kube-controller-manager.kubeconfig

kubectl config set-credentials system:kube-controller-manager \
--client-certificate=kube-controller-manager.crt \
--client-key=kube-controller-manager.key \
--embed-certs=true \
--kubeconfig=kube-controller-manager.kubeconfig

kubectl config set-context default \
--cluster=kubernetes-the-hard-way \
--user=system:kube-controller-manager \
--kubeconfig=kube-controller-manager.kubeconfig

kubectl config use-context default --kubeconfig=kube-controller-manager.kubeconfig

# Create config file for kube scheduler
kubectl config set-cluster kubernetes-the-hard-way \
--certificate-authority=ca.crt \
--embed-certs=true \
--server=https://127.0.0.1:6443 \
--kubeconfig=kube-scheduler.kubeconfig

kubectl config set-credentials system:kube-scheduler \
--client-certificate=kube-scheduler.crt \
--client-key=kube-scheduler.key \
--embed-certs=true \
--kubeconfig=kube-scheduler.kubeconfig

kubectl config set-context default \
--cluster=kubernetes-the-hard-way \
--user=system:kube-scheduler \
--kubeconfig=kube-scheduler.kubeconfig

kubectl config use-context default --kubeconfig=kube-scheduler.kubeconfig

# Create config file for the admin user
kubectl config set-cluster kubernetes-the-hard-way \
--certificate-authority=ca.crt \
--embed-certs=true \
--server=https://${LOAD_BALANCER}:6443 \
--kubeconfig=admin.kubeconfig

kubectl config set-credentials admin \
--client-certificate=admin.crt \
--client-key=admin.key \
--embed-certs=true \
--kubeconfig=admin.kubeconfig

kubectl config set-context default \
--cluster=kubernetes-the-hard-way \
--user=admin \
--kubeconfig=admin.kubeconfig

kubectl config use-context default --kubeconfig=admin.kubeconfig

# Copy kube proxy config file to workers
for instance in $W01 $W02 $W03; do
  scp -i ${SSH_KEY} kube-proxy.kubeconfig ubuntu@${instance}:/opt/k8s
done

# Copy kube scheduler, kube controller manager and admin config files to controller planes
for instance in $CP02 $CP03; do
  scp -i ${SSH_KEY} admin.kubeconfig kube-controller-manager.kubeconfig kube-scheduler.kubeconfig ubuntu@${instance}:/opt/k8s
done

##################################################
# ETCD SET UP
##################################################

cat > etcd-template.service <<EOF
[Unit]
Description=etcd
Documentation=https://github.com/etcd-io/etcd

[Service]
ExecStart=/usr/local/bin/etcd \\
  --name ETCD_NAME \\
  --cert-file=/etc/etcd/etcd-server.crt \\
  --key-file=/etc/etcd/etcd-server.key \\
  --peer-cert-file=/etc/etcd/etcd-server.crt \\
  --peer-key-file=/etc/etcd/etcd-server.key \\
  --trusted-ca-file=/etc/etcd/ca.crt \\
  --peer-trusted-ca-file=/etc/etcd/ca.crt \\
  --peer-client-cert-auth \\
  --client-cert-auth \\
  --initial-advertise-peer-urls https://INTERNAL_IP:2380 \\
  --listen-peer-urls https://INTERNAL_IP:2380 \\
  --listen-client-urls https://INTERNAL_IP:2379,https://127.0.0.1:2379 \\
  --advertise-client-urls https://INTERNAL_IP:2379 \\
  --initial-cluster-token etcd-cluster-0 \\
  --initial-cluster ${CP01_NAME}=https://${CP01}:2380,${CP02_NAME}=https://${CP02}:2380,${CP03_NAME}=https://${CP03}:2380 \\
  --initial-cluster-state new \\
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > etcd-conf.sh <<EOF
#!/bin/bash

set -xe

cd /opt/k8s

wget -q --show-progress --https-only --timestamping \
  "https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz"

tar -xvf etcd-${ETCD_VER}-linux-amd64.tar.gz
rm -rf etcd-${ETCD_VER}-linux-amd64.tar.gz
mv etcd-${ETCD_VER}-linux-amd64/etcd* /usr/local/bin/

mkdir -p /etc/etcd /var/lib/etcd
cp /opt/k8s/ca.crt /opt/k8s/etcd-server.key /opt/k8s/etcd-server.crt /etc/etcd/

NET_INTERFACE=\$(netstat -i | grep -vE "(lo|dock)" | tail -n 1 | cut -d" " -f1)
INTERNAL_IP=\$(ip addr show \$NET_INTERFACE | grep "inet " | awk '{print \$2}' | cut -d / -f 1)
ETCD_NAME=\$(hostname -s)

echo \$NET_INTERFACE
echo \$INTERNAL_IP
echo \$ETCD_NAME

sed -i "s/ETCD_NAME/\${ETCD_NAME}/g" /opt/k8s/etcd-template.service
sed -i "s/INTERNAL_IP/\${INTERNAL_IP}/g" /opt/k8s/etcd-template.service

cp /opt/k8s/etcd-template.service /etc/systemd/system/etcd.service

systemctl daemon-reload
systemctl enable etcd
systemctl start etcd
EOF

for instance in $CP02 $CP03; do
  scp -i ${SSH_KEY}  etcd-conf.sh etcd-template.service ubuntu@${instance}:/opt/k8s
  ssh -i ${SSH_KEY} -t -oStrictHostKeyChecking=no ubuntu@${instance} sudo bash /opt/k8s/etcd-conf.sh
done

chmod +x etcd-conf.sh
./etcd-conf.sh

ETCDCTL_API=3 etcdctl member list \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.crt \
  --cert=/etc/etcd/etcd-server.crt \
  --key=/etc/etcd/etcd-server.key

##################################################
# CONTROL PLANES SET UP
##################################################

cat <<EOF | sudo tee kube-apiserver-template.service
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-apiserver \\
  --advertise-address=INTERNAL_IP \\
  --allow-privileged=true \\
  --apiserver-count=3 \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/log/audit.log \\
  --authorization-mode=Node,RBAC \\
  --bind-address=0.0.0.0 \\
  --client-ca-file=/var/lib/kubernetes/ca.crt \\
  --enable-admission-plugins=NodeRestriction,ServiceAccount \\
  --enable-swagger-ui=true \\
  --enable-bootstrap-token-auth=true \\
  --etcd-cafile=/var/lib/kubernetes/ca.crt \\
  --etcd-certfile=/var/lib/kubernetes/etcd-server.crt \\
  --etcd-keyfile=/var/lib/kubernetes/etcd-server.key \\
  --etcd-servers=https://${CP01}:2379,https://${CP02}:2379,https://${CP03}:2379 \\
  --event-ttl=1h \\
  --kubelet-certificate-authority=/var/lib/kubernetes/ca.crt \\
  --kubelet-client-certificate=/var/lib/kubernetes/kube-apiserver.crt \\
  --kubelet-client-key=/var/lib/kubernetes/kube-apiserver.key \\
  --kubelet-https=true \\
  --runtime-config=api/all=true \\
  --service-account-key-file=/var/lib/kubernetes/service-account.crt \\
  --service-cluster-ip-range=10.96.0.0/24 \\
  --service-node-port-range=30000-32767 \\
  --tls-cert-file=/var/lib/kubernetes/kube-apiserver.crt \\
  --tls-private-key-file=/var/lib/kubernetes/kube-apiserver.key \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF | sudo tee kube-controller-manager-template.service
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \\
  --address=0.0.0.0 \\
  --cluster-cidr=192.168.5.0/24 \\
  --cluster-name=kubernetes \\
  --cluster-signing-cert-file=/var/lib/kubernetes/ca.crt \\
  --cluster-signing-key-file=/var/lib/kubernetes/ca.key \\
  --kubeconfig=/var/lib/kubernetes/kube-controller-manager.kubeconfig \\
  --leader-elect=true \\
  --root-ca-file=/var/lib/kubernetes/ca.crt \\
  --service-account-private-key-file=/var/lib/kubernetes/service-account.key \\
  --service-cluster-ip-range=10.96.0.0/24 \\
  --use-service-account-credentials=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF | sudo tee kube-scheduler-template.service
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-scheduler \\
  --kubeconfig=/var/lib/kubernetes/kube-scheduler.kubeconfig \\
  --address=127.0.0.1 \\
  --leader-elect=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > control-plane-conf.sh <<EOF
#!/bin/bash

set -xe

cd /opt/k8s

mkdir -p /etc/kubernetes/config

wget -q --show-progress --https-only --timestamping \
  "https://storage.googleapis.com/kubernetes-release/release/${K8S_VERSION}/bin/linux/amd64/kube-apiserver" \
  "https://storage.googleapis.com/kubernetes-release/release/${K8S_VERSION}/bin/linux/amd64/kube-controller-manager" \
  "https://storage.googleapis.com/kubernetes-release/release/${K8S_VERSION}/bin/linux/amd64/kube-scheduler" \
  "https://storage.googleapis.com/kubernetes-release/release/${K8S_VERSION}/bin/linux/amd64/kubectl"

chmod +x kube-apiserver kube-controller-manager kube-scheduler kubectl
mv kube-apiserver kube-controller-manager kube-scheduler kubectl /usr/local/bin/

mkdir -p /var/lib/kubernetes/

cp ca.crt ca.key kube-apiserver.crt kube-apiserver.key \
service-account.key service-account.crt \
etcd-server.key etcd-server.crt /var/lib/kubernetes/

NET_INTERFACE=\$(netstat -i | grep -vE "(lo|dock)" | tail -n 1 | cut -d" " -f1)
INTERNAL_IP=\$(ip addr show \$NET_INTERFACE | grep "inet " | awk '{print \$2}' | cut -d / -f 1)

sed -i "s/INTERNAL_IP/\${INTERNAL_IP}/g" /opt/k8s/kube-apiserver-template.service

cp /opt/k8s/kube-apiserver-template.service /etc/systemd/system/kube-apiserver.service

cp kube-controller-manager.kubeconfig /var/lib/kubernetes/
cp kube-scheduler.kubeconfig /var/lib/kubernetes/

cp kube-controller-manager-template.service /etc/systemd/system/kube-controller-manager.service
cp kube-scheduler-template.service /etc/systemd/system/kube-scheduler.service

systemctl daemon-reload
systemctl enable kube-apiserver kube-controller-manager kube-scheduler
systemctl start kube-apiserver kube-controller-manager kube-scheduler

while ! kubectl get componentstatuses --kubeconfig admin.kubeconfig; do
    sleep 2
    echo "==> Retrying..."
done
EOF

for instance in $CP02 $CP03; do
  scp -i ${SSH_KEY}  control-plane-conf.sh  kube-apiserver-template.service kube-controller-manager-template.service kube-scheduler-template.service ubuntu@${instance}:/opt/k8s
done

chmod +x control-plane-conf.sh
./control-plane-conf.sh

for instance in $CP02 $CP03; do
  ssh -i ${SSH_KEY} -t -oStrictHostKeyChecking=no ubuntu@${instance} sudo bash /opt/k8s/control-plane-conf.sh
done

##################################################
# WORKER NODES SET UP
##################################################

cat > bootstrap-token-${TOKEN_ID}.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: bootstrap-token-${TOKEN_ID}
  namespace: kube-system

type: bootstrap.kubernetes.io/token
stringData:
  description: "The default bootstrap token"

  token-id: ${TOKEN_ID}
  token-secret: ${TOKEN_SECRET}

  expiration: ${TOKEN_EXPIRATION}

  usage-bootstrap-authentication: "true"
  usage-bootstrap-signing: "true"

  auth-extra-groups: system:bootstrappers:worker
EOF

cat <<EOF | sudo tee kubelet-config.yaml
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: "/var/lib/kubernetes/ca.crt"
authorization:
  mode: Webhook
clusterDomain: "cluster.local"
clusterDNS:
  - "10.96.0.10"
resolvConf: "/run/systemd/resolve/resolv.conf"
runtimeRequestTimeout: "15m"
staticPodPath: "/var/lib/kubelet/manifests"
EOF

cat <<EOF | sudo tee kubelet.service
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=docker.service
Requires=docker.service

[Service]
ExecStart=/usr/local/bin/kubelet \\
  --bootstrap-kubeconfig="/var/lib/kubelet/bootstrap.kubeconfig" \\
  --config=/var/lib/kubelet/kubelet-config.yaml \\
  --image-pull-progress-deadline=2m \\
  --kubeconfig=/var/lib/kubelet/kubeconfig \\
  --cert-dir=/var/lib/kubelet/pki/ \\
  --rotate-certificates=true \\
  --rotate-server-certificates=true \\
  --network-plugin=cni \\
  --register-node=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF | sudo tee kube-proxy-config.yaml
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
clientConnection:
  kubeconfig: "/var/lib/kube-proxy/kube-proxy.kubeconfig"
mode: "iptables"
clusterCIDR: "192.168.5.0/24"
EOF

cat <<EOF | sudo tee kube-proxy.service
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

cat > worker-conf.sh <<EOF
#!/bin/bash

set -xe

cd /opt/k8s

wget -q --show-progress --https-only --timestamping \
  https://storage.googleapis.com/kubernetes-release/release/${K8S_VERSION}/bin/linux/amd64/kubectl \
  https://storage.googleapis.com/kubernetes-release/release/${K8S_VERSION}/bin/linux/amd64/kube-proxy \
  https://storage.googleapis.com/kubernetes-release/release/${K8S_VERSION}/bin/linux/amd64/kubelet

mkdir -p \
  /etc/cni/net.d \
  /opt/cni/bin \
  /var/lib/kubelet \
  /var/lib/kube-proxy \
  /var/lib/kubernetes \
  /var/run/kubernetes \
  /var/lib/kubelet/manifests

chmod +x kubectl kube-proxy kubelet
mv kubectl kube-proxy kubelet /usr/local/bin/

mv ca.crt /var/lib/kubernetes/
mv bootstrap.kubeconfig /var/lib/kubelet/bootstrap.kubeconfig
mv kubelet-config.yaml /var/lib/kubelet/kubelet-config.yaml
mv kubelet.service /etc/systemd/system/kubelet.service
mv kube-proxy.kubeconfig /var/lib/kube-proxy/kube-proxy.kubeconfig
mv kube-proxy-config.yaml /var/lib/kube-proxy/kube-proxy-config.yaml
mv kube-proxy.service /etc/systemd/system/kube-proxy.service

wget https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGINS}/cni-plugins-linux-amd64-${CNI_PLUGINS}.tgz 
tar -xzvf cni-plugins-linux-amd64-${CNI_PLUGINS}.tgz --directory /opt/cni/bin/

systemctl daemon-reload
systemctl enable kubelet kube-proxy
systemctl start kubelet kube-proxy
EOF

kubectl create -f bootstrap-token-${TOKEN_ID}.yaml --kubeconfig admin.kubeconfig
kubectl create clusterrolebinding create-csrs-for-bootstrapping --clusterrole=system:node-bootstrapper --group=system:bootstrappers --kubeconfig admin.kubeconfig
kubectl create clusterrolebinding auto-approve-csrs-for-group --clusterrole=system:certificates.k8s.io:certificatesigningrequests:nodeclient --group=system:bootstrappers --kubeconfig admin.kubeconfig
kubectl create clusterrolebinding auto-approve-renewals-for-nodes --clusterrole=system:certificates.k8s.io:certificatesigningrequests:selfnodeclient --group=system:nodes --kubeconfig admin.kubeconfig

kubectl config set-cluster bootstrap \
 --server=https://${LOAD_BALANCER}:6443 \
 --certificate-authority=/var/lib/kubernetes/ca.crt \
 --kubeconfig=bootstrap.kubeconfig

kubectl config set-credentials kubelet-bootstrap \
--token=${TOKEN_ID}.${TOKEN_SECRET} \
--kubeconfig=bootstrap.kubeconfig

kubectl config set-context bootstrap \
--user=kubelet-bootstrap \
--cluster=bootstrap \
--kubeconfig=bootstrap.kubeconfig

kubectl config use-context bootstrap --kubeconfig=bootstrap.kubeconfig

# Copy files to workers
for instance in $W01 $W02 $W03; do
  scp -i ${SSH_KEY} worker-conf.sh ca.crt kube-proxy.service kube-proxy-config.yaml kube-proxy.kubeconfig bootstrap.kubeconfig kubelet.service kubelet-config.yaml ubuntu@${instance}:/opt/k8s
done

# Run worker configuration script
for instance in $W01 $W02 $W03; do
  ssh -i ${SSH_KEY} -t -oStrictHostKeyChecking=no ubuntu@${instance} sudo bash /opt/k8s/worker-conf.sh
done


sleep 10
kubectl certificate approve $(kubectl get csr --kubeconfig admin.kubeconfig | grep node | grep Pending | head -n 1 | cut -d' ' -f1)
kubectl certificate approve $(kubectl get csr --kubeconfig admin.kubeconfig | grep node | grep Pending | head -n 2 | cut -d' ' -f1)
kubectl certificate approve $(kubectl get csr --kubeconfig admin.kubeconfig | grep node | grep Pending | head -n 3 | cut -d' ' -f1)

kubectl get nodes --kubeconfig admin.kubeconfig

kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version --kubeconfig admin.kubeconfig | base64 | tr -d '\n')" --kubeconfig admin.kubeconfig

kubectl get pods -A --kubeconfig admin.kubeconfig

cat <<EOF | kubectl apply --kubeconfig admin.kubeconfig -f -
apiVersion: rbac.authorization.k8s.io/v1beta1
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
apiVersion: rbac.authorization.k8s.io/v1beta1
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
    name: kube-apiserver
EOF

cat <<EOF | kubectl apply --kubeconfig admin.kubeconfig -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: coredns
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:coredns
rules:
- apiGroups:
  - ""
  resources:
  - endpoints
  - services
  - pods
  - namespaces
  verbs:
  - list
  - watch
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:coredns
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:coredns
subjects:
- kind: ServiceAccount
  name: coredns
  namespace: kube-system
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        health
        kubernetes cluster.local in-addr.arpa ip6.arpa {
          pods insecure
          upstream
          fallthrough in-addr.arpa ip6.arpa
        }
        prometheus :9153
        proxy . /etc/resolv.conf
        cache 30
        loop
        reload
        loadbalance
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: coredns
  namespace: kube-system
  labels:
    k8s-app: kube-dns
    kubernetes.io/name: "CoreDNS"
spec:
  replicas: 2
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
  selector:
    matchLabels:
      k8s-app: kube-dns
  template:
    metadata:
      labels:
        k8s-app: kube-dns
    spec:
      serviceAccountName: coredns
      tolerations:
        - key: node-role.kubernetes.io/master
          effect: NoSchedule
        - key: "CriticalAddonsOnly"
          operator: "Exists"
      containers:
      - name: coredns
        image: coredns/coredns:1.2.2
        imagePullPolicy: IfNotPresent
        resources:
          limits:
            memory: 170Mi
          requests:
            cpu: 100m
            memory: 70Mi
        args: [ "-conf", "/etc/coredns/Corefile" ]
        volumeMounts:
        - name: config-volume
          mountPath: /etc/coredns
          readOnly: true
        ports:
        - containerPort: 53
          name: dns
          protocol: UDP
        - containerPort: 53
          name: dns-tcp
          protocol: TCP
        - containerPort: 9153
          name: metrics
          protocol: TCP
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            add:
            - NET_BIND_SERVICE
            drop:
            - all
          readOnlyRootFilesystem: true
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
            scheme: HTTP
          initialDelaySeconds: 60
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 5
      dnsPolicy: Default
      volumes:
        - name: config-volume
          configMap:
            name: coredns
            items:
            - key: Corefile
              path: Corefile
---
apiVersion: v1
kind: Service
metadata:
  name: kube-dns
  namespace: kube-system
  annotations:
    prometheus.io/port: "9153"
    prometheus.io/scrape: "true"
  labels:
    k8s-app: kube-dns
    kubernetes.io/cluster-service: "true"
    kubernetes.io/name: "CoreDNS"
spec:
  selector:
    k8s-app: kube-dns
  clusterIP: 10.96.0.10
  ports:
  - name: dns
    port: 53
    protocol: UDP
  - name: dns-tcp
    port: 53
    protocol: TCP
EOF