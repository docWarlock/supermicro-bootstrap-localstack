#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="localstack"

echo "[*] Installing Helm (if missing)..."
if ! command -v helm >/dev/null 2>&1; then
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

echo "[*] Adding LocalStack Helm repo..."
helm repo add localstack https://localstack.github.io/helm-charts
helm repo update

echo "[*] Creating values file for LocalStack..."
cat > values-localstack.yaml <<'EOF'
image:
  repository: localstack/localstack
  tag: "latest"

service:
  type: ClusterIP
  ports:
    edge: 4566

mountDind:
  enabled: true    # required for Lambda, ECS, etc.

extraEnvVars:
  - name: SERVICES
    value: s3,sqs,iam,ecr

persistence:
  enabled: true
  size: 20Gi
EOF

echo "[*] Installing LocalStack into namespace '${NAMESPACE}'..."
helm upgrade --install localstack localstack/localstack \
  --namespace ${NAMESPACE} --create-namespace \
  -f values-localstack.yaml

echo "[*] Waiting for LocalStack pod to be ready..."
kubectl -n ${NAMESPACE} rollout status deploy/localstack --timeout=180s

echo "---------------------------------------------------"
echo "✅ LocalStack is deployed in namespace: ${NAMESPACE}"
echo "   To access it locally, run:"
echo "     kubectl -n ${NAMESPACE} port-forward svc/localstack 4566:4566"
echo
echo "   Example test:"
echo "     pip install awscli-local"
echo "     awslocal --endpoint-url=http://localhost:4566 s3 ls"
echo "---------------------------------------------------"
