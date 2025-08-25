# supermicro-bootstrap-localstack
🛠️ Usage

On your fresh Ubuntu box:

sudo apt update && sudo apt -y install curl
curl -O https://your-server/bootstrap.sh   # or paste into nano
chmod +x bootstrap.sh
sudo ./bootstrap.sh

✅ What this script does

Updates system.

Installs core tools (SSH, UFW, chrony, curl, jq).

Enables firewall (SSH + K8s API + HTTP/HTTPS).

Installs RKE2.

Creates /etc/rancher/rke2/config.yaml with a random token + detected IP.

Starts RKE2 server.

Copies rke2.yaml into your user’s home (/home/user/rke2.yaml).

Prints your cluster token + kubeconfig path.
