#!/bin/bash

# KServe Deployment Script
# Quick commands for deploying and managing KServe + Streamlit

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE=${NAMESPACE:-mlops-prod}
MODEL_IMAGE=${MODEL_IMAGE:-rakarun/mlops:house-price-model-latest}
STREAMLIT_IMAGE=${STREAMLIT_IMAGE:-rakarun/mlops:streamlit-latest}
CLUSTER_TYPE=${CLUSTER_TYPE:-kind}  # kind, eks, gke, aks

echo -e "${GREEN}🚀 KServe Deployment Script${NC}"
echo "Namespace: $NAMESPACE"
echo "Model Image: $MODEL_IMAGE"
echo "Streamlit Image: $STREAMLIT_IMAGE"
echo ""

# Function to print section headers
print_header() {
    echo -e "${YELLOW}>>> $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    print_header "Checking prerequisites..."

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}❌ kubectl not found${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ kubectl found${NC}"

    # Check cluster connection
    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${RED}❌ Cannot connect to Kubernetes cluster${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Connected to cluster${NC}"

    # Check KServe installation
    if ! kubectl get crd inferenceservices.serving.kserve.io &> /dev/null; then
        echo -e "${RED}❌ KServe not installed${NC}"
        echo "Install KServe with:"
        echo "  kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.11.0/kserve.yaml"
        exit 1
    fi
    echo -e "${GREEN}✓ KServe installed${NC}"
}

# Function to deploy manifests
deploy() {
    print_header "Deploying KServe + Streamlit..."

    kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -f inference-service.yaml
    kubectl apply -f streamlit-deployment.yaml

    echo -e "${GREEN}✓ Deployment initiated${NC}"
    echo ""
    print_header "Waiting for services to be ready..."

    # Wait for InferenceService
    kubectl wait --for=condition=Ready inferenceservice/house-price-predictor \
        --timeout=300s -n $NAMESPACE 2>/dev/null || true

    # Wait for Streamlit deployment
    kubectl wait --for=condition=available --timeout=300s \
        deployment/streamlit-app -n $NAMESPACE 2>/dev/null || true

    echo -e "${GREEN}✓ Services deployed${NC}"
}

# Function to check status
status() {
    print_header "Deployment Status"

    echo ""
    echo "InferenceService:"
    kubectl get inferenceservice house-price-predictor -n $NAMESPACE

    echo ""
    echo "Streamlit Deployment:"
    kubectl get deployment streamlit-app -n $NAMESPACE

    echo ""
    echo "Pods:"
    kubectl get pods -n $NAMESPACE -l "app in (house-price-predictor, streamlit-app)"

    echo ""
    echo "Services:"
    kubectl get svc -n $NAMESPACE -l "app in (house-price-predictor, streamlit-app)"
}

# Function to get logs
logs() {
    local component=$1

    if [ "$component" = "model" ]; then
        print_header "Model Service Logs"
        kubectl logs -f -n $NAMESPACE \
            -l "serving.kserve.io/inferenceservice=house-price-predictor" \
            --all-containers=true --max-log-requests=10 --tail=100
    elif [ "$component" = "streamlit" ]; then
        print_header "Streamlit Logs"
        kubectl logs -f -n $NAMESPACE \
            deployment/streamlit-app --all-containers=true --tail=100
    else
        echo "Usage: $0 logs [model|streamlit]"
    fi
}

# Function to port forward
portforward() {
    print_header "Setting up port forwarding..."

    echo "Forwarding KServe API to http://localhost:8080"
    kubectl port-forward svc/house-price-predictor 8080:80 -n $NAMESPACE &
    MODEL_PID=$!

    echo "Forwarding Streamlit to http://localhost:8501"
    kubectl port-forward svc/streamlit-app 8501:80 -n $NAMESPACE &
    STREAMLIT_PID=$!

    echo ""
    echo -e "${GREEN}✓ Port forwarding active${NC}"
    echo "  Model API: http://localhost:8080"
    echo "  Streamlit UI: http://localhost:8501"
    echo ""
    echo "Press Ctrl+C to stop port forwarding"
    wait
}

# Function to test predictions
test_prediction() {
    print_header "Testing Model Prediction"

    local api_endpoint="http://localhost:8080/v1/models/house-price-predictor:predict"

    echo "Sending test request to $api_endpoint"
    echo ""

    curl -s -X POST "$api_endpoint" \
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
        }' | python -m json.tool

    echo ""
    echo -e "${GREEN}✓ Test request sent${NC}"
}

# Function to update model
update_model() {
    local new_image=$1

    if [ -z "$new_image" ]; then
        echo "Usage: $0 update-model <new-image-uri>"
        exit 1
    fi

    print_header "Updating model image to $new_image"

    kubectl patch inferenceservice house-price-predictor \
        -n $NAMESPACE \
        -p "{\"spec\":{\"predictor\":{\"model\":{\"image\":\"$new_image\"}}}}"

    echo -e "${GREEN}✓ Model image updated${NC}"
}

# Function to cleanup
cleanup() {
    print_header "Cleaning up..."

    kubectl delete -f streamlit-deployment.yaml -n $NAMESPACE 2>/dev/null || true
    kubectl delete -f inference-service.yaml -n $NAMESPACE 2>/dev/null || true

    echo -e "${GREEN}✓ Cleanup complete${NC}"
}

# Function to show help
show_help() {
    cat << EOF
KServe Deployment Script

Usage: $0 <command> [options]

Commands:
  check              Check prerequisites
  deploy             Deploy KServe + Streamlit
  status             Show deployment status
  logs [component]   Show logs (model|streamlit)
  portforward        Set up port forwarding
  test               Test model prediction
  update-model IMG   Update model image
  cleanup            Delete all resources
  help               Show this help message

Examples:
  $0 check
  $0 deploy
  $0 status
  $0 logs model
  $0 portforward
  $0 test
  $0 update-model rakarun/mlops:house-price-model-v2
  $0 cleanup

Environment Variables:
  NAMESPACE         Kubernetes namespace (default: default)
  MODEL_IMAGE       Model image URI (default: rakarun/mlops:house-price-model-latest)
  STREAMLIT_IMAGE   Streamlit image URI (default: rakarun/mlops:streamlit-latest)
  CLUSTER_TYPE      Cluster type: kind, eks, gke, aks (default: kind)

EOF
}

# Main script
main() {
    local command=${1:-help}

    case $command in
        check)
            check_prerequisites
            ;;
        deploy)
            check_prerequisites
            deploy
            status
            ;;
        status)
            status
            ;;
        logs)
            logs $2
            ;;
        portforward)
            portforward
            ;;
        test)
            test_prediction
            ;;
        update-model)
            update_model $2
            ;;
        cleanup)
            cleanup
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}Unknown command: $command${NC}"
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
