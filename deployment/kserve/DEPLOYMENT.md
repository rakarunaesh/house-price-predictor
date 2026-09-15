# KServe Deployment Guide

This directory contains Kubernetes manifests for deploying the House Price Predictor model using KServe and Streamlit on Kubernetes.

## 📋 Architecture

```
┌─────────────────────────────────────────────────────┐
│              Kubernetes Cluster (EKS/GKE/AKS)       │
├─────────────────────────────────────────────────────┤
│                                                     │
│  ┌──────────────────────────────────────────────┐  │
│  │ KServe InferenceService                      │  │
│  │ (house-price-predictor)                      │  │
│  │                                              │  │
│  │ Pod: model serving                           │  │
│  │ • Sklearn model loaded                       │  │
│  │ • Accepts JSON requests                      │  │
│  │ • Auto-scales 1-5 replicas                   │  │
│  │ • Exposes /v1/models/*/predict endpoint     │  │
│  │                                              │  │
│  └──────────────────────────────────────────────┘  │
│                      ▲                             │
│                      │ (HTTP)                      │
│                      │                             │
│  ┌──────────────────────────────────────────────┐  │
│  │ Streamlit Deployment                         │  │
│  │ (streamlit-app)                              │  │
│  │                                              │  │
│  │ Pods: 2 replicas (load balanced)            │  │
│  │ • Streamlit UI on port 8501                 │  │
│  │ • Calls KServe API for predictions          │  │
│  │ • Auto-scales based on CPU/memory           │  │
│  │ • Exposed via LoadBalancer/Ingress          │  │
│  │                                              │  │
│  └──────────────────────────────────────────────┘  │
│                      ▲                             │
│                      │                             │
│                   Users                            │
│                                                     │
└─────────────────────────────────────────────────────┘
```

## 📦 Files

- **inference-service.yaml** — KServe InferenceService for the model
- **streamlit-deployment.yaml** — Kubernetes Deployment for Streamlit UI
- **kustomization.yaml** — Kustomize configuration for managing manifests

## 🚀 Prerequisites

### 1. Kubernetes Cluster
You need a running Kubernetes cluster:

```bash
# Option 1: Local cluster (kind)
kind create cluster --name house-price
kubectl cluster-info

# Option 2: AWS EKS
aws eks create-cluster --name house-price --region us-east-1 ...

# Option 3: GKE
gcloud container clusters create house-price --zone us-central1-a ...
```

### 2. KServe Installation
Install KServe on your cluster:

```bash
# Install KServe v0.11.0
kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.11.0/kserve.yaml
kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.11.0/kserve-runtimes.yaml

# Verify installation
kubectl get pods -n kserve
kubectl get crd | grep kserve
```

### 3. Docker Images
Ensure your Docker images are built and pushed:

```bash
# Build and push model image
docker build -f Dockerfile -t rakarun/mlops:house-price-model-latest .
docker push rakarun/mlops:house-price-model-latest

# Build and push Streamlit image
docker build -f streamlit_app/Dockerfile -t rakarun/mlops:streamlit-latest streamlit_app/
docker push rakarun/mlops:streamlit-latest
```

## 🔧 Deployment Steps

### Step 1: Deploy KServe InferenceService + Streamlit

```bash
# Navigate to kserve directory
cd deployment/kserve

# Deploy using kubectl
kubectl apply -f inference-service.yaml
kubectl apply -f streamlit-deployment.yaml

# Or deploy using kustomize
kubectl apply -k .
```

### Step 2: Verify Deployment

```bash
# Check InferenceService status
kubectl get inferenceservice
kubectl describe inferenceservice house-price-predictor

# Check pods are running
kubectl get pods -l app=house-price-predictor
kubectl get pods -l app=streamlit-app

# Watch pod creation
kubectl get pods -w
```

### Step 3: Port Forward for Testing (local cluster)

```bash
# Forward KServe API
kubectl port-forward svc/house-price-predictor 8080:80 &

# Forward Streamlit
kubectl port-forward svc/streamlit-app 8501:80 &

# Access Streamlit at http://localhost:8501
# API endpoint: http://localhost:8080
```

### Step 4: Get External IP (cloud clusters)

```bash
# For LoadBalancer services
kubectl get svc streamlit-app
# Shows EXTERNAL-IP for Streamlit

kubectl get svc house-price-predictor
# Shows EXTERNAL-IP for model API
```

## 🧪 Testing Predictions

### Using curl (after port-forward)

```bash
curl -X POST http://localhost:8080/v1/models/house-price-predictor:predict \
  -H "Content-Type: application/json" \
  -d '{
    "instances": [
      {
        "sqft": 1500,
        "bedrooms": 3,
        "bathrooms": 2,
        "location": 0,
        "year_built": 2000,
        "condition": 0
      }
    ]
  }'
```

### Using Python

```python
import requests

api_url = "http://localhost:8080/v1/models/house-price-predictor:predict"
data = {
    "instances": [
        {
            "sqft": 1500,
            "bedrooms": 3,
            "bathrooms": 2,
            "location": 0,
            "year_built": 2000,
            "condition": 0
        }
    ]
}

response = requests.post(api_url, json=data)
print(response.json())
```

### Using Streamlit UI

Once deployed, access Streamlit at:
- Local: `http://localhost:8501`
- Cloud: `http://<EXTERNAL-IP>:80`

Use the UI to make predictions visually.

## 📊 Monitoring

### Check Logs

```bash
# Model service logs
kubectl logs -f deployment/house-price-predictor-predictor

# Streamlit logs
kubectl logs -f deployment/streamlit-app

# Watch events
kubectl get events --sort-by='.lastTimestamp'
```

### Check Metrics

```bash
# CPU and memory usage
kubectl top pods

# If Prometheus installed:
# - Predictions per second
# - Inference latency
# - Error rate
```

## 🔄 Model Updates

### Update Model Image

```bash
# Build new image
docker build -t rakarun/mlops:house-price-model-v2 .
docker push rakarun/mlops:house-price-model-v2

# Update InferenceService
kubectl patch inferenceservice house-price-predictor \
  -p '{"spec":{"predictor":{"model":{"image":"rakarun/mlops:house-price-model-v2"}}}}'

# Or edit the manifest and reapply
kubectl apply -f inference-service.yaml
```

### Canary Deployment (A/B Testing)

Uncomment the `canaryTrafficPercent` section in `inference-service.yaml`:

```yaml
canaryTrafficPercent: 10  # Send 10% traffic to new model
```

Then deploy:
```bash
kubectl apply -f inference-service.yaml
```

This will:
- Keep 90% traffic on current model
- Send 10% to new model for testing
- Monitor metrics
- Gradually increase traffic if new model is better

## 🗑️ Cleanup

```bash
# Delete all resources
kubectl delete -f inference-service.yaml
kubectl delete -f streamlit-deployment.yaml

# Or using kustomize
kubectl delete -k .

# Delete cluster (if cloud)
kind delete cluster --name house-price
# OR
aws eks delete-cluster --name house-price
```

## 🐛 Troubleshooting

### InferenceService stuck in creating

```bash
# Check service status
kubectl describe inferenceservice house-price-predictor

# Check pod logs
kubectl logs -l serving.kserve.io/inferenceservice=house-price-predictor

# Check events
kubectl describe service house-price-predictor
```

### Streamlit can't reach API

Check environment variables:
```bash
kubectl exec -it deployment/streamlit-app -- env | grep API_URL
```

Should show: `API_URL=http://house-price-predictor.default.svc.cluster.local`

If wrong, update `streamlit-deployment.yaml` and reapply.

### Pod crashes

```bash
# Check logs
kubectl logs <pod-name>

# Check resource requests
kubectl describe pod <pod-name>

# May need to increase cluster resources
```

## 📚 Environment-Specific Overlays

Create overlays for different environments:

```
deployment/kserve/
├── base/
│   ├── inference-service.yaml
│   ├── streamlit-deployment.yaml
│   └── kustomization.yaml
├── overlays/
│   ├── dev/
│   │   └── kustomization.yaml
│   ├── staging/
│   │   └── kustomization.yaml
│   └── production/
│       └── kustomization.yaml
```

Deploy specific environment:
```bash
kubectl apply -k deployment/kserve/overlays/production/
```

## 🔒 Security Considerations

### Enable RBAC
```bash
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: house-price-app
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list"]
EOF
```

### Use Secrets for Credentials
```bash
kubectl create secret generic model-creds --from-literal=api-key=your-key
```

Reference in deployment:
```yaml
env:
  - name: API_KEY
    valueFrom:
      secretKeyRef:
        name: model-creds
        key: api-key
```

### Network Policies
Restrict traffic between pods.

## 📞 Support

For issues:
1. Check KServe docs: https://kserve.github.io/
2. Check Streamlit docs: https://docs.streamlit.io/
3. Check logs: `kubectl logs`
4. Check events: `kubectl get events`
