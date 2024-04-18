【环境】
CentOS 7.1810
Kubernetes:1.28.2

【服务器配置】-3台
cd /etc/yum.repos.d/ && mkdir CentOS && mv CentOS* CentOS/ 

vi redhat.repo
[redhat]
baseurl=file:///mnt/cdrom
gpgcheck=0
enabled=1

mkdir /mnt/cdrom && mount /dev/cdrom /mnt/cdrom && yum clean all && yum repolist all && yum makecache

systemctl stop firewalld && \
systemctl disable firewalld && \
setenforce 0

vim /etc/selinux/config
#disabled

yum install -y device-mapper-persistent-data lvm2 wget net-tools nfs-utils lrzsz gcc gcc-c++ make cmake libxml2-devel openssl-devel curl curl-devel unzip sudo ntp libaio-devel wget vim ncurses-devel autoconf automake zlib-devel  python-devel epel-release openssh-server socat  ipvsadm conntrack telnet ipvsadm

【配置主机hosts文件，相互之间通过主机名互相访问】
vim /etc/hosts
192.168.40.150   k8s-sheca-master
192.168.40.151   k8s-sheca-node1
192.168.40.152   k8s-sheca-node2
 
【配置主机之间无密码登录】-master
ssh-keygen
ssh-copy-id k8s-sheca-node1
ssh-copy-id k8s-sheca-node2

【关闭交换分区swap，提升性能，重启服务器】- 3台
swapoff -a
vim /etc/fstab
#/dev/mapper/centos-swap swap      swap    defaults        0 0

【修改机器内核参数】- 3台
modprobe br_netfilter
cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
sysctl -p /etc/sysctl.d/k8s.conf

【配置阿里云的repo源】-3台
yum install yum-utils -y
yum-config-manager --add-repo http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo

【配置安装k8s组件需要的阿里云的repo源】-3台
cat >  /etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
enabled=1
gpgcheck=0
EOF

【配置时间同步】-3台
yum install ntpdate -y
ntpdate cn.pool.ntp.org
crontab -e
	* *  * * * /usr/sbin/ntpdate   cn.pool.ntp.org
service crond restart

【安装containerd服务】-3台
yum list | grep containerd
yum install -y container-selinux
yum install  containerd.io-1.6.31 -y
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

vim /etc/containerd/config.toml
	SystemdCgroup = false修改成SystemdCgroup = true
	sandbox_image = "k8s.gcr.io/pause:3.6" 修改成 sandbox_image="registry.aliyuncs.com/google_containers/pause:3.9"

[配置containerd镜像加速器]
mkdir /etc/containerd/certs.d/docker.io/ -p
vim /etc/containerd/config.toml
	config_path = "/etc/containerd/certs.d"
	
vim /etc/containerd/certs.d/docker.io/hosts.toml
[host."https://qryj5zfu.mirror.aliyuncs.com",host."https://registry.docker-cn.com"]
  capabilities = ["pull"]

systemctl restart  containerd  
systemctl enable containerd  --now

yum install  docker-ce  -y
systemctl enable docker --now
vim /etc/docker/daemon.json
{
 "registry-mirrors":["https://qryj5zfu.mirror.aliyuncs.com","https://registry.docker-cn.com","https://docker.mirrors.ustc.edu.cn","https://dockerhub.azk8s.cn","http://hub-mirror.c.163.com"]
}
systemctl restart docker


【安装初始化k8s需要的软件包】-3台
yum list | grep kubelet
yum install -y kubelet-1.28.2 kubeadm-1.28.2 kubectl-1.28.2
systemctl enable kubelet

【kubeadm初始化k8s集群】
crictl config runtime-endpoint unix:///run/containerd/containerd.sock

【使用kubeadm初始化k8s集群】-master
kubeadm config print init-defaults > kubeadm.yaml

cat kubeadm.yaml
apiVersion: kubeadm.k8s.io/v1beta3
bootstrapTokens:
- groups:
  - system:bootstrappers:kubeadm:default-node-token
  token: abcdef.0123456789abcdef
  ttl: 24h0m0s
  usages:
  - signing
  - authentication
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: 192.168.40.150
  bindPort: 6443
nodeRegistration:
  criSocket: unix:///run/containerd/containerd.sock
  imagePullPolicy: IfNotPresent
  name: k8s-sheca-master
  taints: null
---
apiServer:
  timeoutForControlPlane: 4m0s
apiVersion: kubeadm.k8s.io/v1beta3
certificatesDir: /etc/kubernetes/pki
clusterName: kubernetes
controllerManager: {}
dns: {}
etcd:
  local:
    dataDir: /var/lib/etcd
imageRepository: registry.cn-hangzhou.aliyuncs.com/google_containers
kind: ClusterConfiguration
kubernetesVersion: 1.28.2
networking:
  dnsDomain: cluster.local
  podSubnet: 10.244.0.0/16
  serviceSubnet: 10.96.0.0/12
scheduler: {}
---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: ipvs
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd

kubeadm config images list --kubernetes-version v1.28.2
registry.k8s.io/kube-apiserver:v1.28.2
registry.k8s.io/kube-controller-manager:v1.28.2
registry.k8s.io/kube-scheduler:v1.28.2
registry.k8s.io/kube-proxy:v1.28.2
registry.k8s.io/pause:3.9
registry.k8s.io/etcd:3.5.9-0
registry.k8s.io/coredns/coredns:v1.10.1

crictl pull registry.lank8s.cn/kube-apiserver:v1.28.2 &&                 
crictl pull registry.lank8s.cn/kube-controller-manager:v1.28.2 &&        
crictl pull registry.lank8s.cn/kube-scheduler:v1.28.2 &&                    
crictl pull registry.lank8s.cn/kube-proxy:v1.28.2 &&                       
crictl pull registry.lank8s.cn/pause:3.9 &&                                 
crictl pull registry.lank8s.cn/etcd:3.5.9-0 &&                              
crictl pull registry.lank8s.cn/coredns/coredns:v1.10.1

#重新打标记 因为默认会去registry.k8s.io 去下载镜像 也可以指定阿里云源
ctr -n k8s.io images tag registry.lank8s.cn/kube-controller-manager:v1.28.2 registry.k8s.io/kube-controller-manager:v1.28.2        
ctr -n k8s.io images tag registry.lank8s.cn/kube-scheduler:v1.28.2 registry.k8s.io/kube-scheduler:v1.28.2                 
ctr -n k8s.io images tag registry.lank8s.cn/kube-proxy:v1.28.2 registry.k8s.io/kube-proxy:v1.28.2                     
ctr -n k8s.io images tag registry.lank8s.cn/pause:3.9 registry.k8s.io/pause:3.9                              
ctr -n k8s.io images tag registry.lank8s.cn/etcd:3.5.9-0 registry.k8s.io/etcd:3.5.9-0                          
ctr -n k8s.io images tag registry.lank8s.cn/coredns/coredns:v1.10.1 registry.k8s.io/coredns/coredns:v1.10.1

kubeadm init --config=kubeadm.yaml --ignore-preflight-errors=SystemVerification --ignore-preflight-errors=Swap
   
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

kubeadm join 192.168.40.150:6443 --token abcdef.0123456789abcdef \
        --discovery-token-ca-cert-hash sha256:d127af31bf06540722208578d1219bc997fcfa0aec616e45c71b1db207430204

kubectl  get nodes -o wide
NAME               STATUS     ROLES           AGE   VERSION   INTERNAL-IP      EXTERNAL-IP   OS-IMAGE                KERNEL-VERSION          CONTAINER-RUNTIME
k8s-sheca-master   NotReady   control-plane   74s   v1.28.2   192.168.40.150   <none>        CentOS Linux 7 (Core)   3.10.0-957.el7.x86_64   containerd://1.6.31
k8s-sheca-node1    NotReady   <none>          7s    v1.28.2   192.168.40.151   <none>        CentOS Linux 7 (Core)   3.10.0-957.el7.x86_64   containerd://1.6.31
k8s-sheca-node2    NotReady   <none>          4s    v1.28.2   192.168.40.152   <none>        CentOS Linux 7 (Core)   3.10.0-957.el7.x86_64   containerd://1.6.31     

【安装kubernetes网络插件calico】- v3.26.4
#https://docs.tigera.io/calico/3.26/getting-started/kubernetes/self-managed-onprem/onpremises#install-calico-with-kubernetes-api-datastore-50-nodes-or-less
curl https://raw.githubusercontent.com/projectcalico/calico/v3.26.4/manifests/calico.yaml -O
kubectl apply -f calico.yaml

crictl pull docker.io/calico/cni:v3.26.4 && 
crictl pull docker.io/calico/node:v3.26.4 && 
crictl pull docker.io/calico/kube-controllers:v3.26.4

kubectl  get nodes -o wide
NAME               STATUS   ROLES           AGE   VERSION   INTERNAL-IP      EXTERNAL-IP   OS-IMAGE                KERNEL-VERSION          CONTAINER-RUNTIME
k8s-sheca-master   Ready    control-plane   56m   v1.28.2   192.168.40.150   <none>        CentOS Linux 7 (Core)   3.10.0-957.el7.x86_64   containerd://1.6.31
k8s-sheca-node1    Ready    <none>          55m   v1.28.2   192.168.40.151   <none>        CentOS Linux 7 (Core)   3.10.0-957.el7.x86_64   containerd://1.6.31
k8s-sheca-node2    Ready    <none>          55m   v1.28.2   192.168.40.152   <none>        CentOS Linux 7 (Core)   3.10.0-957.el7.x86_64   containerd://1.6.31

#进度条一直卡着 由于配置错误勒
重启-e-添加 rw inti=/sysroot/bin/sh - ctrl+x - chroot /sysroot - vi /etc/sysconfig/selinux 

==============================================================================================
【metrice-server】
wget https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.7.0/components.yaml
vim components.yaml
	1.registry.k8s.io/metrics-server/metrics-server:v0.7.0 ¸ÄÎª registry.lank8s.cn/metrics-server/metrics-server:v0.7.0
  2.      - --kubelet-preferred-address-types=InternalIP
  3.      - --kubelet-insecure-tls	 
kubectl  apply  -f components.yaml
==============================================================================================
【MetaILB】
kubectl get cm -n kube-system
kubectl edit cm kube-proxy -n kube-system 
	strictARP: true
wget https://raw.githubusercontent.com/metallb/metallb/v0.14.4/config/manifests/metallb-native.yaml
kubectl apply -f metallb-native.yaml 
kubectl get ns
kubectl get pods -n metallb-system
kubectl get pods speaker-8k9gk -o jsonpath={.status.hostIP} -n metallb-system
kubectl get pods speaker-pv2dk -o jsonpath={.status.hostIP} -n metallb-system
kubectl get pods speaker-w49ww -o jsonpath={.status.hostIP} -n metallb-system
kubectl api-versions
vim metallb-ipaddresspool.yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: localip-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.40.51-192.168.40.80
  autoAssign: true
  avoidBuggyIPs: true
kubectl apply -f metallb-ipaddresspool.yaml
kubectl get ipaddresspool -n metallb-system
vim metallb-l2advertisement.yaml
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: localip-pool-l2a
  namespace: metallb-system
spec:
  ipAddressPools:
  - localip-pool
  interfaces:
  - ens33
kubectl apply -f metallb-l2advertisement.yaml
kubectl get l2advertisement -n metallb-system
==============================================================================================
【csi-driver-nfs】
yum install -y nfs-utils
systemctl start nfs-server
systemctl status nfs-server
mkdir /data/nfs -p
vim /etc/exports
	/data/nfs 192.168.40.0/24(rw,fsid=0,async,no_subtree_check,no_auth_nlm,insecure,no_root_squash)
exportfs -arv

git clone https://github.com/kubernetes-csi/csi-driver-nfs.git
grep image: csi-driver-nfs/deploy/v4.6.0/*
vi csi-nfs-controller.yaml 
	%s/registry.k8s.cn/registry.lank8s.cn/g
vi csi-nfs-node.yaml 
	%s/registry.k8s.cn/registry.lank8s.cn/g
vi csi-snapshot-controller.yaml
	%s/registry.k8s.cn/registry.lank8s.cn/g
cd csi-driver-nfs/deploy/v4.6.0/
kubectl apply -f ./
kubectl get crds | grep storage.k8s.io

yum install -y yum install nfs-utils  :3Ì¨
vim csi-storageclass.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-csi
provisioner: nfs.csi.k8s.io
parameters:
  server: 192.168.40.104
  share: /data/nfs
reclaimPolicy: Delete
volumeBindingMode: Immediate
kubectl apply -f csi-storageclass.yaml
kubectl get sc

vim nfs-pvc-demo.yaml
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: nfs-pvc
  annotations:
    velero.io/csi-volumesnapshot-class: "nfs-csi"
spec:
  storageClassName: nfs-csi
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Gi

kubectl apply -f nfs-pvc-demo.yaml
kubectl get pvc

vim redis-with-nfs-pvc.yaml
apiVersion: v1
kind: Pod
metadata:
  name: redis-with-nfs-pvc
spec:
  containers:
  - name: redis
    image: redis:7-alpine
    ports:
    - containerPort: 6379
      name: redis
    volumeMounts:
    - mountPath: /data
      name: data-storage
  volumes:
  - name: data-storage
    persistentVolumeClaim:
      claimName: nfs-pvc

kubectl apply -f redis-with-nfs-pvc.yaml
kubectl get pods
kubectl exec -it redis-with-nfs-pvc -- /bin/sh
/data # redis-cli
127.0.0.1:6379> set mykey "BIRKHOFF 2024-04-18"
127.0.0.1:6379> BGSAVE
127.0.0.1:6379> get mykey
"BIRKHOFF 2024-04-18"
==============================================================================================

【Ingress】
wget https://github.com/kubernetes/ingress-nginx/blob/controller-v1.9.5/deploy/static/provider/cloud/deploy.yaml
vim deploy.yaml
	registry.k8s.io 改为 registry.lank8s.cn 2处
kubectl apply -f deploy.yaml
kubectl get ingressclass
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx 
