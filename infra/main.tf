# =============================================================================
# Infraestrutura GCP — Aplicação Todo List (Serverless)
# =============================================================================
# Componentes:
#   - Cloud Run (Frontend x2 regiões + Backend x1)
#   - Google Cloud HTTPS Load Balancer (Proxy Reverso)
#   - Certificados SSL gerenciados pelo Google
#   - Serverless NEGs
#   - Artifact Registry (repositório de imagens Docker)
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# --- Provider ---
provider "google" {
  project = var.project_id
  region  = var.region_primary
}

# =============================================================================
# 1. HABILITAR APIs NECESSÁRIAS
# =============================================================================
resource "google_project_service" "apis" {
  for_each = toset([
    "run.googleapis.com",
    "compute.googleapis.com",
    "artifactregistry.googleapis.com",
    "certificatemanager.googleapis.com",
  ])

  project = var.project_id
  service = each.value

  disable_dependent_services = false
  disable_on_destroy         = false
}

# =============================================================================
# 2. ARTIFACT REGISTRY — Repositório de Imagens Docker
# =============================================================================
resource "google_artifact_registry_repository" "todo_app" {
  location      = var.region_primary
  repository_id = "todo-app"
  description   = "Repositório de imagens Docker da aplicação Todo List"
  format        = "DOCKER"

  depends_on = [google_project_service.apis]
}

# =============================================================================
# 3. CLOUD RUN — FRONT-END (2 regiões para redundância)
# =============================================================================

# --- Front-end: Região Primária (us-central1) ---
resource "google_cloud_run_v2_service" "frontend_primary" {
  name     = "frontend-primary"
  location = var.region_primary

  template {
    containers {
      image = var.frontend_image

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "256Mi"
        }
      }
    }

    scaling {
      min_instance_count = 0
      max_instance_count = 3
    }
  }

  # Ingress: permite acesso do Load Balancer E da internet
  # (Front-end precisa ser acessível via LB)
  ingress = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  depends_on = [google_project_service.apis]
}

# --- Front-end: Região Secundária (us-east1) — Redundância ---
resource "google_cloud_run_v2_service" "frontend_secondary" {
  name     = "frontend-secondary"
  location = var.region_secondary

  template {
    containers {
      image = var.frontend_image

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "256Mi"
        }
      }
    }

    scaling {
      min_instance_count = 0
      max_instance_count = 3
    }
  }

  ingress = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  depends_on = [google_project_service.apis]
}

# =============================================================================
# 4. CLOUD RUN — BACK-END (1 região, ingress restrito)
# =============================================================================
resource "google_cloud_run_v2_service" "backend" {
  name     = "backend"
  location = var.region_primary

  template {
    containers {
      image = var.backend_image

      ports {
        container_port = 5000
      }

      # Variáveis de ambiente para o back-end
      env {
        name  = "MONGODB_URI"
        value = var.mongodb_uri
      }

      env {
        name  = "CORS_ORIGIN"
        value = var.cors_origin != "" ? var.cors_origin : "https://${var.frontend_domain}"
      }

      env {
        name  = "PORT"
        value = "5000"
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }
    }

    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }
  }

  # SEGURANÇA: Apenas Load Balancer interno pode acessar
  # Acesso direto pela internet é BLOQUEADO
  ingress = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  depends_on = [google_project_service.apis]
}

# =============================================================================
# 5. IAM — Permitir acesso público via Load Balancer
# =============================================================================

# Front-end: permitir invocações (via LB)
resource "google_cloud_run_v2_service_iam_member" "frontend_primary_invoker" {
  project  = var.project_id
  location = var.region_primary
  name     = google_cloud_run_v2_service.frontend_primary.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_v2_service_iam_member" "frontend_secondary_invoker" {
  project  = var.project_id
  location = var.region_secondary
  name     = google_cloud_run_v2_service.frontend_secondary.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Back-end: permitir invocações (via LB)
resource "google_cloud_run_v2_service_iam_member" "backend_invoker" {
  project  = var.project_id
  location = var.region_primary
  name     = google_cloud_run_v2_service.backend.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# =============================================================================
# 6. SERVERLESS NEGs (Network Endpoint Groups) — Conectam Cloud Run ao LB
# =============================================================================

# NEG: Frontend Primário
resource "google_compute_region_network_endpoint_group" "frontend_primary_neg" {
  name                  = "frontend-primary-neg"
  region                = var.region_primary
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = google_cloud_run_v2_service.frontend_primary.name
  }
}

# NEG: Frontend Secundário
resource "google_compute_region_network_endpoint_group" "frontend_secondary_neg" {
  name                  = "frontend-secondary-neg"
  region                = var.region_secondary
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = google_cloud_run_v2_service.frontend_secondary.name
  }
}

# NEG: Backend
resource "google_compute_region_network_endpoint_group" "backend_neg" {
  name                  = "backend-neg"
  region                = var.region_primary
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = google_cloud_run_v2_service.backend.name
  }
}

# =============================================================================
# 7. LOAD BALANCER HTTPS — FRONT-END (Proxy Reverso)
# =============================================================================

# IP externo estático para o Front-end
resource "google_compute_global_address" "frontend_ip" {
  name = "frontend-lb-ip"
}

# Backend Service (LB) — Front-end
resource "google_compute_backend_service" "frontend_backend" {
  name                  = "frontend-backend-service"
  protocol              = "HTTPS"
  load_balancing_scheme = "EXTERNAL_MANAGED"

  backend {
    group = google_compute_region_network_endpoint_group.frontend_primary_neg.id
  }

  backend {
    group = google_compute_region_network_endpoint_group.frontend_secondary_neg.id
  }
}

# URL Map — Front-end
resource "google_compute_url_map" "frontend_url_map" {
  name            = "frontend-url-map"
  default_service = google_compute_backend_service.frontend_backend.id
}

# Certificado SSL gerenciado pelo Google — Front-end
resource "google_compute_managed_ssl_certificate" "frontend_cert" {
  name = "frontend-ssl-cert"

  managed {
    domains = [var.frontend_domain]
  }
}

# HTTPS Proxy — Front-end
resource "google_compute_target_https_proxy" "frontend_https_proxy" {
  name             = "frontend-https-proxy"
  url_map          = google_compute_url_map.frontend_url_map.id
  ssl_certificates = [google_compute_managed_ssl_certificate.frontend_cert.id]
}

# Forwarding Rule HTTPS (443) — Front-end
resource "google_compute_global_forwarding_rule" "frontend_https" {
  name                  = "frontend-https-rule"
  target                = google_compute_target_https_proxy.frontend_https_proxy.id
  ip_address            = google_compute_global_address.frontend_ip.address
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

# HTTP → HTTPS Redirect — Front-end
resource "google_compute_url_map" "frontend_http_redirect" {
  name = "frontend-http-redirect"

  default_url_redirect {
    https_redirect = true
    strip_query    = false
  }
}

resource "google_compute_target_http_proxy" "frontend_http_proxy" {
  name    = "frontend-http-proxy"
  url_map = google_compute_url_map.frontend_http_redirect.id
}

resource "google_compute_global_forwarding_rule" "frontend_http" {
  name                  = "frontend-http-redirect-rule"
  target                = google_compute_target_http_proxy.frontend_http_proxy.id
  ip_address            = google_compute_global_address.frontend_ip.address
  port_range            = "80"
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

# =============================================================================
# 8. LOAD BALANCER HTTPS — BACK-END (Proxy Reverso / API)
# =============================================================================

# IP externo estático para o Back-end
resource "google_compute_global_address" "backend_ip" {
  name = "backend-lb-ip"
}

# Backend Service (LB) — Back-end
resource "google_compute_backend_service" "backend_backend" {
  name                  = "backend-backend-service"
  protocol              = "HTTPS"
  load_balancing_scheme = "EXTERNAL_MANAGED"

  backend {
    group = google_compute_region_network_endpoint_group.backend_neg.id
  }
}

# URL Map — Back-end
resource "google_compute_url_map" "backend_url_map" {
  name            = "backend-url-map"
  default_service = google_compute_backend_service.backend_backend.id
}

# Certificado SSL gerenciado pelo Google — Back-end
resource "google_compute_managed_ssl_certificate" "backend_cert" {
  name = "backend-ssl-cert"

  managed {
    domains = [var.backend_domain]
  }
}

# HTTPS Proxy — Back-end
resource "google_compute_target_https_proxy" "backend_https_proxy" {
  name             = "backend-https-proxy"
  url_map          = google_compute_url_map.backend_url_map.id
  ssl_certificates = [google_compute_managed_ssl_certificate.backend_cert.id]
}

# Forwarding Rule HTTPS (443) — Back-end
resource "google_compute_global_forwarding_rule" "backend_https" {
  name                  = "backend-https-rule"
  target                = google_compute_target_https_proxy.backend_https_proxy.id
  ip_address            = google_compute_global_address.backend_ip.address
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

# HTTP → HTTPS Redirect — Back-end
resource "google_compute_url_map" "backend_http_redirect" {
  name = "backend-http-redirect"

  default_url_redirect {
    https_redirect = true
    strip_query    = false
  }
}

resource "google_compute_target_http_proxy" "backend_http_proxy" {
  name    = "backend-http-proxy"
  url_map = google_compute_url_map.backend_http_redirect.id
}

resource "google_compute_global_forwarding_rule" "backend_http" {
  name                  = "backend-http-redirect-rule"
  target                = google_compute_target_http_proxy.backend_http_proxy.id
  ip_address            = google_compute_global_address.backend_ip.address
  port_range            = "80"
  load_balancing_scheme = "EXTERNAL_MANAGED"
}
