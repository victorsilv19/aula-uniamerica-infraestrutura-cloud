# Diagrama da Arquitetura

O diagrama abaixo representa a infraestrutura implementada no Google Cloud Platform para o desafio, atendendo a todos os requisitos de segurança, redundância e comunicação exigidos.

```mermaid
flowchart TD
    %% ─── ATORES ────────────────────────────────────────────────
    User(["🌐 Navegador do Usuário<br/>(Internet)"])
    DNS["🔍 DuckDNS<br/>(Resolução de Nomes)"]
    Hacker(["⛔ Tráfego Não Autorizado<br/>(Acesso Direto)"])

    %% ─── PROXY REVERSO / LOAD BALANCER ────────────────────────
    subgraph LB ["☁️ GCP Global Load Balancer — Proxy Reverso"]
        FWD_HTTPS["Forwarding Rule<br/>🔒 TCP :443 (HTTPS)"]
        FWD_HTTP["Forwarding Rule<br/>🔓 TCP :80 (HTTP)"]
        REDIR["URL Map<br/>↪ Redireciona 80 → 443"]
        SSL["Certificado SSL Gerenciado<br/>🔐 TLS Terminado aqui"]
        Armor["🛡️ Google Cloud Armor<br/>Firewall de Borda (WAF)"]
        Router["URL Map<br/>🔀 Roteamento por Host Header"]

        FWD_HTTP --> REDIR
        REDIR --> FWD_HTTPS
        FWD_HTTPS --> SSL
        SSL --> Armor
        Armor --> Router
    end

    %% ─── REGIÃO PRIMÁRIA ────────────────────────────────────────
    subgraph Regiao1 ["🟢 Região Primária — us-central1 (Limite Privado)"]
        NEG_FE1["Serverless NEG<br/>(Frontend Primary)"]
        FE1["🖥️ Cloud Run: frontend-primary<br/>Porta Interna: 8080"]
        NEG_BE["Serverless NEG<br/>(Backend)"]
        BE["⚙️ Cloud Run: backend<br/>Porta Interna: 5000"]
        VPC["🔒 VPC Connector<br/>(Saída privada)"]

        NEG_FE1 --> FE1
        NEG_BE --> BE
        BE --> VPC
    end

    %% ─── REGIÃO SECUNDÁRIA ──────────────────────────────────────
    subgraph Regiao2 ["🟢 Região Secundária — us-east1 (Limite Privado)"]
        NEG_FE2["Serverless NEG<br/>(Frontend Secondary)"]
        FE2["🖥️ Cloud Run: frontend-secondary<br/>Porta Interna: 8080"]

        NEG_FE2 --> FE2
    end

    %% ─── BANCO DE DADOS ─────────────────────────────────────────
    subgraph DB ["🗄️ MongoDB Atlas (Limite Privado)"]
        FW_Atlas{{"🔒 IP Whitelist<br/>(Network Access)"}}
        Atlas[("MongoDB Cluster<br/>Serviço Gerenciado")]

        FW_Atlas --> Atlas
    end

    %% ─── OBSERVABILIDADE ────────────────────────────────────────
    subgraph Obs ["📊 GCP Operations — Observabilidade"]
        Logging[("📋 Cloud Logging<br/>Armazena logs JSON")]
        Monitoring[("📈 Cloud Monitoring<br/>Log-based Metrics & Painéis")]
        Admin(["👤 Administrador<br/>GCP IAM Roles"])

        Logging -.-> Monitoring
        Monitoring -.-> Admin
    end

    %% ─── FLUXOS DE CONEXÃO ──────────────────────────────────────
    User ==>|"DNS Lookup"| DNS
    User -->|"HTTPS :443"| FWD_HTTPS
    Router -->|"Frontend US-Central"| NEG_FE1
    Router -->|"Frontend US-East"| NEG_FE2
    Router -->|"API / Backend"| NEG_BE
    VPC -->|"TCP :27017"| FW_Atlas

    FE1 -.->|"Logs stdout"| Logging
    FE2 -.->|"Logs stdout"| Logging
    BE -.->|"Logs pino-http"| Logging

    Hacker -.->|"Bloqueado WAF"| Armor
    Hacker -.->|"Bloqueado Ingress"| FE1
    Hacker -.->|"Bloqueado Ingress"| BE
    Hacker -.->|"Bloqueado IP Whitelist"| FW_Atlas

    %% ─── ESTILOS DOS NÓS ────────────────────────────────────────
    classDef user fill:#dbeafe,stroke:#2563eb,stroke-width:2px,color:#1e3a8a
    classDef lb fill:#ede9fe,stroke:#7c3aed,stroke-width:2px,color:#3b0764
    classDef private fill:#dcfce7,stroke:#16a34a,stroke-width:2px,color:#14532d
    classDef db fill:#fef9c3,stroke:#ca8a04,stroke-width:2px,color:#713f12
    classDef obs fill:#f1f5f9,stroke:#64748b,stroke-width:2px,color:#1e293b
    classDef blocked fill:#fee2e2,stroke:#dc2626,stroke-width:2px,color:#7f1d1d
    classDef dns fill:#e0f2fe,stroke:#0284c7,stroke-width:2px,color:#0c4a6e

    class User user
    class DNS dns
    class FWD_HTTPS,FWD_HTTP,REDIR,SSL,Armor,Router lb
    class NEG_FE1,FE1,NEG_BE,BE,VPC,NEG_FE2,FE2 private
    class FW_Atlas,Atlas db
    class Logging,Monitoring,Admin obs
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
