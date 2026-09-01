# Guia de Deploy — Passo a Passo com gcloud CLI

Este guia mostra como fazer o deploy completo da aplicação usando comandos `gcloud`.
Também pode ser seguido pelo Console do GCP (console.cloud.google.com).

---

## Pré-requisitos

1. **Conta GCP** com billing ativo
2. **gcloud CLI** instalado: https://cloud.google.com/sdk/docs/install
3. **Docker** instalado: https://docs.docker.com/get-docker/
4. **Conta MongoDB Atlas**: https://www.mongodb.com/cloud/atlas/register

---

## Etapa 0: Configuração Inicial

```bash
# Autenticar no GCP
gcloud auth login

# Criar um projeto (ou usar existente)
gcloud projects create meu-todo-app-2026 --name="Todo App"
gcloud config set project meu-todo-app-2026

# Habilitar billing (necessário pelo Console: console.cloud.google.com → Billing)

# Habilitar APIs necessárias
gcloud services enable run.googleapis.com
gcloud services enable compute.googleapis.com
gcloud services enable artifactregistry.googleapis.com

# Definir variáveis de ambiente para facilitar
export PROJECT_ID=$(gcloud config get-value project)
export REGION_PRIMARY=us-central1
export REGION_SECONDARY=us-east1
```

---

## Etapa 1: Configurar MongoDB Atlas

### 1.1 Criar Cluster Free Tier

1. Acesse https://cloud.mongodb.com
2. Crie uma conta ou faça login
3. Clique em **"Build a Database"**
4. Selecione **"M0 (Free)"**
5. Escolha a região **"GCP"** → **"Iowa (us-central1)"**
6. Clique em **"Create Deployment"**

### 1.2 Criar Usuário do Banco

1. Em **"Database Access"** → **"Add New Database User"**
2. Authentication: **Password**
3. Username: `todouser`
4. Password: (anote a senha, será usada na connection string)
5. Database User Privileges: **"Read and write to any database"**
6. Clique em **"Add User"**

### 1.3 Configurar IP Allowlist (será atualizado depois)

1. Em **"Network Access"** → **"Add IP Address"**
2. Por enquanto, adicione **"Allow Access from Anywhere" (0.0.0.0/0)** para testes iniciais
3. **IMPORTANTE**: Após o deploy, restringir aos IPs do Cloud Run (Etapa 6)

### 1.4 Obter Connection String

1. Em **"Database"** → **"Connect"** → **"Drivers"**
2. Copie a connection string:
   ```
   mongodb+srv://todouser:<password>@cluster0.xxxxx.mongodb.net/todo-app?retryWrites=true&w=majority
   ```
3. Substitua `<password>` pela senha criada

### 1.5 Inserir Dados Iniciais

1. Em **"Database"** → **"Browse Collections"** → **"Add My Own Data"**
2. Database: `todo-app`, Collection: `todos`
3. Insira um documento de teste:
   ```json
   {"text": "Estudar Cloud", "completed": false}
   ```

---

## Etapa 2: Criar Repositório de Imagens (Artifact Registry)

```bash
# Criar repositório Docker
gcloud artifacts repositories create todo-app \
  --repository-format=docker \
  --location=$REGION_PRIMARY \
  --description="Imagens Docker do Todo App"

# Configurar autenticação Docker para o Artifact Registry
gcloud auth configure-docker ${REGION_PRIMARY}-docker.pkg.dev
```

---

## Etapa 3: Build e Push das Imagens Docker

```bash
# Navegar até a raiz do projeto
cd /caminho/para/aula-uniamerica-infraestrutura-cloud

# =============================================
# FRONTEND — Build com a URL da API
# =============================================
# ATENÇÃO: Substitua "api-seugrupo.dominio.com" pelo seu domínio real

docker build \
  --build-arg REACT_APP_API_URL=https://api-seugrupo.dominio.com \
  -t ${REGION_PRIMARY}-docker.pkg.dev/${PROJECT_ID}/todo-app/frontend:latest \
  ./frontend

# Push para o Artifact Registry
docker push ${REGION_PRIMARY}-docker.pkg.dev/${PROJECT_ID}/todo-app/frontend:latest

# =============================================
# BACKEND — Build simples
# =============================================
docker build \
  -t ${REGION_PRIMARY}-docker.pkg.dev/${PROJECT_ID}/todo-app/backend:latest \
  ./backend

# Push para o Artifact Registry
docker push ${REGION_PRIMARY}-docker.pkg.dev/${PROJECT_ID}/todo-app/backend:latest
```

---

## Etapa 4: Deploy no Cloud Run

### 4.1 Deploy do Front-end — Região Primária (us-central1)

```bash
gcloud run deploy frontend-primary \
  --image=${REGION_PRIMARY}-docker.pkg.dev/${PROJECT_ID}/todo-app/frontend:latest \
  --region=$REGION_PRIMARY \
  --platform=managed \
  --port=8080 \
  --memory=256Mi \
  --cpu=1 \
  --min-instances=0 \
  --max-instances=3 \
  --ingress=internal-and-cloud-load-balancing \
  --allow-unauthenticated
```

### 4.2 Deploy do Front-end — Região Secundária (us-east1)

```bash
gcloud run deploy frontend-secondary \
  --image=${REGION_PRIMARY}-docker.pkg.dev/${PROJECT_ID}/todo-app/frontend:latest \
  --region=$REGION_SECONDARY \
  --platform=managed \
  --port=8080 \
  --memory=256Mi \
  --cpu=1 \
  --min-instances=0 \
  --max-instances=3 \
  --ingress=internal-and-cloud-load-balancing \
  --allow-unauthenticated
```

### 4.3 Deploy do Back-end

```bash
# ATENÇÃO: Substitua a MONGODB_URI pela sua connection string real
# ATENÇÃO: Substitua o CORS_ORIGIN pelo domínio do seu frontend

gcloud run deploy backend \
  --image=${REGION_PRIMARY}-docker.pkg.dev/${PROJECT_ID}/todo-app/backend:latest \
  --region=$REGION_PRIMARY \
  --platform=managed \
  --port=5000 \
  --memory=512Mi \
  --cpu=1 \
  --min-instances=0 \
  --max-instances=5 \
  --ingress=internal-and-cloud-load-balancing \
  --allow-unauthenticated \
  --set-env-vars="MONGODB_URI=mongodb+srv://todouser:SENHA@cluster0.xxxxx.mongodb.net/todo-app?retryWrites=true&w=majority" \
  --set-env-vars="CORS_ORIGIN=https://frontend-seugrupo.dominio.com" \
  --set-env-vars="PORT=5000"
```

---

## Etapa 5: Configurar Load Balancer (Proxy Reverso)

### 5.1 Reservar IPs Estáticos

```bash
# IP para o Frontend
gcloud compute addresses create frontend-lb-ip --global

# IP para o Backend
gcloud compute addresses create backend-lb-ip --global

# Visualizar os IPs (anotar para informar ao professor)
gcloud compute addresses list --global
```

### 5.2 Criar Serverless NEGs (Network Endpoint Groups)

```bash
# NEG do Frontend Primário
gcloud compute network-endpoint-groups create frontend-primary-neg \
  --region=$REGION_PRIMARY \
  --network-endpoint-type=serverless \
  --cloud-run-service=frontend-primary

# NEG do Frontend Secundário
gcloud compute network-endpoint-groups create frontend-secondary-neg \
  --region=$REGION_SECONDARY \
  --network-endpoint-type=serverless \
  --cloud-run-service=frontend-secondary

# NEG do Backend
gcloud compute network-endpoint-groups create backend-neg \
  --region=$REGION_PRIMARY \
  --network-endpoint-type=serverless \
  --cloud-run-service=backend
```

### 5.3 Criar Backend Services do LB

```bash
# Backend Service do Frontend (com os 2 NEGs)
gcloud compute backend-services create frontend-backend-service \
  --global \
  --load-balancing-scheme=EXTERNAL_MANAGED

gcloud compute backend-services add-backend frontend-backend-service \
  --global \
  --network-endpoint-group=frontend-primary-neg \
  --network-endpoint-group-region=$REGION_PRIMARY

gcloud compute backend-services add-backend frontend-backend-service \
  --global \
  --network-endpoint-group=frontend-secondary-neg \
  --network-endpoint-group-region=$REGION_SECONDARY

# Backend Service do Backend (1 NEG)
gcloud compute backend-services create backend-backend-service \
  --global \
  --load-balancing-scheme=EXTERNAL_MANAGED

gcloud compute backend-services add-backend backend-backend-service \
  --global \
  --network-endpoint-group=backend-neg \
  --network-endpoint-group-region=$REGION_PRIMARY
```

### 5.4 Criar URL Maps

```bash
# URL Map do Frontend
gcloud compute url-maps create frontend-url-map \
  --default-service=frontend-backend-service

# URL Map do Backend
gcloud compute url-maps create backend-url-map \
  --default-service=backend-backend-service
```

### 5.5 Criar Certificados SSL

```bash
# Certificado SSL do Frontend
gcloud compute ssl-certificates create frontend-ssl-cert \
  --domains=frontend-seugrupo.dominio.com \
  --global

# Certificado SSL do Backend
gcloud compute ssl-certificates create backend-ssl-cert \
  --domains=api-seugrupo.dominio.com \
  --global
```

> **NOTA**: Os certificados só serão provisionados após a configuração do DNS (Etapa 7).
> Pode levar até 60 minutos para ficar ativo.

### 5.6 Criar HTTPS Proxies

```bash
# HTTPS Proxy do Frontend
gcloud compute target-https-proxies create frontend-https-proxy \
  --url-map=frontend-url-map \
  --ssl-certificates=frontend-ssl-cert

# HTTPS Proxy do Backend
gcloud compute target-https-proxies create backend-https-proxy \
  --url-map=backend-url-map \
  --ssl-certificates=backend-ssl-cert
```

### 5.7 Criar Forwarding Rules (HTTPS :443)

```bash
# Obter IPs
FRONTEND_IP=$(gcloud compute addresses describe frontend-lb-ip --global --format='value(address)')
BACKEND_IP=$(gcloud compute addresses describe backend-lb-ip --global --format='value(address)')

# Forwarding Rule HTTPS do Frontend
gcloud compute forwarding-rules create frontend-https-rule \
  --global \
  --target-https-proxy=frontend-https-proxy \
  --address=$FRONTEND_IP \
  --ports=443 \
  --load-balancing-scheme=EXTERNAL_MANAGED

# Forwarding Rule HTTPS do Backend
gcloud compute forwarding-rules create backend-https-rule \
  --global \
  --target-https-proxy=backend-https-proxy \
  --address=$BACKEND_IP \
  --ports=443 \
  --load-balancing-scheme=EXTERNAL_MANAGED
```

### 5.8 Criar Redirecionamento HTTP → HTTPS

```bash
# URL Map de redirecionamento (Frontend)
gcloud compute url-maps import frontend-http-redirect \
  --source=- <<EOF
name: frontend-http-redirect
defaultUrlRedirect:
  httpsRedirect: true
  redirectResponseCode: MOVED_PERMANENTLY_DEFAULT
EOF

gcloud compute target-http-proxies create frontend-http-proxy \
  --url-map=frontend-http-redirect

gcloud compute forwarding-rules create frontend-http-redirect-rule \
  --global \
  --target-http-proxy=frontend-http-proxy \
  --address=$FRONTEND_IP \
  --ports=80 \
  --load-balancing-scheme=EXTERNAL_MANAGED

# URL Map de redirecionamento (Backend)
gcloud compute url-maps import backend-http-redirect \
  --source=- <<EOF
name: backend-http-redirect
defaultUrlRedirect:
  httpsRedirect: true
  redirectResponseCode: MOVED_PERMANENTLY_DEFAULT
EOF

gcloud compute target-http-proxies create backend-http-proxy \
  --url-map=backend-http-redirect

gcloud compute forwarding-rules create backend-http-redirect-rule \
  --global \
  --target-http-proxy=backend-http-proxy \
  --address=$BACKEND_IP \
  --ports=80 \
  --load-balancing-scheme=EXTERNAL_MANAGED
```

---

## Etapa 6: Restringir MongoDB Atlas (IP Allowlist)

Após o deploy do Cloud Run, precisamos obter os IPs de saída e restringir o MongoDB Atlas.

> **NOTA**: Cloud Run usa IPs de saída compartilhados por padrão. Para IPs fixos,
> configure um VPC Connector + Cloud NAT. Para a atividade, pode-se usar uma
> abordagem mais simples:

### Opção Simples (para a atividade)

1. No MongoDB Atlas, vá em **"Network Access"**
2. Remova **0.0.0.0/0** (se adicionou antes)
3. Adicione os ranges de IP do Google Cloud Run:
   - Consulte: https://www.gstatic.com/ipranges/cloud.json
   - Ou mantenha `0.0.0.0/0` mas explique no diagrama que em produção restringiria com Cloud NAT

### Opção Avançada (Cloud NAT para IPs fixos)

```bash
# Criar VPC Connector
gcloud compute networks vpc-access connectors create todo-connector \
  --region=$REGION_PRIMARY \
  --range=10.8.0.0/28

# Atualizar o Cloud Run Backend para usar o VPC Connector
gcloud run services update backend \
  --region=$REGION_PRIMARY \
  --vpc-connector=todo-connector \
  --vpc-egress=all-traffic

# Criar Cloud Router e Cloud NAT
gcloud compute routers create todo-router \
  --network=default \
  --region=$REGION_PRIMARY

gcloud compute routers nats create todo-nat \
  --router=todo-router \
  --region=$REGION_PRIMARY \
  --auto-allocate-nat-external-ips \
  --nat-all-subnet-ip-ranges

# Obter o IP NAT e adicionar ao MongoDB Atlas
gcloud compute routers nats describe todo-nat --router=todo-router --region=$REGION_PRIMARY
```

---

## Etapa 7: Configurar DNS

### Solicitar ao Professor

Envie um e-mail/mensagem ao professor Laércio com:

```
Professor Laércio,

Segue a solicitação de subdomínios para a atividade:

Grupo: [NOME DO GRUPO]

1. Subdomínio: frontend-seugrupo.dominio.com
   IP Público: [IP do output do comando: gcloud compute addresses describe frontend-lb-ip --global]
   Serviço: Front-end da aplicação Todo List

2. Subdomínio: api-seugrupo.dominio.com
   IP Público: [IP do output do comando: gcloud compute addresses describe backend-lb-ip --global]
   Serviço: API Back-end da aplicação Todo List

Obrigado!
```

### Verificar DNS (após configuração pelo professor)

```bash
# Verificar resolução DNS
nslookup frontend-seugrupo.dominio.com
nslookup api-seugrupo.dominio.com

# Verificar certificado SSL (pode levar até 60 min)
gcloud compute ssl-certificates describe frontend-ssl-cert --global
gcloud compute ssl-certificates describe backend-ssl-cert --global
```

---

## Etapa 8: Testar

Após DNS e SSL estarem ativos, execute os testes do arquivo `plano-testes.md`.

```bash
# Teste rápido
curl -I https://frontend-seugrupo.dominio.com
curl https://api-seugrupo.dominio.com/todos
```

---

## Alternativa: Deploy via Terraform

Se preferir usar Terraform ao invés dos comandos manuais:

```bash
cd infra

# Copiar e preencher variáveis
cp terraform.tfvars.example terraform.tfvars
# Editar terraform.tfvars com seus valores

# Inicializar Terraform
terraform init

# Visualizar o que será criado
terraform plan

# Aplicar (criar tudo)
terraform apply

# Ver outputs (IPs dos Load Balancers)
terraform output
```

---

## Comandos Úteis

```bash
# Ver logs do Cloud Run
gcloud run services logs read frontend-primary --region=$REGION_PRIMARY --limit=50
gcloud run services logs read backend --region=$REGION_PRIMARY --limit=50

# Ver status dos serviços
gcloud run services list

# Ver IPs do Load Balancer
gcloud compute addresses list --global

# Ver status dos certificados SSL
gcloud compute ssl-certificates list

# Deletar tudo (quando terminar)
# CUIDADO: isso remove toda a infraestrutura
terraform destroy
# OU manualmente via console
```
