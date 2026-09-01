# Diagrama de Arquitetura — Infraestrutura Serverless GCP

## Visão Geral da Arquitetura

```mermaid
graph TB
    subgraph INTERNET["🌐 INTERNET"]
        USER["👤 Usuário<br/>Browser"]
    end

    subgraph DNS_LAYER["📡 DNS"]
        DNS_FE["DNS<br/>frontend.dominio.com<br/>→ IP do LB Frontend"]
        DNS_BE["DNS<br/>api.dominio.com<br/>→ IP do LB Backend"]
    end

    subgraph GCP["☁️ Google Cloud Platform"]
        subgraph LB_LAYER["🔀 Proxy Reverso / Load Balancers"]
            LB_FE["HTTPS Load Balancer<br/>Frontend<br/>Porta: 443 (TLS 1.2+)<br/>Certificado SSL gerenciado<br/>Redireciona HTTP→HTTPS"]
            LB_BE["HTTPS Load Balancer<br/>Backend (API)<br/>Porta: 443 (TLS 1.2+)<br/>Certificado SSL gerenciado<br/>Redireciona HTTP→HTTPS"]
        end

        subgraph FE_LAYER["🖥️ Front-end (Redundante)"]
            FE1["Cloud Run<br/>frontend-primary<br/>us-central1<br/>Porta: 8080<br/>Ingress: internal-and-cloud-lb"]
            FE2["Cloud Run<br/>frontend-secondary<br/>us-east1<br/>Porta: 8080<br/>Ingress: internal-and-cloud-lb"]
        end

        subgraph BE_LAYER["⚙️ Back-end"]
            BE["Cloud Run<br/>backend<br/>us-central1<br/>Porta: 5000<br/>Ingress: internal-and-cloud-lb<br/>CORS: frontend.dominio.com"]
        end
    end

    subgraph DB_LAYER["🗄️ Banco de Dados"]
        DB["MongoDB Atlas<br/>Serverless / Free Tier (M0)<br/>Porta: 27017 (TLS)<br/>IP Allowlist: apenas Cloud Run IPs"]
    end

    %% Fluxos permitidos
    USER -->|"HTTPS :443"| DNS_FE
    DNS_FE -->|"Resolve IP"| LB_FE
    LB_FE -->|"HTTP :8080"| FE1
    LB_FE -->|"HTTP :8080"| FE2

    FE1 -.->|"JS no Browser<br/>HTTPS :443"| DNS_BE
    FE2 -.->|"JS no Browser<br/>HTTPS :443"| DNS_BE
    DNS_BE -->|"Resolve IP"| LB_BE
    LB_BE -->|"HTTP :5000"| BE

    BE -->|"TLS :27017"| DB

    %% Estilos
    classDef internet fill:#e3f2fd,stroke:#1565c0,stroke-width:2px
    classDef dns fill:#fff3e0,stroke:#e65100,stroke-width:2px
    classDef lb fill:#f3e5f5,stroke:#6a1b9a,stroke-width:2px
    classDef frontend fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px
    classDef backend fill:#fff8e1,stroke:#f57f17,stroke-width:2px
    classDef database fill:#fce4ec,stroke:#c62828,stroke-width:2px

    class USER internet
    class DNS_FE,DNS_BE dns
    class LB_FE,LB_BE lb
    class FE1,FE2 frontend
    class BE backend
    class DB database
```

---

## Diagrama de Fluxos Permitidos e Bloqueados

```mermaid
graph LR
    subgraph PERMITIDOS["✅ Fluxos PERMITIDOS"]
        A1["Usuário"] -->|"HTTPS :443"| B1["DNS Frontend"]
        B1 --> C1["LB Frontend"]
        C1 --> D1["Cloud Run FE #1"]
        C1 --> D2["Cloud Run FE #2"]
        
        E1["Frontend JS"] -->|"HTTPS :443"| F1["DNS API"]
        F1 --> G1["LB Backend"]
        G1 --> H1["Cloud Run Backend"]
        H1 -->|"TLS :27017"| I1["MongoDB Atlas"]
    end
```

```mermaid
graph LR
    subgraph BLOQUEADOS["❌ Fluxos BLOQUEADOS"]
        X1["Internet"] -.->|"❌ BLOQUEADO<br/>Ingress: internal-only"| Y1["Cloud Run Backend<br/>(URL direta)"]
        X2["Internet"] -.->|"❌ BLOQUEADO<br/>IP Allowlist"| Y2["MongoDB Atlas"]
        X3["Internet"] -.->|"❌ BLOQUEADO<br/>Ingress: internal-only"| Y3["Cloud Run Frontend<br/>(URL direta)"]
        X4["Frontend"] -.->|"❌ BLOQUEADO<br/>IP Allowlist"| Y4["MongoDB Atlas"]
    end
    
    style X1 fill:#ffcdd2
    style X2 fill:#ffcdd2
    style X3 fill:#ffcdd2
    style X4 fill:#ffcdd2
    style Y1 fill:#ffcdd2
    style Y2 fill:#ffcdd2
    style Y3 fill:#ffcdd2
    style Y4 fill:#ffcdd2
```

---

## Detalhamento de Segurança por Componente

```mermaid
graph TB
    subgraph SEC["🔒 Regras de Segurança"]
        subgraph FW_LB_FE["Firewall: Load Balancer Frontend"]
            R1["✅ Entrada: Internet → porta 443 (HTTPS)"]
            R2["✅ HTTP 80 → Redireciona para HTTPS 443"]
            R3["❌ Todas as outras portas bloqueadas"]
        end
        
        subgraph FW_FE["Firewall: Cloud Run Frontend"]
            R4["✅ Entrada: apenas do Load Balancer"]
            R5["❌ Entrada direta da Internet bloqueada"]
            R6["Porta interna: 8080"]
        end

        subgraph FW_LB_BE["Firewall: Load Balancer Backend"]
            R7["✅ Entrada: Internet → porta 443 (HTTPS)"]
            R8["✅ HTTP 80 → Redireciona para HTTPS 443"]
            R9["✅ CORS: apenas frontend.dominio.com"]
            R10["❌ Todas as outras portas bloqueadas"]
        end
        
        subgraph FW_BE["Firewall: Cloud Run Backend"]
            R11["✅ Entrada: apenas do Load Balancer"]
            R12["❌ Entrada direta da Internet bloqueada"]
            R13["Porta interna: 5000"]
        end
        
        subgraph FW_DB["Firewall: MongoDB Atlas"]
            R14["✅ Entrada: apenas IPs do Cloud Run"]
            R15["❌ Entrada da Internet bloqueada"]
            R16["Porta: 27017 (TLS obrigatório)"]
            R17["Autenticação: usuário + senha"]
        end
    end
```

---

## Redundância do Front-end

```mermaid
graph TB
    LB["HTTPS Load Balancer<br/>(Global)"] --> FE1["Cloud Run FE<br/>us-central1 ✅"]
    LB --> FE2["Cloud Run FE<br/>us-east1 ✅"]
    
    FE1 -->|"Se us-central1 cair"| FAILOVER["LB redireciona<br/>automaticamente"]
    FAILOVER --> FE2
    
    style FE1 fill:#c8e6c9,stroke:#2e7d32
    style FE2 fill:#c8e6c9,stroke:#2e7d32
    style FAILOVER fill:#fff9c4,stroke:#f57f17
```

---

## Tabela de Portas e Protocolos

| Origem | Destino | Porta | Protocolo | Status |
|--------|---------|-------|-----------|--------|
| Usuário (Internet) | LB Frontend | 443 | HTTPS/TLS 1.2+ | ✅ Permitido |
| Usuário (Internet) | LB Frontend | 80 | HTTP | 🔄 Redireciona p/ 443 |
| LB Frontend | Cloud Run FE #1 | 8080 | HTTP (interno) | ✅ Permitido |
| LB Frontend | Cloud Run FE #2 | 8080 | HTTP (interno) | ✅ Permitido |
| Frontend JS (Browser) | LB Backend | 443 | HTTPS/TLS 1.2+ | ✅ Permitido |
| LB Backend | Cloud Run Backend | 5000 | HTTP (interno) | ✅ Permitido |
| Cloud Run Backend | MongoDB Atlas | 27017 | TLS | ✅ Permitido |
| Internet | Cloud Run FE (direto) | * | * | ❌ Bloqueado |
| Internet | Cloud Run BE (direto) | * | * | ❌ Bloqueado |
| Internet | MongoDB Atlas | 27017 | * | ❌ Bloqueado |
| Frontend | MongoDB Atlas | 27017 | * | ❌ Bloqueado |

---

## Fluxo Completo de uma Requisição

```mermaid
sequenceDiagram
    actor User as 👤 Usuário
    participant DNS as 📡 DNS
    participant LB_FE as 🔀 LB Frontend
    participant FE as 🖥️ Cloud Run FE
    participant LB_BE as 🔀 LB Backend
    participant BE as ⚙️ Cloud Run BE
    participant DB as 🗄️ MongoDB Atlas

    Note over User,DB: Fluxo 1: Carregar a página

    User->>DNS: Acessar frontend.dominio.com
    DNS->>LB_FE: Resolve para IP do LB
    LB_FE->>LB_FE: Termina TLS (HTTPS → HTTP)
    LB_FE->>FE: Encaminha para Cloud Run (porta 8080)
    FE->>User: Retorna HTML/JS/CSS

    Note over User,DB: Fluxo 2: Buscar tarefas (API)

    User->>DNS: JS faz fetch para api.dominio.com/todos
    DNS->>LB_BE: Resolve para IP do LB
    LB_BE->>LB_BE: Termina TLS + Verifica CORS
    LB_BE->>BE: Encaminha para Cloud Run (porta 5000)
    BE->>DB: Consulta MongoDB (TLS :27017)
    DB->>BE: Retorna dados
    BE->>LB_BE: Resposta JSON
    LB_BE->>User: Resposta HTTPS com dados
```
