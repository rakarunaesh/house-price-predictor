# KServe Installation & Namespace Guide

Complete guide for installing, uninstalling, and managing KServe in specific Kubernetes namespaces.

## 📋 Prerequisites

```bash
# Install kubectl
# Install kubeadm/minikube/kind for cluster management
# Have a running Kubernetes cluster (v1.20+)

# Verify cluster
kubectl cluster-info
kubectl get nodes
```

## 🚀 Installing KServe

### Option 1: Install KServe in Default Namespace (Quickest)

```bash
# Install KServe manifests
kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.11.0/kserve.yaml

# Install KServe runtimes (sklearn, xgboost, tensorflow, pytorch)
kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.11.0/kserve-runtimes.yaml

# Wait for installation to complete
kubectl wait --for=condition=ready pod -l app=kserve-controller-manager -n kserve --timeout=300s

# Verify installation
kubectl get all -n kserve
kubectl get crd | grep kserve
```

### Option 2: Install KServe in Custom Namespace (Recommended for Production)

```bash
# Step 1: Create namespace
kubectl create namespace kserve
# or
kubectl create namespace mlops-prod

# Step 2: Install KServe in custom namespace
# Download manifests first
mkdir -p /tmp/kserve && cd /tmp/kserve
wget https://github.com/kserve/kserve/releases/download/v0.11.0/kserve.yaml
wget https://github.com/kserve/kserve/releases/download/v0.11.0/kserve-runtimes.yaml

# Step 3: Edit manifests to change namespace
sed -i 's/namespace: kserve/namespace: mlops-prod/g' kserve.yaml
sed -i 's/namespace: kserve/namespace: mlops-prod/g' kserve-runtimes.yaml

# Step 4: Apply manifests
kubectl apply -f kserve.yaml
kubectl apply -f kserve-runtimes.yaml

# Verify
kubectl get all -n mlops-prod
```

### Option 3: Using Kustomize for Namespace Installation

Create a custom kustomization:

```bash
# Create directory structure
mkdir -p kserve-install/overlays/mlops-prod
cd kserve-install

# Download base manifests
mkdir -p base
wget -O base/kserve.yaml https://github.com/kserve/kserve/releases/download/v0.11.0/kserve.yaml
wget -O base/kserve-runtimes.yaml https://github.com/kserve/kserve/releases/download/v0.11.0/kserve-runtimes.yaml

# Create base kustomization
cat > base/kustomization.yaml <<EOF
resources:
  - kserve.yaml
  - kserve-runtimes.yaml
EOF

# Create overlay for mlops-prod namespace
cat > overlays/mlops-prod/kustomization.yaml <<EOF
bases:
  - ../../base

namespace: mlops-prod

commonLabels:
  environment: production
  managed-by: kustomize
EOF

# Apply with namespace
kubectl apply -k overlays/mlops-prod/
```

### Option 4: Using Helm (If Available)

```bash
# Add KServe Helm repository
helm repo add kserve https://github.com/kserve/charts
helm repo update

# Install KServe in custom namespace
kubectl create namespace mlops-prod
helm install kserve kserve/kserve --namespace mlops-prod

# Verify
helm list -n mlops-prod
kubectl get all -n mlops-prod
```

## 🔍 Verify Installation

```bash
# Check KServe namespace
kubectl get all -n kserve
# OR
kubectl get all -n mlops-prod

# Check CRDs (Custom Resource Definitions)
kubectl get crd | grep kserve

# Should see:
# inferenceservices.serving.kserve.io
# servingruntimes.serving.kserve.io
# trainedmodels.serving.kserve.io

# Check controller is running
kubectl get pods -n kserve
# OR
kubectl get pods -n mlops-prod

# Should see:
# kserve-controller-manager-xxxx   1/1     Running
```

## 🗑️ Uninstalling KServe

### Step 1: Delete All InferenceServices First

```bash
# Delete from all namespaces
kubectl delete inferenceservice --all --all-namespaces

# Or specific namespace
kubectl delete inferenceservice --all -n default
kubectl delete inferenceservice --all -n mlops-prod
```

### Step 2: Uninstall KServe

#### Method 1: Delete Manifests (if installed from manifests)

```bash
# Uninstall runtimes first
kubectl delete -f https://github.com/kserve/kserve/releases/download/v0.11.0/kserve-runtimes.yaml

# Then uninstall KServe
kubectl delete -f https://github.com/kserve/kserve/releases/download/v0.11.0/kserve.yaml

# Verify namespace is deleted
kubectl get namespace kserve
# Should show: Error from server (NotFound): namespaces "kserve" not found
```

#### Method 2: Uninstall from Custom Namespace

```bash
# Delete resources in custom namespace
kubectl delete namespace mlops-prod

# This deletes:
# - All pods, services, deployments
# - KServe controller manager
# - All InferenceServices in that namespace
# - Namespace itself

# Verify
kubectl get namespace mlops-prod
# Should show: Error from server (NotFound)
```

#### Method 3: Using Helm (if installed with Helm)

```bash
# Uninstall Helm release
helm uninstall kserve -n mlops-prod

# Delete namespace
kubectl delete namespace mlops-prod
```

### Step 3: Clean Up CRDs (Optional, if fully removing)

```bash
# WARNING: This deletes all InferenceService definitions across cluster
# Only do if completely removing KServe

kubectl delete crd inferenceservices.serving.kserve.io
kubectl delete crd servingruntimes.serving.kserve.io
kubectl delete crd trainedmodels.serving.kserve.io
```

## 📍 Deploy Model to Custom Namespace

After installing KServe in a custom namespace, deploy your model there:

### Update Your Manifests

Edit `inference-service.yaml` and `streamlit-deployment.yaml`:

```yaml
# Change this:
metadata:
  namespace: default

# To this:
metadata:
  namespace: mlops-prod
```

### Deploy to Custom Namespace

```bash
# Method 1: Direct deployment
kubectl apply -f inference-service.yaml -n mlops-prod
kubectl apply -f streamlit-deployment.yaml -n mlops-prod

# Method 2: Using kustomize with namespace override
kubectl apply -k . -n mlops-prod

# Verify deployment in custom namespace
kubectl get inferenceservice -n mlops-prod
kubectl get deployment -n mlops-prod
kubectl get pods -n mlops-prod
```

## 🔄 Multi-Namespace Setup (Advanced)

Run multiple KServe instances in different namespaces:

```bash
# Development namespace
kubectl create namespace kserve-dev
kubectl apply -f kserve.yaml -n kserve-dev
kubectl apply -f kserve-runtimes.yaml -n kserve-dev

# Staging namespace
kubectl create namespace kserve-staging
kubectl apply -f kserve.yaml -n kserve-staging
kubectl apply -f kserve-runtimes.yaml -n kserve-staging

# Production namespace
kubectl create namespace kserve-prod
kubectl apply -f kserve.yaml -n kserve-prod
kubectl apply -f kserve-runtimes.yaml -n kserve-prod

# Deploy models to each namespace
kubectl apply -f inference-service.yaml -n kserve-dev
kubectl apply -f inference-service.yaml -n kserve-staging
kubectl apply -f inference-service.yaml -n kserve-prod

# List all InferenceServices across namespaces
kubectl get inferenceservice --all-namespaces
```

## 🚀 Complete Installation Script

```bash
#!/bin/bash

KSERVE_VERSION="0.11.0"
NAMESPACE="${1:-kserve}"

echo "Installing KServe v$KSERVE_VERSION in namespace: $NAMESPACE"

# Create namespace
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Download and install
wget -q -O /tmp/kserve.yaml https://github.com/kserve/kserve/releases/download/v${KSERVE_VERSION}/kserve.yaml
wget -q -O /tmp/kserve-runtimes.yaml https://github.com/kserve/kserve/releases/download/v${KSERVE_VERSION}/kserve-runtimes.yaml

# Replace namespace in manifests
sed -i "s/namespace: kserve/namespace: $NAMESPACE/g" /tmp/kserve.yaml
sed -i "s/namespace: kserve/namespace: $NAMESPACE/g" /tmp/kserve-runtimes.yaml

# Apply manifests
kubectl apply -f /tmp/kserve.yaml
kubectl apply -f /tmp/kserve-runtimes.yaml

# Wait for controller ready
kubectl wait --for=condition=ready pod \
  -l app=kserve-controller-manager \
  -n $NAMESPACE \
  --timeout=300s

echo "✅ KServe installation complete in namespace: $NAMESPACE"

# Verify
echo ""
echo "Verification:"
kubectl get all -n $NAMESPACE
```

Usage:
```bash
chmod +x install-kserve.sh
./install-kserve.sh kserve        # Install in kserve namespace
./install-kserve.sh mlops-prod    # Install in mlops-prod namespace
```

## 🧹 Complete Uninstall Script

```bash
#!/bin/bash

NAMESPACE="${1:-kserve}"

echo "⚠️  Uninstalling KServe from namespace: $NAMESPACE"
echo "This will delete all InferenceServices and the KServe controller"
echo ""

read -p "Are you sure? (yes/no): " -n 3 -r
echo
if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Proceeding with uninstallation..."
    
    # Delete InferenceServices
    kubectl delete inferenceservice --all -n $NAMESPACE
    
    # Delete namespace (this removes everything in it)
    kubectl delete namespace $NAMESPACE
    
    echo "✅ KServe uninstalled from namespace: $NAMESPACE"
else
    echo "Cancelled uninstallation"
fi
```

Usage:
```bash
chmod +x uninstall-kserve.sh
./uninstall-kserve.sh kserve        # Uninstall from kserve namespace
./uninstall-kserve.sh mlops-prod    # Uninstall from mlops-prod namespace
```

## 🔗 Port Forwarding from Custom Namespace

```bash
# Forward services from custom namespace
kubectl port-forward -n mlops-prod svc/house-price-predictor 8080:80
kubectl port-forward -n mlops-prod svc/streamlit-app 8501:80

# In another terminal, access:
# API: http://localhost:8080
# Streamlit: http://localhost:8501
```

## 📊 Namespace Isolation

Benefits of using custom namespaces:

```
1. Resource Isolation
   - Separate CPU/memory limits per namespace
   - Easier to track costs

2. Security
   - RBAC policies per namespace
   - Network policies for traffic control
   - Separate secrets per namespace

3. Environment Management
   - Dev, staging, prod in same cluster
   - Easy promotion between environments
   - Rollback capability

4. Multi-tenancy
   - Different teams use different namespaces
   - Teams don't interfere with each other
```

Example RBAC for namespace:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: kserve-user
  namespace: mlops-prod
rules:
  - apiGroups: ["serving.kserve.io"]
    resources: ["inferenceservices"]
    verbs: ["get", "list", "create", "update", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: kserve-user-binding
  namespace: mlops-prod
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: kserve-user
subjects:
  - kind: User
    name: mlops-engineer@company.com
    apiGroup: rbac.authorization.k8s.io
```

## 🆘 Troubleshooting

### KServe stuck in installing

```bash
# Check pod status
kubectl get pods -n kserve
kubectl describe pod kserve-controller-manager-xxx -n kserve

# Check logs
kubectl logs -n kserve deployment/kserve-controller-manager

# Force delete if stuck
kubectl delete pod -n kserve -l app=kserve-controller-manager --force --grace-period=0
```

### CRDs not found

```bash
# Check if CRDs are installed
kubectl get crd | grep kserve

# If missing, reapply manifests
kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.11.0/kserve.yaml
```

### InferenceService stuck in creating

```bash
# Check in correct namespace
kubectl get inferenceservice -n mlops-prod

# Describe the service for errors
kubectl describe inferenceservice house-price-predictor -n mlops-prod

# Check controller logs
kubectl logs -n kserve deployment/kserve-controller-manager
```
