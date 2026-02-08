resource "grafana_dashboard" "postgres_metrics" {
  config_json = jsonencode({
    title   = "PostgreSQL Metrics"
    uid     = "postgres-metrics"
    
    panels = [
      {
        id    = 1
        title = "PostgreSQL Connections"
        type  = "graph"
        gridPos = {
          x = 0
          y = 0
          w = 12
          h = 8
        }
        targets = [
          {
            expr         = "pg_stat_database_numbackends{datname=\"postgres\"}"
            refId        = "A"
            legendFormat = "Active Connections"
          }
        ]
      },
      {
        id    = 2
        title = "Timestamp Records Count"
        type  = "stat"
        gridPos = {
          x = 12
          y = 0
          w = 12
          h = 8
        }
        targets = [
          {
            expr  = "pg_stat_user_tables_n_tup_ins{relname=\"timestamps\"}"
            refId = "A"
          }
        ]
      },
      {
        id    = 3
        title = "Database Size"
        type  = "gauge"
        gridPos = {
          x = 0
          y = 8
          w = 12
          h = 8
        }
        targets = [
          {
            expr  = "pg_database_size_bytes{datname=\"postgres\"}"
            refId = "A"
          }
        ]
      },
      {
        id    = 4
        title = "Transactions per Second"
        type  = "graph"
        gridPos = {
          x = 12
          y = 8
          w = 12
          h = 8
        }
        targets = [
          {
            expr         = "rate(pg_stat_database_xact_commit{datname=\"postgres\"}[5m])"
            refId        = "A"
            legendFormat = "Commits/sec"
          }
        ]
      }
    ]
  })
}
