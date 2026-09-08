# Diagrama da Arquitetura

O diagrama abaixo representa a infraestrutura implementada no Google Cloud Platform para o desafio, atendendo a todos os requisitos de segurança, redundância e comunicação exigidos.

```mermaid
flowchart TD
    %% Atores e Internet
    User(("Usuário (Internet)"))
    DNS["Cloud DNS / DuckDNS<br/>(Resolução de Nomes)"]

    %% Google Cloud Load Balancer (Proxy Reverso)
    subgraph LB [Proxy Reverso Global - Load Balancer]
        SSL["Certificado SSL<br/>(Gerenciado)"]
        Armor["Google Cloud Armor<br/>(Firewall - Permite 443, Bloqueia L7 Attacks)"]
        Router["URL Map (Roteamento)"]
        
        SSL --> Armor
        Armor --> Router
    end

    %% Região 1 (us-central1)
    subgraph Regiao1 [Região 1: us-central1]
        NEG_FE1["NEG Serverless"]
        FE1["Front-end (Cloud Run)<br/>Ingress: Internal & LB"]
        NEG_BE["NEG Serverless"]
        BE["Back-end API (Cloud Run)<br/>Ingress: Internal & LB"]
        VPC["VPC Connector<br/>(Rede Privada)"]
        
        NEG_FE1 --> FE1
        NEG_BE --> BE
        BE --> VPC
    end

    %% Região 2 (us-east1)
    subgraph Regiao2 [Região 2: us-east1]
        NEG_FE2["NEG Serverless"]
        FE2["Front-end (Cloud Run)<br/>Ingress: Internal & LB"]
        
        NEG_FE2 --> FE2
    end

    %% Banco de Dados
    subgraph DB [MongoDB Atlas]
        Atlas[("MongoDB Cluster<br/>(Serviço Gerenciado)")]
        FW_Atlas{"Network Access<br/>(Firewall)"}
        
        FW_Atlas --> Atlas
    end

    %% Fluxos de Conexão - Usuário para Frontend
    User -- "1. Acesso ao Domínio\n(HTTPS :443)" --> DNS
    DNS -- "2. Resolve IP\n(136.69.42.110)" --> SSL
    Router -- "3. deploynasexta.duckdns.org\n(Balanceamento)" --> NEG_FE1
    Router -- "3. deploynasexta.duckdns.org\n(Balanceamento)" --> NEG_FE2

    %% Fluxos de Conexão - Frontend para Backend
    FE1 -. "4. Requisição API\n(HTTPS :443)" .-> DNS
    FE2 -. "4. Requisição API\n(HTTPS :443)" .-> DNS
    Router -- "5. api-deploynasexta.duckdns.org\n(Roteamento API)" --> NEG_BE

    %% Fluxo de Conexão - Backend para Banco de Dados
    VPC -- "6. Conexão DB\n(TCP :27017)" --> FW_Atlas

    %% Fluxos Bloqueados (Segurança)
    Hacker(("Acesso Direto\nInternet"))
    Hacker -.-x|BLOQUEADO| FE1
    Hacker -.-x|BLOQUEADO| BE
    Hacker -.-x|BLOQUEADO| FW_Atlas

    classDef allowed fill:#d4edda,stroke:#28a745,stroke-width:2px;
    classDef blocked fill:#f8d7da,stroke:#dc3545,stroke-width:2px,stroke-dasharray: 5 5;
    classDef highlight fill:#cce5ff,stroke:#007bff,stroke-width:2px;
    classDef db fill:#fff3cd,stroke:#ffc107,stroke-width:2px;

    class LB highlight
    class Regiao1,Regiao2 allowed
    class DB db
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
