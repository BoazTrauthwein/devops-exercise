#!/bin/bash

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

wait_for_pod() {
    local namespace=$1
    local label=$2
    local timeout=${3:-300}
    
    log_info "Waiting for pod with label $label in namespace $namespace..."
    kubectl wait --for=condition=ready pod -l "$label" -n "$namespace" --timeout="${timeout}s" || {
        log_error "Timeout waiting for pod"
        return 1
    }
}

# Install function
install() {
    log_info "Starting installation..."
    
    # Pre-flight checks
    log_info "Running pre-flight checks..."
    command -v docker >/dev/null 2>&1 || { log_error "Docker not installed"; exit 1; }
    command -v kubectl >/dev/null 2>&1 || { log_error "kubectl not installed"; exit 1; }
    command -v helm >/dev/null 2>&1 || { log_error "Helm not installed"; exit 1; }
    command -v k3d >/dev/null 2>&1 || { log_error "K3d not installed"; exit 1; }
    
    # Check Docker is running
    docker ps >/dev/null 2>&1 || { log_error "Docker is not running or you don't have permissions"; exit 1; }
    
    log_info "✓ All prerequisites met"
    
    # Step 1: Create K3d cluster
    log_info "Creating K3d cluster..."
    if k3d cluster list | grep -q "cxdo"; then
        log_warn "Cluster 'cxdo' already exists, skipping creation"
    else
        k3d cluster create --config k3d/cluster-config.yaml
        sleep 10
    fi
    
    # Step 2: Create namespaces
    log_info "Creating namespaces..."
    kubectl apply -f k8s/namespaces.yaml
    
    # Step 3: Deploy PostgreSQL
    log_info "Deploying PostgreSQL..."
    
    # Generate password
    PG_PASSWORD=$(openssl rand -base64 16)
    echo "PostgreSQL Password: $PG_PASSWORD" > .credentials.txt
    log_info "PostgreSQL password saved to .credentials.txt"
    
    # Create secret in database namespace
    kubectl create secret generic postgres-credentials \
        -n database \
        --from-literal=postgres-password="$PG_PASSWORD" \
        --from-literal=password="$PG_PASSWORD" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Add Helm repos
    log_info "Adding Helm repositories..."
    helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null 2>&1 || true
    helm repo add jenkins https://charts.jenkins.io >/dev/null 2>&1 || true
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
    helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
    helm repo update
    
    # Install PostgreSQL
    if helm list -n database | grep -q "postgres"; then
        log_warn "PostgreSQL already installed, skipping"
    else
        helm install postgres bitnami/postgresql \
            -n database \
            -f helm-values/postgres-values.yaml
    fi
    
    wait_for_pod "database" "app.kubernetes.io/name=postgresql"
    log_info "✓ PostgreSQL ready"
    
    # Step 4: Deploy postgres-exporter
    log_info "Deploying postgres-exporter..."
    kubectl apply -f k8s/postgres-exporter.yaml
    sleep 5
    wait_for_pod "database" "app=postgres-exporter"
    log_info "✓ postgres-exporter ready"
    
    # Step 5: Deploy Prometheus
    log_info "Deploying Prometheus..."
    if helm list -n monitoring | grep -q "prometheus"; then
        log_warn "Prometheus already installed, skipping"
    else
        helm install prometheus prometheus-community/kube-prometheus-stack \
            -n monitoring \
            -f helm-values/prometheus-values.yaml
    fi
    
    wait_for_pod "monitoring" "app.kubernetes.io/name=prometheus"
    log_info "✓ Prometheus ready"
    
    # Step 6: Deploy Grafana
    log_info "Deploying Grafana..."
    if helm list -n monitoring | grep -q "grafana"; then
        log_warn "Grafana already installed, skipping"
    else
        helm install grafana grafana/grafana \
            -n monitoring \
            -f helm-values/grafana-values.yaml
    fi
    
    wait_for_pod "monitoring" "app.kubernetes.io/name=grafana"
    kubectl apply -f k8s/ingress-routes/grafana-ingress.yaml
    log_info "✓ Grafana ready"
    
    # Step 7: Deploy Jenkins
    log_info "Deploying Jenkins..."
    
    # Copy PostgreSQL secret to Jenkins namespace
    kubectl get secret postgres-credentials -n database -o yaml | \
        sed 's/namespace: database/namespace: jenkins/' | \
        kubectl apply -f -
    
    if helm list -n jenkins | grep -q "jenkins"; then
        log_warn "Jenkins already installed, skipping"
    else
        helm install jenkins jenkins/jenkins \
            -n jenkins \
            -f helm-values/jenkins-values.yaml
    fi
    
    wait_for_pod "jenkins" "app.kubernetes.io/component=jenkins-controller" 600
    kubectl apply -f k8s/ingress-routes/jenkins-ingress.yaml
    log_info "✓ Jenkins ready"
    
    # Step 8: Deploy Terraform runner and provision Grafana dashboard
    log_info "Provisioning Grafana dashboard with Terraform..."
    kubectl apply -f k8s/terraform-runner.yaml
    kubectl wait --for=condition=ready pod/terraform-runner -n monitoring --timeout=120s || {
    log_error "Terraform runner pod not ready"
    return 1
    }
    
    # Copy Terraform files
    kubectl cp terraform/main.tf monitoring/terraform-runner:/workspace/main.tf
    kubectl cp terraform/dashboard.tf monitoring/terraform-runner:/workspace/dashboard.tf
    
    # Run Terraform
    log_info "Running Terraform apply..."
    kubectl exec -n monitoring terraform-runner -- sh -c "
        cd /workspace && 
        terraform init && 
        terraform apply -auto-approve
    " || log_warn "Terraform apply had issues, dashboard may need manual creation"
    
    log_info "✓ Grafana dashboard provisioned"
    
    # Final output
    echo ""
    echo "========================================="
    log_info "Installation complete!"
    echo "========================================="
    echo ""
    echo "Access URLs (add to /etc/hosts on your local machine):"
    echo "  <EC2-PUBLIC-IP> jenkins.local grafana.local traefik.local"
    echo ""
    echo "Services:"
    echo "  Jenkins:  http://jenkins.local (admin / admin123)"
    echo "  Grafana:  http://grafana.local (admin / admin123)"
    echo ""
    echo "Credentials saved in: .credentials.txt"
    echo ""
    log_warn "IMPORTANT: Configure Jenkins tunnel manually:"
    echo "  1. Go to Manage Jenkins → Clouds → kubernetes"
    echo "  2. Set Jenkins tunnel to: jenkins-agent.jenkins.svc.cluster.local:50000"
    echo "  3. Save"
    echo ""
    log_warn "IMPORTANT: Create the record-timestamp job manually in Jenkins UI"
    echo "  See docs/jenkins-pipeline.groovy for the pipeline code"
    echo ""
}

# Uninstall function
uninstall() {
    log_info "Starting uninstallation..."
    
    # Delete Terraform resources
    log_info "Destroying Terraform resources..."
    kubectl exec -n monitoring terraform-runner -- sh -c "
        cd /workspace && terraform destroy -auto-approve
    " 2>/dev/null || log_warn "Terraform destroy failed or already destroyed"
    
    # Uninstall Helm releases
    log_info "Uninstalling Helm releases..."
    helm uninstall grafana -n monitoring 2>/dev/null || true
    helm uninstall prometheus -n monitoring 2>/dev/null || true
    helm uninstall jenkins -n jenkins 2>/dev/null || true
    helm uninstall postgres -n database 2>/dev/null || true
    
    # Delete K3d cluster
    log_info "Deleting K3d cluster..."
    k3d cluster delete cxdo 2>/dev/null || true
    
    # Clean up credentials file
    rm -f .credentials.txt
    
    log_info "✓ Uninstallation complete"
}

# Main script logic
case "${1:-}" in
    install)
        install
        ;;
    uninstall)
        uninstall
        ;;
    *)
        echo "Usage: $0 {install|uninstall}"
        echo ""
        echo "  install    - Deploy the entire stack"
        echo "  uninstall  - Remove everything"
        exit 1
        ;;
esac
