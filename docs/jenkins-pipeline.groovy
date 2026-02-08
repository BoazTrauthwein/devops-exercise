pipeline {
    agent {
        kubernetes {
            yaml """
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: psql
    image: postgres:15-alpine
    command: ['sleep']
    args: ['infinity']
    env:
    - name: PGPASSWORD
      valueFrom:
        secretKeyRef:
          name: postgres-credentials
          key: postgres-password
"""
        }
    }
    stages {
        stage('Record Timestamp') {
            steps {
                container('psql') {
                    sh '''
                        echo "Connecting to PostgreSQL..."
                        psql -h postgres-postgresql.database.svc.cluster.local -U postgres -d postgres -c "INSERT INTO timestamps (recorded_at, worker_pod) VALUES (NOW(), '$HOSTNAME');"
                        echo "Timestamp recorded successfully!"
                    '''
                }
            }
        }
    }
}
