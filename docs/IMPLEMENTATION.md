# DevOps Exercise - Solution Overview

## Executive Summary

Built a production-grade local Kubernetes environment running Jenkins CI/CD, PostgreSQL database, and Grafana monitoring - all automated and accessible via Traefik ingress (no port-forwarding).

---

## Architecture

### Infrastructure
- **Platform:** K3d (lightweight Kubernetes) on AWS EC2 Ubuntu 22.04
- **Cluster:** 1 server + 2 agent nodes
- **Ingress:** Traefik (pre-installed with K3d)
- **Access:** All services via domain names (jenkins.local, grafana.local)

### Components

#### 1. PostgreSQL Database
- **Deployment:** Bitnami Helm chart
- **Storage:** 5Gi persistent volume
- **Table:** `timestamps` (id, recorded_at, worker_pod)
- **Security:** Password in Kubernetes secrets

#### 2. Jenkins CI/CD
- **Deployment:** Official Jenkins Helm chart
- **Workers:** Dynamic Kubernetes pods (ephemeral)
- **Job:** `record-timestamp` - runs every 5 minutes, writes to PostgreSQL
- **Configuration:** JCasC for Kubernetes cloud setup

#### 3. Monitoring Stack
- **postgres-exporter:** Exposes PostgreSQL metrics (port 9187)
- **Prometheus:** Scrapes metrics every 30 seconds
- **Grafana:** Visualizes metrics via dashboard
- **IaC:** Dashboard provisioned using Terraform

---

## Data Flow

```
Jenkins (every 5 min) → Dynamic Worker Pod → PostgreSQL → Inserts timestamp
                                                ↓
                                        postgres-exporter
                                                ↓
                                           Prometheus
                                                ↓
                                            Grafana (displays metrics)
```

---

## Key Features

✅ **No Port-Forwarding:** All services accessed via Traefik IngressRoutes  
✅ **Dynamic Workers:** Jenkins creates/destroys pods per job  
✅ **Infrastructure as Code:** Terraform provisions Grafana dashboard  
✅ **Persistent Storage:** PostgreSQL data survives pod restarts  
✅ **Secrets Management:** Kubernetes secrets, cross-namespace sharing  
✅ **Real-time Monitoring:** Live PostgreSQL metrics in Grafana  

---

## Automation Stack

| Component | Tool | Purpose |
|-----------|------|---------|
| Cluster | K3d | Lightweight Kubernetes |
| PostgreSQL | Helm (Bitnami) | Database deployment |
| Jenkins | Helm (Official) | CI/CD with K8s workers |
| Prometheus | Helm (kube-prometheus-stack) | Metrics collection |
| Grafana | Helm (Official) | Visualization |
| Dashboard | Terraform | IaC for Grafana |
| Ingress | Traefik | HTTP routing |

---

## Access URLs

- **Jenkins:** http://jenkins.local (admin / admin123)
- **Grafana:** http://grafana.local (admin / admin123)

---

## Metrics Captured

**Live Dashboard Panels:**
- PostgreSQL active connections (~2)
- Timestamp records inserted (5+)
- Database size (~7.9 MB)
- Transactions per second (~0.2/sec)

---

## Project Structure

```
cxdo-devops-exercise/
├── k3d/
│   └── cluster-config.yaml          # K3d cluster definition
├── helm-values/
│   ├── postgres-values.yaml         # PostgreSQL config
│   ├── jenkins-values.yaml          # Jenkins config
│   ├── prometheus-values.yaml       # Prometheus config
│   └── grafana-values.yaml          # Grafana config
├── k8s/
│   ├── namespaces.yaml              # Namespace definitions
│   ├── postgres-exporter.yaml       # Metrics exporter
│   ├── terraform-runner.yaml        # Terraform executor pod
│   └── ingress-routes/
│       ├── jenkins-ingress.yaml     # Jenkins routing
│       └── grafana-ingress.yaml     # Grafana routing
└── terraform/
    ├── main.tf                      # Terraform provider
    └── dashboard.tf                 # Grafana dashboard IaC
```

---

## Deployment Summary

### 1. Environment Setup (10 min)
```bash
# Install: Docker, kubectl, Helm, K3d, Terraform
# Create K3d cluster with Traefik
# Configure DNS (jenkins.local, grafana.local)
```

### 2. PostgreSQL (5 min)
```bash
# Generate password → Create secret
# Deploy via Helm with init script
# Verify table creation
```

### 3. Jenkins (15 min)
```bash
# Deploy via Helm with plugins
# Configure Kubernetes cloud via JCasC
# Create pipeline job (writes to PostgreSQL)
# Fix agent tunnel configuration
```

### 4. Monitoring (15 min)
```bash
# Deploy postgres-exporter
# Deploy Prometheus (scrapes exporter)
# Deploy Grafana
# Run Terraform inside cluster → Create dashboard
```

**Total Time:** ~45 minutes (excluding troubleshooting)

---

## Technical Highlights

### Kubernetes Features Used
- **Namespaces:** Resource isolation (jenkins, database, monitoring)
- **Secrets:** Secure credential storage
- **PersistentVolumes:** Stateful data for PostgreSQL/Jenkins
- **Services:** ClusterIP for internal communication
- **Dynamic Pods:** Ephemeral Jenkins workers

### Jenkins Kubernetes Integration
- Pipeline defines pod spec inline (YAML in Groovy)
- Worker pod contains `psql` container
- Secret injection via environment variables
- Automatic pod cleanup after job completion

### Monitoring Architecture
- **Exporter Pattern:** postgres-exporter translates PostgreSQL stats to Prometheus metrics
- **Pull-based:** Prometheus scrapes exporter every 30s
- **Visualization:** Grafana queries Prometheus PromQL

### Infrastructure as Code
- **Terraform:** Manages Grafana dashboard declaratively
- **Helm:** Manages application deployments
- **Kubernetes Manifests:** Manages custom resources (IngressRoutes, postgres-exporter)

---

## Challenges Overcome

1. **Plugin Dependencies:** Resolved by using `:latest` versions
2. **Agent Connectivity:** Fixed by manually configuring Jenkins tunnel
3. **DNS Resolution:** Ran Terraform inside cluster pod
4. **Password Interpolation:** Used native exporter env vars (DATA_SOURCE_URI/USER/PASS)
5. **Cross-namespace Secrets:** Copied secret to Jenkins namespace

---

## Production Readiness Gaps

**Current State:** Functional demo environment  
**For Production, Add:**

- **Security:** TLS certificates, secrets rotation, RBAC, network policies
- **High Availability:** Multiple Jenkins replicas, PostgreSQL replication
- **Backup:** Automated DB backups to S3, Jenkins config backups
- **Monitoring:** AlertManager, log aggregation (Loki), distributed tracing
- **GitOps:** ArgoCD/Flux for declarative deployments

---

## Key Learnings

1. **Traefik Ingress > Port-forwarding** for production-like setups
2. **JCasC has limits** - complex scripts better created manually
3. **Namespace isolation** requires secret duplication strategy
4. **Application-native configs** more reliable than custom interpolation
5. **Run Terraform where DNS works** - inside cluster for k8s resources

---

## Conclusion

Successfully demonstrated end-to-end DevOps practices:
- **CI/CD:** Jenkins with Kubernetes-native workers
- **Database:** PostgreSQL with persistent storage
- **Monitoring:** Prometheus + Grafana with IaC
- **Networking:** Traefik ingress (production pattern)
- **Automation:** Helm + Terraform + kubectl

All services accessible via clean URLs, no manual port-forwarding, infrastructure fully codified.