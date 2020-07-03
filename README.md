# Deploy and Configure a k8s cluster using AWS EC2 instances


1. VPC
2. LB
3. EC2 + Listeners + TG attach
    1. CP 1 + kubeadm init + weavenet
    2. CP 2 3 + kubeadm join
    3. Ws + kubeadm join