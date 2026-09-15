# Diagrama da Arquitetura

O diagrama abaixo representa a infraestrutura implementada no Google Cloud Platform para o desafio, atendendo a todos os requisitos de segurança, redundância e comunicação exigidos.

```mermaid
flowchart TD
    %% ─── LEGENDA ───────────────────────────────────────────────
    subgraph Legenda [" 📘 Legenda"]
        direction LR
        L1[ ] -->|"HTTP/S (Aplicação)"| L2[ ]
        L3[ ] -.->|"Observabilidade"| L4[ ]
        L5[ ] -.-x|"Bloqueado"| L6[ ]
        L7[ ] ==>|"Resolução DNS"| L8[ ]
        style Legenda fill:#f0f4ff,stroke:#6c8ebf,stroke-width:1px,stroke-dasharray:4 4,color:#333
    end

    %% ─── ATORES ────────────────────────────────────────────────
    User(["🌐 Navegador do Usuário\n(Internet)"])
    DNS["🔍 DuckDNS\n(Resolução de Nomes)"]
    Hacker(["⛔ Tráfego Não Autorizado\n(Acesso Direto)"])

    %% ─── PROXY REVERSO / LOAD BALANCER ────────────────────────
    subgraph LB ["☁️  GCP Global Load Balancer — Proxy Reverso"]
        direction TB
        FWD_HTTPS["Forwarding Rule\n🔒 TCP :443 (HTTPS)"]
        FWD_HTTP["Forwarding Rule\n🔓 TCP :80 (HTTP)"]
        REDIR["URL Map\n↪ Redireciona 80 → 443"]
        SSL["Certificado SSL Gerenciado\n🔐 TLS Terminado aqui"]
        Armor["🛡️ Google Cloud Armor\nFirewall de Borda (WAF)"]
        Router["URL Map\n🔀 Roteamento por Host Header"]

        FWD_HTTP --> REDIR
        FWD_HTTPS --> SSL
        SSL --> Armor
        Armor --> Router
    end

    %% ─── REGIÃO PRIMÁRIA ────────────────────────────────────────
    subgraph Regiao1 ["🟢 Região Primária — us-central1  (Limite Privado)"]
        direction TB
        NEG_FE1["Serverless NEG\n(Frontend Primary)"]
        FE1["🖥️ Cloud Run: frontend-primary\nPorta Interna: 8080\nIngress: Internal-LB apenas"]
        NEG_BE["Serverless NEG\n(Backend)"]
        BE["⚙️ Cloud Run: backend\nPorta Interna: 5000\nIngress: Internal-LB apenas"]
        VPC["🔒 VPC Connector\n(Saída privada para MongoDB)"]

        NEG_FE1 -->|"HTTPS interno"| FE1
        NEG_BE -->|"HTTPS interno"| BE
        BE -->|"TCP :27017"| VPC
    end

    %% ─── REGIÃO SECUNDÁRIA ──────────────────────────────────────
    subgraph Regiao2 ["🟢 Região Secundária — us-east1  (Limite Privado)"]
        direction TB
        NEG_FE2["Serverless NEG\n(Frontend Secondary)"]
        FE2["🖥️ Cloud Run: frontend-secondary\nPorta Interna: 8080\nIngress: Internal-LB apenas"]

        NEG_FE2 -->|"HTTPS interno"| FE2
    end

    %% ─── BANCO DE DADOS ─────────────────────────────────────────
    subgraph DB ["🗄️  MongoDB Atlas  (Limite Privado)"]
        direction LR
        FW_Atlas{{"🔒 IP Whitelist\n(Network Access)"}}
        Atlas[("MongoDB Cluster\nServiço Gerenciado\nTCP :27017")]

        FW_Atlas -->|"Conexão autorizada"| Atlas
    end

    %% ─── OBSERVABILIDADE ────────────────────────────────────────
    subgraph Obs ["📊 GCP Operations — Observabilidade"]
        direction TB
        Logging[("📋 Cloud Logging\nArmazena logs JSON\nRetenção: 30 dias")]
        Monitoring[("📈 Cloud Monitoring\nMQL / Log-based Metrics\n4 Painéis Configurados")]
        Admin(["👤 Administrador\nAcesso via GCP IAM\n(roles/viewer ou superior)"])

        Logging -.->|"Log-based Metrics"| Monitoring
        Monitoring -.->|"Visualiza Dashboards"| Admin
    end

    %% ─── FLUXO 1: DNS ───────────────────────────────────────────
    User ==>"deploynasexta.duckdns.org\n→ IP Estático do LB" DNS
    User ==>"api-deploynasexta.duckdns.org\n→ mesmo IP do LB" DNS

    %% ─── FLUXO 2: USUÁRIO → FRONTEND ───────────────────────────
    User -->|"HTTPS :443\ndeploynasexta.duckdns.org"| FWD_HTTPS
    Router -->|"Host: deploynasexta.*\nBalanceia entre regiões"| NEG_FE1
    Router -->|"Host: deploynasexta.*\nBalanceia entre regiões"| NEG_FE2

    %% ─── FLUXO 3: USUÁRIO → API (chamada AJAX do browser) ──────
    User -->|"HTTPS :443\napi-deploynasexta.duckdns.org"| FWD_HTTPS
    Router -->|"Host: api-deploynasexta.*\nRoteia para Backend"| NEG_BE

    %% ─── FLUXO 4: BACKEND → BANCO ───────────────────────────────
    VPC -->|"TCP :27017\nmongodb+srv://..."| FW_Atlas

    %% ─── FLUXO 5: OBSERVABILIDADE ───────────────────────────────
    FE1 -.->|"stdout JSON\n(Agente GCP nativo)"| Logging
    FE2 -.->|"stdout JSON\n(Agente GCP nativo)"| Logging
    BE  -.->|"Logs pino-http JSON\nCampos: method, route,\nstatus, duration_ms"| Logging
    LB  -.->|"Logs de rede e latência\n(GCP nativo)"| Logging

    %% ─── BLOQUEIOS ───────────────────────────────────────────────
    Hacker -.-x|"🚫 BLOQUEADO\nCloud Armor (WAF)"| Armor
    Hacker -.-x|"🚫 BLOQUEADO\nIngress Interno"| FE1
    Hacker -.-x|"🚫 BLOQUEADO\nIngress Interno"| BE
    Hacker -.-x|"🚫 BLOQUEADO\nIP Whitelist"| FW_Atlas

    %% ─── ESTILOS ─────────────────────────────────────────────────
    classDef user        fill:#dbeafe,stroke:#2563eb,stroke-width:2px,color:#1e3a8a
    classDef lb          fill:#ede9fe,stroke:#7c3aed,stroke-width:2px,color:#3b0764
    classDef private     fill:#dcfce7,stroke:#16a34a,stroke-width:2px,color:#14532d
    classDef db          fill:#fef9c3,stroke:#ca8a04,stroke-width:2px,color:#713f12
    classDef obs         fill:#f1f5f9,stroke:#64748b,stroke-width:2px,color:#1e293b
    classDef blocked     fill:#fee2e2,stroke:#dc2626,stroke-width:2px,stroke-dasharray:5 5,color:#7f1d1d
    classDef dns         fill:#e0f2fe,stroke:#0284c7,stroke-width:2px,color:#0c4a6e

    class User user
    class DNS dns
    class LB,FWD_HTTPS,FWD_HTTP,REDIR,SSL,Armor,Router lb
    class Regiao1,Regiao2,NEG_FE1,FE1,NEG_BE,BE,VPC,NEG_FE2,FE2 private
    class DB,FW_Atlas,Atlas db
    class Obs,Logging,Monitoring,Admin obs
    class Hacker blocked
```

## Resumo dos Controles de Acesso

| Componente | Regra de Acesso | Fluxos Permitidos | Fluxos Bloqueados |
|------------|-----------------|-------------------|-------------------|
| **Load Balancer** | Exposto à internet na porta 443 | `Usuário → Load Balancer` (HTTPS) | Tráfego HTTP não seguro (porta 80) e portas diferentes da 443 |
| **Front-end** | Bloqueado da internet (Ingress Restrito) | `Load Balancer → Front-end` | `Internet → Front-end` (Acesso direto) |
| **Back-end** | Bloqueado da internet (Ingress Restrito) | `Load Balancer → Back-end` | `Internet → Back-end` (Acesso direto) |
| **Cloud Armor** | Firewall de Borda | Tráfego web limpo | Ataques conhecidos, DDoS e IPs maliciosos |
| **MongoDB Atlas**| Firewall de Rede | `Back-end (VPC) → Atlas` (TCP 27017) | `Internet → Atlas` |
| **GCP Console**| Controle via IAM | `Admin → Cloud Monitoring` | Acessos não autenticados / sem permissão na GCP |
