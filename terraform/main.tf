terraform {
  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 3.0"
    }
  }
}

provider "grafana" {
  url  = "http://grafana.monitoring.svc.cluster.local"
  auth = "admin:admin123"
}
