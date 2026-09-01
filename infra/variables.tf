# =============================================================================
# Variáveis de Configuração — Infraestrutura GCP
# =============================================================================

variable "project_id" {
  description = "ID do projeto GCP"
  type        = string
  # ALTERE para o ID do seu projeto GCP
  # Exemplo: "meu-projeto-123456"
}

variable "region_primary" {
  description = "Região primária do Cloud Run"
  type        = string
  default     = "us-central1"
}

variable "region_secondary" {
  description = "Região secundária do Cloud Run (redundância do front-end)"
  type        = string
  default     = "us-east1"
}

variable "frontend_domain" {
  description = "Domínio/subdomínio do front-end (ex: frontend-seugrupo.dominio.com)"
  type        = string
  # ALTERE para o domínio fornecido pelo professor
}

variable "backend_domain" {
  description = "Domínio/subdomínio do back-end/API (ex: api-seugrupo.dominio.com)"
  type        = string
  # ALTERE para o domínio fornecido pelo professor
}

variable "mongodb_uri" {
  description = "URI de conexão do MongoDB Atlas"
  type        = string
  sensitive   = true
  # ALTERE para a URI do seu cluster MongoDB Atlas
  # Exemplo: "mongodb+srv://usuario:senha@cluster0.xxxxx.mongodb.net/todo-app?retryWrites=true&w=majority"
}

variable "cors_origin" {
  description = "Origem permitida no CORS do back-end (domínio do frontend)"
  type        = string
  # Será preenchido automaticamente com base no frontend_domain
  default     = ""
}

variable "frontend_image" {
  description = "Imagem Docker do front-end no Artifact Registry"
  type        = string
  # Exemplo: "us-central1-docker.pkg.dev/meu-projeto/todo-app/frontend:latest"
}

variable "backend_image" {
  description = "Imagem Docker do back-end no Artifact Registry"
  type        = string
  # Exemplo: "us-central1-docker.pkg.dev/meu-projeto/todo-app/backend:latest"
}
