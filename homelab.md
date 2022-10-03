# Setup a home-lab that could connect to from the Internet
<!-- 
Setup 1 master-node/controlplane and 3 worker-node:
- Master-node: 192.168.1.20
- Worker-node: 192.168.1.30, 192.168.1.31, 192.168.1.32
-->

# Những cái cần để cài đặt Home-lab
<!-- 
1. Ubuntu/Centos đã được cài vào mạng local
2. Những thành phần cài trên Master-node
- Rancher: single-node docker vì cài trên Kubernetes tốn nhiều tài nguyên hơn và Home-lab của mình không có Kubernetes multi-clusters nên cũng không cần thiết
- Kubernetes
- Ansible
- Terraform
- MetalLB
- Traefik cài qua Rancher
- Let's Encrypt 
-->
## Cài đặt

### Ansible
<!-- 
1. Cài Ansible trên Master-node:
- Làm theo [hướng dẫn](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html#control-node-requirements)
- Hoặc dùng centos/install-ansible.sh
- Sử dụng ssh-key không có passphrase cho đỡ tốn thời gian nhập passphrase
    Trên máy Master:
-->
'''
cd ~/.ssh
ssh-keygen -t rsa
ls -la
ssh-copy-id -i <ira-file-name>.pub <user-name>@<ip-address, ex:192.168.1.30>
'''
<!-- use default name id_rsa.pub
or we have to change the path to read the name of the isa file:
u@pc:~$ ssh-agent bashcd
u@pc:~$ ssh-add ~/.ssh/id_rsa
Enter passphrase for /home/u/.ssh/id_rsa: # ENTER YOUR PASSWORD
Identity added: /home/u/.ssh/id_rsa (/home/u/.ssh/id_rsa)

After that, we could config the PasswordAuthentication from 'yes' to 'no' to not allow SSH root@ password, so if we lose RSA key, we need to use monitor/keyboard
vi /etc/ssh/sshd_config
-->
Triển khai 1 [playbook để cài Kubernetes](https://buildvirtual.net/deploy-a-kubernetes-cluster-using-ansible/) nhưng đây mới là hướng dẫn xịn https://github.com/jmutai/k8s-pre-bootstrap
Lưu ý: do đang sử dụng Master-node để làm luôn ansible server nên host đang để ansible_connection = local thay vì để IP như các workernode
Thêm vào: vi /etc/ansible/hosts
'''
[masters]
master ansible_host=127.0.0.1 ansible_user=root ansible_connection=local
[workers]
workernode1 ansible_host=192.168.1.30 ansible_user=root
workernode2 ansible_host=192.168.1.31 ansible_user=root
workernode3 ansible_host=192.168.1.32 ansible_user=root
'''
Step 1:
Our first task in setting up the Kubernetes cluster is to create a new user on each node. This will be a non-root user, that has sudo privileges. It’s a good idea not to use the root account for day to day operations, of course. We can use Ansible to set the account up on all three nodes, quickly and easily. First, create a file in the working directory: vi users.yml
'''
- hosts: 'workers, masters'
  become: yes

  tasks:
    - name: create the kube user account
      user: name=kube append=yes state=present createhome=yes shell=/bin/bash

    - name: allow 'kube' to use sudo without needing a password
      lineinfile:
        dest: /etc/sudoers
        line: 'kube ALL=(ALL) NOPASSWD: ALL'
        validate: 'visudo -cf %s'

    - name: set up authorized keys for the kube user
      authorized_key: user=kube key="{{item}}"
      with_file:
        - ~/.ssh/id_rsa.pub
'''
We’re now ready to run our first playbook. To do so:
'''
ansible-playbook -i hosts users.yml
'''
Step 2:
Create a playbook to install Kubernetes: vi install-k8s.yml
Các bước ở đây giống với các bước trong centos/install-docker-kube.sh
'''
---
- hosts: "masters, workers"
  remote_user: kube
  become: yes
  become_method: sudo
  become_user: root
  gather_facts: yes
  connection: ssh

  tasks:
    - name: Create containerd config file
      file:
        path: "/etc/modules-load.d/containerd.conf"
        state: "touch"

    - name: Add conf for containerd
      blockinfile:
        path: "/etc/modules-load.d/containerd.conf"
        block: |
              overlay
              br_netfilter

    - name: modprobe
      shell: |
              sudo modprobe overlay
              sudo modprobe br_netfilter

    - name: Set system configurations for Kubernetes networking
      file:
        path: "/etc/sysctl.d/99-kubernetes-cri.conf"
        state: "touch"
 
    - name: Apply new settings
      command: sudo sysctl --system

    - name: Add docker repository
      get_url:
        url: https://download.docker.com/linux/centos/docker-ce.repo
        dest: /etc/yum.repos.d/docker-ce.repo

    - name: Install containerd
      ansible.builtin.package:
        name: [containerd.io]
        state: present

    - name: Create containerd directories required
      ansible.builtin.file:
        path: "{{ item }}
        state: directory
      with_items:
        - /etc/containerd

    - name: Configure containerd
      ansible.builtin.shell: containerd config default > /etc/containerd/config.toml
      run_once: true

    - name: Set cgroup driver as systemd
      ansible.builtin.template:
        src: daemon.json.j2
        dest: /etc/docker/daemon.json

    - name: Start and enable containerd service
      ansible.builtin.systemd:
        name: containerd
        state: restarted
        enabled: yes
        daemon_reload: yes

    - name: disable swap
      shell: |
              sudo swapoff -a
    #- name: Disable SWAP in fstab since kubernetes can't work with swap enabled (2/2)
    #-  ansible.builtin.replace:
    #-    path: /etc/fstab
    #-    regexp: '^([^#].*?\sswap\s+.*)$'
    #-    replace: '# \1'
    
    - name: Remove swap entry from /etc/fstab
      lineinfile:
        dest: /etc/fstab
        regexp: swap
        state: absent

    - name: Add kubernetes repository
      ansible.builtin.template:
        src: 'kubernetes.repo.j2'
        dest: /etc/yum.repos.d/kubernetes.repo

    - name: Install kubernetes packages
      yum:
        name: [kubelet,kubeadm,kubectl]
        disable_excludes: kubernetes

    - name: Enable kubelet service
      ansible.builtin.service:
        name: kubelet
        enabled: yes
'''
Chạy Playbook này trên tất cả các hosts:
'''
ansible-playbook -i hosts install-k8s.yml
'''
1st Oct 22: LỖI - méo hiểu tại sao lại lỗi kết thúc yaml không thể tìm được lý do, nên đổi sang dùng reposity của anh này: https://github.com/jmutai/k8s-pre-bootstrap
'''
yum install -y git
git clone https://github.com/jmutai/k8s-pre-bootstrap
cd k8s-pre-bootstrap
vi k8s-prep.yml
'''
Sửa các thành phần config: vi k8s-prep.yml để chạy Containerd
'''
---
- name: Setup Proxy
  hosts: k8snodes
  remote_user: root
  become: yes
  become_method: sudo
  #gather_facts: no
  vars:
    k8s_version: "1.25"                                  # Kubernetes version to be installed
    selinux_state: permissive                            # SELinux state to be set on k8s nodes
    timezone: "Asia/Ho_Chi_Minh"                           # Timezone to set on all nodes
    k8s_cni: calico                                      # calico, flannel
    container_runtime: containerd                             # docker, cri-o, containerd
    pod_network_cidr: "192.168.1.0/16"                   # pod subnet if using cri-o runtime
    configure_firewalld: false                           # true / false (keep it false, k8s>1.19 have issues with firewalld)
    # Docker proxy support
    setup_proxy: false                                   # Set to true to configure proxy
    proxy_server: "proxy.example.com:8080"               # Proxy server address and port
    docker_proxy_exclude: "localhost,127.0.0.1"          # Adresses to exclude from proxy
  roles:
    - kubernetes-bootstrap
                           
'''
Thêm địa chỉ của các nodes vào /etc/hosts 
Đổi thông số file hosts trong thư mục k8s-pre-bootstrap
[k8snodes]
masternode
workernode1
workernode2
workernode3

1st Oct 22: vẫn LỖI mà chưa biết cách chữa do nó hiển thị mỗi The offending line appears to be

TỰ LÀM: 1 file ansible playbook tải cái shellbash của centos về rồi cho tự chạy, trong thư mục /etc/ansible, tạo file install-k8s-sh.yml :
---
- hosts: "masters, workers"
  remote_user: kube
  become: true
  become_method: sudo
  become_user: root
  gather_facts: yes
  connection: ssh

  tasks:
     - name: Download zsh installer
       get_url:
         url: https://raw.githubusercontent.com/Digivision/kubernetes_setup/main/centos/install-docker-kube.sh
         dest: /etc/install-docker-kube.sh
         validate_certs: no # to not validate the SSL
         force: yes # to force the change
         mode: "0555"

     - name: Execute the shellbash file
       shell: /etc/install-docker-kube.sh
       become: true

     - name: Remove the file
       file: 
         path: /etc/install-docker-kube.sh
         state: absent
'''
Đã chạy được file bash, nhưng vấn đề là éo có tracking nên ko hiểu lỗi ở đâu. Sử dụng lệnh trong shell scripts để chạy trực tiếp thì chạy ầm ầm , còn chạy = lệnh sh thì bị lỗi :(. Nên đoạn provision K8s bằng Ansible-playbook này tạm bỏ qua, để nghiên cứu sau (trước mắt cứ dùng cái install-docker-kube.sh để copy toàn bộ lệnh đó ra mà chạy đã)

Step 3: Create Masternode and Join Worker nodes
Tạo file master-worker.yml trong /etc/ansible:
'''
- hosts: masters
  become: yes
  tasks:
    - name: initialize the cluster
      shell: kubeadm init --control-plane-endpoint=192.168.1.20:6443 --upload-certs --apiserver-advertise-address=192.168.1.20 --pod-network-cidr=10.244.0.0/16 --cri-socket=unix:///var/run/containerd/containerd.sock
      args:
        chdir: $HOME
        creates: cluster_initialized.txt
    
    - name: download Flannel setup file
      get_url:
        url: https://raw.githubusercontent.com/Digivision/kubernetes_setup/main/kube-flannel-v0.16.3.yml
        dest: /etc/ansible/kube-flannel-v0.16.3.yml
        validate_certs: no # to not validate the SSL
        force: yes # to force the change
        mode: "0644"

    - name: Deploy Flannel network
      shell: kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f kube-flannel-v0.16.3.yml
    
    - name: create .kube directory
      become: yes
      become_user: kube
      file:
        path: $HOME/.kube
        state: directory
        mode: 0755
    #Loại task trên có vẻ không chạy nên đổi dùng thử loại dưới này 
    - name: Create directory for kube config
      file:
        path: /home/ci/.kube
        state: directory
        owner: ci
        group: ci
        mode: 0755

    - name: Copy /etc/kubernetes/admin.conf to user home directory
      become_user: root
      become_method: sudo
      become: true
      copy:
        src: /etc/kubernetes/admin.conf
        dest: /home/ci/.kube/config
        remote_src: yes
        owner: ci
        group: ci
        mode: '0644'

    - name: copies admin.conf to user's kube config
      copy:
        src: /etc/kubernetes/admin.conf
        dest: /home/kube/.kube/config
        remote_src: yes
        owner: kube

    #- name: install Pod network
    #-  become: yes
    #-  become_user: kube
    #-  shell: kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
    #-  args:
    #-    chdir: $HOME

    - name: Get the token for joining the worker nodes
      become: yes
      become_user: kube
      shell: kubeadm token create  --print-join-command
      register: kubernetes_join_command

    - debug:
        msg: "{{ kubernetes_join_command.stdout }}"
    #This part is not correct in the origin doc, have to Push 2 space to the right
    
    - name: Copy join command to local file.
      become: yes
      local_action: copy content="{{ kubernetes_join_command.stdout_lines[0] }}" dest="/tmp/kubernetes_join_command" mode=0777
    
    #Because of https://github.com/kubernetes/kubernetes/issues/60835#issuecomment-395931644
    - name: Edit kubeadm.conf
      blockinfile:
        path: /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
        block: |
          Environment="KUBELET_EXTRA_ARGS=--node-ip={{ inventory_hostname }}"
    - name: Restart kubelet service
      service:
        name: kubelet
        daemon-reload: yes
        state: restarted

- hosts: workers
  become: yes
  gather_facts: yes

  tasks:
   - name: Copy join command from Ansiblehost to the worker nodes.
     become: yes
     copy:
       src: /tmp/kubernetes_join_command
       dest: /tmp/kubernetes_join_command
       mode: 0777

   - name: Join the Worker nodes to the cluster.
     become: yes
     command: sh /tmp/kubernetes_join_command
     register: joined_or_not
'''

To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

Trước khi bắt đầu thì Backup Config https://www.thegeekdiary.com/centos-rhel-how-to-backuprestore-configuration-using-authconfig/, với vi authconfig.yml:
'''
- hosts: "masters, workers"
  remote_user: kube
  become: yes
  become_method: sudo
  become_user: root
  gather_facts: yes
  connection: ssh

  tasks:
  - name: backup config with authconfig
    shell: |
             authconfig --savebackup=after-k8s
'''
### Rancher
Để [cài Rancher](https://docs.ranchermanager.rancher.io/getting-started/quick-start-guides/deploy-rancher-manager/helm-cli) thì trước hết cần [cài Helm](https://helm.sh/docs/intro/install/) trên Master node

'''
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
'''
hoặc: nhưng éo hiểu sao ở VN éo tải được
'''
yum install helm
'''
Cài Rancher với:
'''
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest

kubectl create namespace cattle-system

kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.7.1/cert-manager.crds.yaml

helm repo add jetstack https://charts.jetstack.io

helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.7.1
'''
Nếu có vấn đề về install mà do trùng tên có thể dùng upgrade --install, vd:
'''
helm upgrade --install cert-manager jetstack/cert-manager   --namespace cert-manager   --create-namespace   --version v1.7.1
'''
Rồi chạy tiếp lệnh: với 192.168.1.20 là IP_OF_LINUX_NODE và p@ssW0rd là <PASSWORD_FOR_RANCHER_ADMIN>
'''
helm install rancher rancher-latest/rancher \
  --namespace cattle-system \
  --set hostname=192.168.1.20 \
  --set replicas=1 \
  --set bootstrapPassword=p@ssW0rd
'''
LỖI chán vkl:  Error: INSTALLATION FAILED: chart requires kubeVersion: < 1.25.0-0 which is incompatible with Kubernetes v1.25.2
Đổi sang dùng [Docker để cài](https://docs.ranchermanager.rancher.io/pages-for-subheaders/rancher-on-a-single-node-with-docker#option-d-let-s-encrypt-certificate) với:
'''
docker run -d --restart=unless-stopped   -p 80:80 -p 443:443   --privileged   rancher/rancher:latest
''''
Rồi vào https://192.168.1.20/dashboard để setup Rancher lần đầu, dùng lệnh docker logs  container-id  2>&1 | grep "Bootstrap Password:" để tìm password (docker ps để tìm container-id), chú ý là phải để URL server giữ nguyên https://192.168.1.20
LỖI đủ kiểu: hết lỗi add Control plane do thiếu SSL đến không nhận Kubernetes API
Xoá toàn bộ (xem lại mục cần xoá, ko là mất hết config phải cài lại cả CentOs)
'''
docker stop $(docker ps -aq)
docker system prune -f
docker volume rm $(docker volume ls -q)
docker image rm $(docker image ls -q)
rm -rf /etc/ceph \
       /etc/cni \
       /etc/kubernetes \
       /opt/cni \
       /opt/rke \
       /run/secrets/kubernetes.io \
       /run/calico \
       /run/flannel \
       /var/lib/calico \
       /var/lib/etcd \
       /var/lib/cni \
       /var/lib/kubelet \
       /var/lib/rancher/rke/log \
       /var/log/containers \
       /var/log/pods \
       /var/run/calico
'''

-> Quyết định cài Kubernetes Dashboard thay cho Rancher:
### Cài Kubernetes Dashboard
Hướng dẫn cài [này](https://computingforgeeks.com/how-to-install-kubernetes-dashboard-with-nodeport/) tương đối đầy đủ nhưng cần bổ sung đường dẫn mới cho file yaml https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/ , với cả phải tạo User và Role trên kubernetes-dashboard để tạo Token Bearer đăng nhập https://github.com/kubernetes/dashboard/blob/master/docs/user/access-control/creating-sample-user.md , còn sử dụng cái sau để theo dõi Namespace khác ngoài kubernetes-dashboard https://computingforgeeks.com/create-admin-user-to-access-kubernetes-dashboard/
Có file config thì trong file đừng để EOF

'''
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.6.1/aio/deploy/recommended.yaml
'''
Thôi tạm bỏ qua vì méo thể connect vào 127.0.0.1:8001 sau lệnh kubectl proxy được.

### MetalLB
Cài có vẻ đơn giản, theo [hướng dẫn này](https://metallb.universe.tf/installation/)
Nhưng tốt hơn là làm theo [hướng dẫn của bạn này](https://www.youtube.com/watch?v=2SmYjj-GFnE)
Kiểm tra kube-proxy với 
'''
kubectl -n kube-system get all
kubectl -n kube-system describe cm kube-proxy | less
'''
Nếu mode="ipvs" thì mới áp dụng dòng dưới để chỉnh từ false -> true, còn nếu mode="" thì bỏ qua
'''
# see what changes would be made, returns nonzero returncode if different
kubectl get configmap kube-proxy -n kube-system -o yaml | \
sed -e "s/strictARP: false/strictARP: true/" | \
kubectl diff -f - -n kube-system

# actually apply the changes, returns nonzero returncode on errors only
kubectl get configmap kube-proxy -n kube-system -o yaml | \
sed -e "s/strictARP: false/strictARP: true/" | \
kubectl apply -f - -n kube-system
'''
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.5/config/manifests/metallb-native.yaml

Tạo file cấu hình cho MetalLB, vi /tmp/metallb.yaml :
'''
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: ipaddresspool-sunshine2
  namespace: metallb-system
spec:
  addresses:
    - 192.168.1.200-192.168.1.250
    - 192.168.1.0/24
  autoAssign: false
  avoidBuggyIPs: true
'''
kubectl create -f /tmp/metallb.yaml
đổi cấu hình trên với: 
kubectl apply -f /tmp/metallb.yaml
Dính lỗi: Error from server (InternalError): error when creating "/tmp/metallb.yaml": Internal error occurred: failed calling webhook "ipaddresspoolvalidationwebhook.metallb.io": failed to call webhook: Post "https://webhook-service.metallb-system.svc:443/validate-metallb-io-v1beta1-ipaddresspool?timeout=10s": dial tcp 10.97.101.85:443: connect: connection refused
Theo các pro bảo thì do --cri-socket phải setup!!!!! Quay lại bước setup đã
Quay cài lại xong vẫn bị cái lỗi đó
Để xem config nhưng méo có chỗ nào mà chỉnh: kubectl get validatingwebhookconfiguration -o yaml
Thấy cái IP mà webhook-service đang chạy: kubectl get svc -n metallb-system
Sửa webhooks: failurePolicy=Ignore với kubectl edit validatingwebhookconfiguration -o yaml
Thì chạy tiếp được với kq: ipaddresspool.metallb.io/ipaddresspool-sunshine2 created

Lối: Getting the dial tcp 10.96.0.1:443: i/o timeout issues
Do lúc kubeadm để là 192.168.1.0 , phải đổi lại cái khác phù hợp với Calico 

Để 4 cái pod/speaker chạy được thì cần tạo Secrets:
'''
kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"
'''

Cài nginx
kubectl create deploy nginx --image nginx:latest
Xem thông tin app đang chạy
kubectl get all
Thấy nginx đang chạy nhưng mà External-IP bị pending
Cài sipcalc để xem range mạng
yum install -y sipcalc
sipcalc 192.168.1.0/24
'''
kubectl patch svc nginx -n <namespace> -p '{"spec": {"type": "LoadBalancer", "externalIPs":["192.168.1.39"]}}'
kubectl delete deployment nginx
'''