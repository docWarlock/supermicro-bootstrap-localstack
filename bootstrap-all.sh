#!/usr/bin/env bash
set -euo pipefail

# ===========================
# CONFIGURATION
# ===========================
USER_NAME="doc"                             # Linux user for kubeconfig
NODE_IP="$(hostname -I | awk '{print $1}')" # auto-detect first IP
NODE_DNS="e300.lan"                         # optional DNS
RKE2_TOKEN="$(openssl rand -hex 16)"        # random cluster token
METALLB_IP_RANGE="192.168.1.240-192.168.1.250"
LOCALSTACK_NAMESPACE="localstack"
KUBECONFIG_PATH="/home/${USER_NAME}/rke2.yaml"

# ===========================
# MAKE RKE2 BINARIES AVAILABLE
# ===========================
export PATH=$PATH:/var/lib/rancher/rke2/bin

# ===========================
# SYSTEM PREP
# ===========================
echo "[*] Updating system..."
apt update && apt -y full-upgrade

echo "[*] Installing essentials..."
apt -y install jq curl ufw chrony openssh-server apt-transport-https ca-certificates gnupg lsb-release

echo "[*] Configuring firewall..."
ufw allow 22/tcp    # SSH
ufw allow 6443/tcp  # K8s API
ufw allow 80,443/tcp
ufw --force enable

echo "[*] Installing Tailscale (optional for remote SSH)..."
curl -fsSL https://tailscale.com/install.sh | sh || true
# after boot: sudo tailscale up --ssh

# ===========================
# INSTALL RKE2
# ===========================
echo "[*] Installing RKE2 server..."
curl -sfL https://get.rke2.io | sh -
systemctl enable rke2-server

echo "[*] Writing RKE2 config..."
mkdir -p /etc/rancher/rke2
cat >/etc/rancher/rke2/config.yaml <<EOF
token: "${RKE2_TOKEN}"
write-kubeconfig-mode: "0600"
tls-san:
  - ${NODE_DNS}
  - ${NODE_IP}
node-ip: ${NODE_IP}
advertise-address: ${NODE_IP}
cni: cilium
secrets-encryption: true
etcd-snapshot-schedule-cron: "0 */6 * * *"
etcd-snapshot-retention: 7
disable-cloud-controller: true
EOF

echo "[*] Starting RKE2..."
systemctl start rke2-server

# ===========================
# COPY KUBECONFIG TO USER
# ===========================
echo "[*] Copying kubeconfig to user home..."
cp /etc/rancher/rke2/rke2.yaml "${KUBECONFIG_PATH}"
chown ${USER_NAME}:${USER_NAME} "${KUBECONFIG_PATH}"
chmod 600 "${KUBECONFIG_PATH}"

# ===========================
# EXPORT KUBECONFIG
# ===========================
export KUBECONFIG="${KUBECONFIG_PATH}"

# ===========================
# WAIT FOR API SERVER
# ===========================
echo "[*] Waiting for RKE2 Kubernetes API..."
until kubectl --kubeconfig "$KUBECONFIG" get nodes >/dev/null 2>&1; do
    echo "Waiting for API server..."
    sleep 5
done
echo "[*] API server is ready."

# Verify connectivity
echo "[*] Verifying API server connectivity..."
kubectl get nodes

# ===========================
# INSTALL HELM
# ===========================
echo "[*] Installing Helm..."
if ! command -v helm >/dev/null 2>&1; then
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# ===========================
# INSTALL METALLB
# ===========================
echo "[*] Installing MetalLB..."
kubectl --kubeconfig "$KUBECONFIG" apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml

cat >/tmp/metallb-pool.yaml <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: lan-pool
  namespace: metallb-system
spec:
  addresses:
    - ${METALLB_IP_RANGE}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: lan-adv
  namespace: metallb-system
spec:
  ipAddressPools:
    - lan-pool
EOF

kubectl --kubeconfig "$KUBECONFIG" apply -f /tmp/metallb-pool.yaml

# ===========================
# DEPLOY LOCALSTACK
# ===========================
echo "[*] Adding LocalStack Helm repo..."
helm repo add localstack https://localstack.github.io/helm-charts
helm repo update

cat > values-localstack.yaml <<EOF
image:
  repository: localstack/localstack
  tag: "latest"

service:
  type: ClusterIP
  ports:
    edge: 4566

mountDind:
  enabled: true

extraEnvVars:
  - name: SERVICES
    value: s3,sqs,iam,ecr

persistence:
  enabled: true
  size: 20Gi
EOF

echo "[*] Installing LocalStack..."
helm upgrade --install localstack localstack/localstack \
  --namespace ${LOCALSTACK_NAMESPACE} --create-namespace \
  -f values-localstack.yaml

kubectl --kubeconfig "$KUBECONFIG" -n ${LOCALSTACK_NAMESPACE} rollout status deploy/localstack --timeout=180s

# ===========================
# COMPLETION MESSAGE
# ===========================
echo "---------------------------------------------------"
echo "✅ Bootstrap complete!"
echo "RKE2 cluster token: ${RKE2_TOKEN}"
echo "Kubeconfig path: ${KUBECONFIG_PATH}"
echo "LocalStack namespace: ${LOCALSTACK_NAMESPACE}"
echo
echo "Next steps from your laptop:"
echo "  mkdir -p ~/.kube"
echo "  scp ${USER_NAME}@${NODE_IP}:${KUBECONFIG_PATH} ~/.kube/config-e300"
echo "  set KUBECONFIG=~/.kube/config-e300"
echo "  kubectl get nodes"
echo "  kubectl -n ${LOCALSTACK_NAMESPACE} port-forward svc/localstack 4566:4566"
echo "---------------------------------------------------"
