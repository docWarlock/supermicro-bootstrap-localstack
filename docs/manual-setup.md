Absolutely — I’ve updated your full guide to include the clarification that you’re **simulating AWS deployments** locally, and added a LocalStack section reflecting that no EKS mapping is needed. Everything is in **strict order of operation**.

---

# 🚀 Supermicro E300 → RKE2 + LocalStack Lab Setup (AWS Deployment Simulation)

## 0. Hardware & Firmware Prep

1. Plug in power + network.
2. Enter BIOS / IPMI:

   * Update firmware + BMC.
   * Enable **VT-x/IOMMU**.
   * Assign static IP or DHCP reservation for management.

---

## 1. Install Base OS (Ubuntu Server 24.04 LTS recommended)

During install:

* Create a sudo user (e.g. `doc`).
* Install OpenSSH if prompted.
* Partition disk (optional but recommended):

  * `/` root → 40–60 GB
  * `/var/lib/rancher` → \~150–180 GB for Kubernetes data

---

## 2. First Login (local console)

```bash
# update + essentials
sudo apt update && sudo apt -y full-upgrade
sudo apt -y install jq curl ufw chrony
sudo timedatectl set-timezone America/Chicago
```

Enable firewall:

```bash
sudo ufw allow 22/tcp   # SSH
sudo ufw enable
```

(Optional) install **Tailscale VPN** for secure remote access:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --ssh
```

---

## 3. Remote Access from Your Laptop

### 3.1 Find IP of the box:

```bash
ip addr show eno1
# example: 192.168.1.10
```

### 3.2 From your laptop (Windows PowerShell):

```powershell
ssh doc@192.168.1.10
```

✅ At this point you can fully remote in — no need for monitor/keyboard anymore.

---

## 4. Install RKE2 (server mode)

On the E300:

```bash
curl -sfL https://get.rke2.io | sudo sh -
sudo systemctl enable rke2-server
```

### 4.1 Generate a cluster token:

```bash
openssl rand -hex 16
```

### 4.2 Create config file:

```bash
sudo mkdir -p /etc/rancher/rke2
sudo nano /etc/rancher/rke2/config.yaml
```

Paste in (replace token + IP with yours):

```yaml
token: "4a9e2b197b1d3a2f8ce34f7a5dc28c90"
write-kubeconfig-mode: "0600"
tls-san:
  - e300.lan
  - 192.168.1.10
node-ip: 192.168.1.10
advertise-address: 192.168.1.10
cni: cilium
secrets-encryption: true
etcd-snapshot-schedule-cron: "0 */6 * * *"
etcd-snapshot-retention: 7
disable-cloud-controller: true
```

### 4.3 Start the server:

```bash
sudo systemctl start rke2-server
sudo journalctl -u rke2-server -f
```

---

## 5. Access the Cluster from Your Laptop

On the E300:

```bash
sudo cp /etc/rancher/rke2/rke2.yaml /home/doc/rke2.yaml
sudo chown doc:doc /home/doc/rke2.yaml
```

From your laptop (PowerShell):

```powershell
mkdir $HOME\.kube
scp doc@192.168.1.10:/home/doc/rke2.yaml $HOME\.kube\config-e300
```

Test:

```powershell
$env:KUBECONFIG="$HOME\.kube\config-e300"
kubectl get nodes
k9s --kubeconfig $HOME\.kube\config-e300
```

---

## 6. Optional: Install MetalLB (for LoadBalancer Services)

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml
```

Example pool (adjust to your LAN):

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata: {name: lan-pool, namespace: metallb-system}
spec: {addresses: ["192.168.1.240-192.168.1.250"]}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata: {name: lan-adv, namespace: metallb-system}
spec: {ipAddressPools: ["lan-pool"]}
```

---

## 7. Deploy LocalStack (Simulate AWS Deployments)

**Goal:** simulate deploying applications to AWS services **without actually connecting to EKS/AWS**.

### 7.1 Install Helm

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### 7.2 Add LocalStack Helm repo

```bash
helm repo add localstack https://localstack.github.io/helm-charts
helm repo update
```

### 7.3 Create Helm values file

```yaml
# values-localstack.yaml
image:
  repository: localstack/localstack
  tag: "latest"

service:
  type: ClusterIP
  ports:
    edge: 4566

mountDind:
  enabled: true    # required for Lambda, ECS

extraEnvVars:
  - name: SERVICES
    value: s3,sqs,iam,ecr

persistence:
  enabled: true
  size: 20Gi
```

### 7.4 Deploy LocalStack

```bash
helm upgrade --install localstack localstack/localstack \
  --namespace localstack --create-namespace \
  -f values-localstack.yaml
kubectl -n localstack rollout status deploy/localstack
```

### 7.5 Access LocalStack

```bash
kubectl -n localstack port-forward svc/localstack 4566:4566
```

Test locally with `awslocal`:

```bash
pip install awscli-local
awslocal s3 ls
```

> You now have a sandbox that **mimics AWS deployments**, so you can deploy Helm charts, Kubernetes manifests, and AWS-like services locally without using real AWS.

---

## 8. Developer Workflow

1. Build app → push to a local registry (Harbor, GHCR, or LocalStack ECR).
2. Deploy manifests/Helm charts to RKE2.
3. Provision AWS-like services in LocalStack with `awslocal`.
4. Monitor and manage pods with `k9s`.

---

## 9. Maintenance & QoL

* **Backups:** RKE2 etcd snapshots are enabled. Copy off-box nightly.
* **Ingress / HTTPS:** Use built-in nginx-ingress.
* **Remote mgmt:** Prefer VPN (Tailscale/WireGuard) for secure access.

---

✅ You now have a **fully functional local lab** that mimics AWS deployments on EKS, using:

* RKE2 for Kubernetes
* LocalStack for AWS services simulation
* kubeconfig + k9s for easy management
* Optional MetalLB for LAN LoadBalancer testing
