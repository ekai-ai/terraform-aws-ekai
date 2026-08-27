resource "kubernetes_namespace" "ekai_db_init" {
  metadata {
    name = "ekai-db-init"
  }
}
resource "kubernetes_secret" "postgres_master" {
  metadata {
    name      = "postgres-ekai-secret"
    namespace = kubernetes_namespace.ekai_db_init.metadata[0].name
  }

  data = {
    host                  = replace(aws_db_instance.ekai_postgresql.endpoint, ":5432", "")
    port                  = "5432"
    username              = local.backend_db_username
    password              = local.backend_db_password
    semantics_db_name     = local.semantics_db_name
    semantics_db_username = local.semantics_db_username
    semantics_db_password = local.semantics_db_password
  }

  type = "Opaque"
}

resource "kubernetes_job" "db_init" {
  metadata {
    name      = "ekai-db-init"
    namespace = kubernetes_namespace.ekai_db_init.metadata[0].name
  }

  spec {
    backoff_limit = 3

    template {
      metadata {}

      spec {
        restart_policy = "OnFailure"

        container {
          name  = "init-db"
          image = "postgres:15"

          env {
            name = "PGHOST"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.postgres_master.metadata[0].name
                key  = "host"
              }
            }
          }

          env {
            name = "PGPORT"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.postgres_master.metadata[0].name
                key  = "port"
              }
            }
          }

          env {
            name = "PGUSER"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.postgres_master.metadata[0].name
                key  = "username"
              }
            }
          }

          env {
            name = "PGPASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.postgres_master.metadata[0].name
                key  = "password"
              }
            }
          }

          env {
            name = "DB_NAME"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.postgres_master.metadata[0].name
                key  = "semantics_db_name"
              }
            }
          }

          env {
            name = "DB_USER"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.postgres_master.metadata[0].name
                key  = "semantics_db_username"
              }
            }
          }

          env {
            name = "DB_PASS"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.postgres_master.metadata[0].name
                key  = "semantics_db_password"
              }
            }
          }

          command = [
            "bash",
            "-c",
            <<-EOT
              set -euo pipefail

              until psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres -c '\q'; do
                echo "Waiting for PostgreSQL to be ready..."
                sleep 5
              done

              echo "🔌 Testing PostgreSQL connection (admin DB)..."
              psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres -c "SELECT 1"

              echo "📦 Creating database if not exists..."
              psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres -tAc \
              "SELECT 1 FROM pg_database WHERE datname = '$DB_NAME'" | grep -q 1 \
              || psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres \
              -c "CREATE DATABASE \"$DB_NAME\";"

              echo "👤 Creating role if not exists..."
              psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres -v ON_ERROR_STOP=1 <<SQL
              DO \$\$
              BEGIN
                IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$DB_USER') THEN
                  CREATE ROLE "$DB_USER" LOGIN PASSWORD '$DB_PASS';
                END IF;
              END
              \$\$;
              SQL

              echo "🔐 Granting permissions..."
              psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres -c "ALTER DATABASE \"$DB_NAME\" OWNER TO \"$DB_USER\";"
              psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres -c "GRANT ALL PRIVILEGES ON DATABASE \"$DB_NAME\" TO \"$DB_USER\";"

              echo "🧩 Enabling pgvector..."
              psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$DB_NAME" -c "CREATE EXTENSION IF NOT EXISTS vector;"

              echo "✅ DATABASE INITIALIZATION COMPLETE"
  EOT
          ]

        }
      }
    }
  }

  depends_on = [
    aws_db_instance.ekai_postgresql
  ]
}
