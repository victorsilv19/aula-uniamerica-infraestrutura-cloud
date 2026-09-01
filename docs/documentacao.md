# Documentação — Infraestrutura Serverless na GCP

## 1. Serviços de Nuvem Utilizados

| Componente | Serviço GCP | Tipo |
|---|---|---|
| **Front-end** | Google Cloud Run (2 regiões) | Serverless |
| **Back-end** | Google Cloud Run (1 região) | Serverless |
| **Banco de Dados** | MongoDB Atlas (Free Tier M0) | Gerenciado/Serverless |
| **Proxy Reverso / HTTPS** | Google Cloud HTTPS Load Balancer | Gerenciado |
| **DNS** | Cloud DNS / DNS do Professor | Gerenciado |
| **Repositório de Imagens** | Google Artifact Registry | Gerenciado |
| **Certificado SSL** | Google-managed SSL Certificate | Gerenciado |

---

## 2. Por Que Esses Serviços Foram Escolhidos

### Cloud Run (Front-end e Back-end)
- **Serverless real**: escala automaticamente de 0 a N instâncias conforme a demanda
- **Paga por uso**: cobrança apenas quando há requisições (free tier: 2M req/mês)
- **Multi-região**: permite deploy em múltiplas regiões para redundância
- **Controle de ingress**: permite restringir acesso apenas via Load Balancer (`internal-and-cloud-load-balancing`), bloqueando acesso direto da internet
- **Baseado em containers**: aceita qualquer imagem Docker, compatível com a aplicação existente

### Google Cloud HTTPS Load Balancer (Proxy Reverso)
- **Proxy reverso nativo**: recebe requisições HTTPS e encaminha para os serviços Cloud Run
- **Terminação TLS**: gerencia certificados SSL automaticamente (Google-managed)
- **Distribuição global**: roteia tráfego para a região mais próxima do usuário
- **Redundância**: se uma região do Cloud Run cair, redireciona automaticamente para outra
- **Redirecionamento HTTP→HTTPS**: força uso de HTTPS em todas as conexões

### MongoDB Atlas (Banco de Dados)
- **Gerenciado**: backups, patches e monitoramento automáticos
- **Free Tier (M0)**: cluster gratuito com 512MB de armazenamento (suficiente para a atividade)
- **IP Allowlist**: permite configurar quais IPs podem se conectar (apenas os IPs do Cloud Run)
- **TLS obrigatório**: todas as conexões são criptografadas
- **Sem acesso público**: apenas IPs autorizados podem acessar

---

## 3. Como a Segurança Foi Implementada

### Princípio: Tudo bloqueado por padrão, liberar apenas o necessário

### 3.1 Front-end
| Regra | Configuração |
|---|---|
| Acesso externo | Apenas via Load Balancer (HTTPS :443) |
| Acesso direto ao Cloud Run | ❌ Bloqueado (`ingress: internal-and-cloud-load-balancing`) |
| Protocolo | HTTPS com TLS 1.2+ |
| HTTP | Redirecionado para HTTPS |
| Certificado SSL | Google-managed (renovação automática) |

### 3.2 Back-end
| Regra | Configuração |
|---|---|
| Acesso externo | Apenas via Load Balancer (HTTPS :443) |
| Acesso direto ao Cloud Run | ❌ Bloqueado (`ingress: internal-and-cloud-load-balancing`) |
| CORS | Restrito ao domínio do frontend (`CORS_ORIGIN=https://frontend.dominio.com`) |
| Métodos HTTP permitidos | GET, POST, PATCH, DELETE |
| Headers permitidos | Content-Type |

### 3.3 Banco de Dados
| Regra | Configuração |
|---|---|
| Acesso público | ❌ Bloqueado |
| IP Allowlist | Apenas IPs de saída do Cloud Run (via Cloud NAT) |
| Porta | 27017 (TLS obrigatório) |
| Autenticação | Usuário + senha (MongoDB Auth) |
| Quem acessa | Apenas o Back-end |

### 3.4 Resumo de Acessos

| De → Para | Status | Mecanismo de Bloqueio |
|---|---|---|
| Internet → Frontend (via domínio) | ✅ Permitido | HTTPS via LB |
| Internet → Backend (via domínio/API) | ✅ Permitido | HTTPS via LB |
| Internet → Cloud Run FE (URL direta) | ❌ Bloqueado | Ingress restrito |
| Internet → Cloud Run BE (URL direta) | ❌ Bloqueado | Ingress restrito |
| Internet → MongoDB Atlas | ❌ Bloqueado | IP Allowlist |
| Frontend → MongoDB Atlas | ❌ Bloqueado | IP Allowlist + sem driver |
| Backend → MongoDB Atlas | ✅ Permitido | IP Allowlist + credenciais |

---

## 4. Como Funciona a Redundância do Front-end

### Arquitetura Multi-Região

O Front-end é deployado em **duas regiões** do Cloud Run:

1. **us-central1** (Iowa, EUA) — região primária
2. **us-east1** (Carolina do Sul, EUA) — região secundária

### Como o Load Balancer Distribui o Tráfego

O Google Cloud HTTPS Load Balancer é **global** e possui as duas regiões como backends. Ele funciona assim:

1. **Operação normal**: O LB distribui as requisições entre as duas regiões, priorizando a mais próxima do usuário
2. **Falha em uma região**: Se o Cloud Run em uma região parar de responder (ou tiver `max-instances=0`), o LB automaticamente redireciona 100% do tráfego para a região que ainda está funcionando
3. **Recuperação**: Quando a região volta ao normal, o LB retoma a distribuição entre as duas

### Teste de Redundância

Para testar, reduzimos o `max-instances` de uma região para 0:
```bash
# Simular falha na região primária
gcloud run services update frontend-primary --max-instances=0 --region=us-central1

# Verificar que o site continua funcionando (servido por us-east1)
curl -I https://frontend.dominio.com

# Restaurar a região primária
gcloud run services update frontend-primary --max-instances=3 --region=us-central1
```

---

## 5. Como Funciona o Proxy Reverso

### O que é o Proxy Reverso

O **Google Cloud HTTPS Load Balancer** atua como proxy reverso. Ele é o **único ponto de entrada** da internet para a aplicação.

### Fluxo de uma Requisição

```
Usuário → DNS → Load Balancer (Proxy Reverso) → Cloud Run
```

1. **Usuário** digita `https://frontend.dominio.com` no browser
2. **DNS** resolve o domínio para o IP do Load Balancer
3. **Load Balancer** (Proxy Reverso):
   - Recebe a requisição HTTPS na porta 443
   - Faz a terminação TLS (descriptografa o HTTPS)
   - Identifica para qual backend enviar (frontend ou API)
   - Encaminha a requisição via HTTP interno para o Cloud Run
4. **Cloud Run** processa e retorna a resposta ao LB
5. **Load Balancer** criptografa a resposta e devolve ao usuário via HTTPS

### Por que usar Proxy Reverso

- **Segurança**: O Cloud Run nunca é acessado diretamente pela internet
- **SSL/TLS centralizado**: Certificados gerenciados em um único ponto
- **Balanceamento**: Distribui carga entre múltiplas instâncias/regiões
- **Simplicidade**: O Cloud Run não precisa lidar com certificados SSL

---

## 6. Como o Domínio Foi Configurado

### Opção A: Subdomínio do Professor

1. Criamos os **Load Balancers** no GCP e obtemos os **IPs públicos estáticos**
2. Informamos ao professor Laércio:
   - Nome do grupo
   - Subdomínio desejado (ex: `frontend-grupo.dominio.com` e `api-grupo.dominio.com`)
   - IPs públicos dos Load Balancers
3. O professor configura os registros DNS:
   - `frontend-grupo.dominio.com` → **A** → `[IP do LB Frontend]`
   - `api-grupo.dominio.com` → **A** → `[IP do LB Backend]`
4. Os certificados SSL são provisionados automaticamente pelo Google após a configuração DNS

### Fluxo DNS

```
frontend-grupo.dominio.com
    → Registro A no DNS
    → IP: 34.xxx.xxx.xxx (Load Balancer Frontend)
    → Load Balancer encaminha para Cloud Run Frontend

api-grupo.dominio.com
    → Registro A no DNS
    → IP: 34.yyy.yyy.yyy (Load Balancer Backend)
    → Load Balancer encaminha para Cloud Run Backend
```

---

## 7. Acessos Permitidos e Bloqueados

### ✅ Acessos Permitidos

| # | Fluxo | Porta | Protocolo | Responsável |
|---|---|---|---|---|
| 1 | Usuário → LB Frontend | 443 | HTTPS | Load Balancer |
| 2 | LB Frontend → Cloud Run FE | 8080 | HTTP interno | NEG/LB |
| 3 | Frontend JS → LB Backend | 443 | HTTPS | Load Balancer |
| 4 | LB Backend → Cloud Run BE | 5000 | HTTP interno | NEG/LB |
| 5 | Cloud Run BE → MongoDB Atlas | 27017 | TLS | Driver MongoDB |

### ❌ Acessos Bloqueados

| # | Fluxo | Mecanismo de Bloqueio |
|---|---|---|
| 1 | Internet → Cloud Run FE (URL direta) | Ingress: `internal-and-cloud-load-balancing` |
| 2 | Internet → Cloud Run BE (URL direta) | Ingress: `internal-and-cloud-load-balancing` |
| 3 | Internet → MongoDB Atlas | IP Allowlist (apenas IPs do Cloud Run) |
| 4 | Frontend → MongoDB Atlas | Sem driver + IP não autorizado |
| 5 | Qualquer → LB em portas não-HTTPS | Forwarding rules apenas em 80 (redirect) e 443 |
