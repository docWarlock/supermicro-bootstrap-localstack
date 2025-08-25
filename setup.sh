#!/usr/bin/env bash
set -euo pipefail

# === CONFIG ===
USER_NAME="user"               # change to your user
NODE_IP="$(hostname -I | awk '{print $1}')"  # auto-detect first IP
NODE_DNS="e300.lan"           # optional DNS name
RKE2_TOKEN="$(openssl rand -hex 16)"         # random cluster token

echo "[*] Updating system..."
apt update && apt -y full-upgrade

echo "[*] Installing essentials..."
apt -y install jq curl ufw chrony openssh-server

echo "[*] Configuring firewall..."
ufw allow 22/tcp   # SSH
ufw allow 6443/tcp # K8s API
ufw allow 80,443/tcp
ufw --force enable

echo "[*] Installing Tailscale (optional, secure remote access)..."
curl -fsSL https://tailscale.com/install.sh | sh || true
# After boot, run: sudo tailscale up --ssh

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

echo "[*] Waiting for kubeconfig to be created..."
sleep 30
if [ ! -f /etc/rancher/rke2/rke2.yaml ]; then
    echo "ERROR: rke2.yaml not found, check 'journalctl -u rke2-server -f'"
    exit 1
fi

echo "[*] Copying kubeconfig to user home..."
cp /etc/rancher/rke2/rke2.yaml /home/${USER_NAME}/rke2.yaml
chown ${USER_NAME}:${USER_NAME} /home/${USER_NAME}/rke2.yaml

echo "[*] Done!"
echo "--------------------------------------------"
echo "RKE2 server started."
echo "Cluster token: ${RKE2_TOKEN}"
echo "Kubeconfig is at: /home/${USER_NAME}/rke2.yaml"
echo "--------------------------------------------"
echo "Next steps (on your laptop):"
echo "  mkdir -p ~/.kube"
echo "  scp ${USER_NAME}@${NODE_IP}:/home/${USER_NAME}/rke2.yaml ~/.kube/config-e300"
echo "  set KUBECONFIG=~/.kube/config-e300"
echo "  kubectl get nodes"
