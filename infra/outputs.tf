# =============================================================================
# Outputs — Informações úteis após o deploy
# =============================================================================

output "frontend_lb_ip" {
  description = "IP do Load Balancer do Front-end (informar ao professor para DNS)"
  value       = google_compute_global_address.frontend_ip.address
}

output "backend_lb_ip" {
  description = "IP do Load Balancer do Back-end (informar ao professor para DNS)"
  value       = google_compute_global_address.backend_ip.address
}

output "frontend_url" {
  description = "URL do Front-end via domínio"
  value       = "https://${var.frontend_domain}"
}

output "backend_url" {
  description = "URL da API do Back-end via domínio"
  value       = "https://${var.backend_domain}"
}

output "frontend_cloud_run_primary" {
  description = "URL direta do Cloud Run Frontend (região primária) — NÃO usar em produção"
  value       = google_cloud_run_v2_service.frontend_primary.uri
}

output "frontend_cloud_run_secondary" {
  description = "URL direta do Cloud Run Frontend (região secundária) — NÃO usar em produção"
  value       = google_cloud_run_v2_service.frontend_secondary.uri
}

output "backend_cloud_run" {
  description = "URL direta do Cloud Run Backend — BLOQUEADA para acesso externo"
  value       = google_cloud_run_v2_service.backend.uri
}

output "instrucoes_dns" {
  description = "Instruções para configurar DNS com o professor"
  value       = <<-EOT
    
    =====================================================
    INSTRUÇÕES PARA SOLICITAR DNS AO PROFESSOR
    =====================================================
    
    Envie ao professor Laércio:
    
    1. Nome do grupo: [SEU GRUPO]
    
    2. Subdomínio Front-end: ${var.frontend_domain}
       IP Público: ${google_compute_global_address.frontend_ip.address}
       Serviço: Front-end da aplicação Todo List
    
    3. Subdomínio Back-end: ${var.backend_domain}
       IP Público: ${google_compute_global_address.backend_ip.address}
       Serviço: API Back-end da aplicação Todo List
    
    =====================================================
  EOT
}
