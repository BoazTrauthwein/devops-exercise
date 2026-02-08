resource "grafana_data_source" "prometheus" {
  type = "prometheus"
  name = "Prometheus"
  url  = "http://prometheus-kube-prometheus-prometheus.monitoring.svc.cluster.local:9090"
  
  is_default = true
}
