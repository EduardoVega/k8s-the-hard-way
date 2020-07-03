#!/bin/bash

set -xe

# Trap ERR, SIGHUP, SIGIN, SIGQUIT or SIGTERM signals
# This is important since we need to revert all changes made
# to the system
trap 'catch_error $LINENO $BASH_COMMAND' ERR SIGHUP SIGINT SIGQUIT SIGTERM

# Functions
function catch_error (){
    # This function will be called by the trap bash utility

    # Last exit code returned by the script
    exit_code=$?
    error_line=$1
    command=( $* )

    # Exit script using last exit code returned
    echo "=> Error information"
    echo "=> Error code: $exit_code"
    echo "=> Error line: $error_line"
    echo "=> Command: ${command[*]:2}"

    echo "=> Script has finished with errors"
    echo "=> Date: $(date)"

    exit $exit_code
} 2>&1 | tee -a /var/log/kubeadm-reqs.log

# Main script
(
# Let iptables see bridge networks
echo "=> Let iptables see bridge networks"

modprobe br_netfilter

cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

sysctl --system

# Install Container Runtime
echo "=> Install container runtime"
apt-get update -y
apt-get install -y\
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common \
    conntrack

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

apt-key fingerprint 0EBFCD88

add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"

apt-get update -y
apt-get install -y \
    docker-ce=5:19.03.8~3-0~ubuntu-bionic \
    docker-ce-cli=5:19.03.8~3-0~ubuntu-bionic \
    containerd.io

# cat > /etc/docker/daemon.json <<EOF
# {
#   "exec-opts": ["native.cgroupdriver=systemd"],
#   "log-driver": "json-file",
#   "log-opts": {
#     "max-size": "100m"
#   },
#   "storage-driver": "overlay2"
# }
# EOF

# mkdir -p /etc/systemd/system/docker.service.d

systemctl enable docker
systemctl start docker

########### Kubeadm ###########
# Install kubelet kubeadm kubectl
# curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
# cat <<EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
# deb https://apt.kubernetes.io/ kubernetes-xenial main
# EOF

# apt-get update -y
# apt-get install -y kubelet kubeadm kubectl
# apt-mark hold kubelet kubeadm kubectl

# kubeadm init

# kubeadm init --control-plane-endpoint "LOAD_BALANCER_DNS:LOAD_BALANCER_PORT" --upload-certs
# mkdir -p $HOME/.kube
# cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
# chown $(id -u):$(id -g) $HOME/.kube/config

#################################

########### K8s the hard way ###########
# Install kubectl
wget https://storage.googleapis.com/kubernetes-release/release/v1.18.2/bin/linux/amd64/kubectl
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

wget https://storage.googleapis.com/kubernetes-release/release/v1.18.2/bin/linux/amd64/kubelet
chmod +x kubelet
sudo mv kubelet /usr/local/bin/

wget https://storage.googleapis.com/kubernetes-release/release/v1.18.2/bin/linux/amd64/kubeadm
chmod +x kubeadm
sudo mv kubeadm /usr/local/bin/


) 2>&1 | tee -a /var/log/kubeadm-reqs.log
