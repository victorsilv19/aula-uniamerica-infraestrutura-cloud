# Plano de Testes — Infraestrutura Serverless GCP

Este documento contém os **7 testes obrigatórios** exigidos pela atividade, com comandos para execução e espaço para evidências (screenshots).

---

## Variáveis de Ambiente para os Testes

```bash
# Defina seus domínios aqui
export FRONTEND_URL="https://frontend-seugrupo.dominio.com"
export BACKEND_URL="https://api-seugrupo.dominio.com"

# URLs diretas do Cloud Run (obtidas no deploy)
export FRONTEND_DIRECT="https://frontend-primary-xxxxx-uc.a.run.app"
export BACKEND_DIRECT="https://backend-xxxxx-uc.a.run.app"
```

---

## Teste 1: Acesso ao Front-end via Domínio

**Objetivo**: Comprovar que o front-end é acessível pelo domínio configurado.

### Comando
```bash
# Via curl
curl -I $FRONTEND_URL

# Resultado esperado:
# HTTP/2 200
# content-type: text/html
# (certificado SSL válido)
```

### Verificação no Browser
1. Abrir o browser
2. Navegar para `https://frontend-seugrupo.dominio.com`
3. A página "Lista de Tarefas" deve carregar
4. Verificar o cadeado SSL (HTTPS) na barra de endereço

### Evidência
> 📸 **Screenshot**: Captura da tela do browser mostrando:
> - URL com o domínio
> - Cadeado SSL
> - Página carregada

---

## Teste 2: Acesso ao Back-end via Domínio/API

**Objetivo**: Comprovar que a API do back-end é acessível pelo domínio.

### Comando
```bash
# Listar tarefas (GET)
curl -s $BACKEND_URL/todos | python -m json.tool

# Health check
curl -s $BACKEND_URL/health

# Resultado esperado:
# [{"_id": "...", "text": "Estudar Cloud", "completed": false}, ...]
# {"status": "ok"}
```

### Evidência
> 📸 **Screenshot**: Captura do terminal mostrando:
> - Comando curl com o domínio da API
> - Resposta JSON com as tarefas

---

## Teste 3: Front-end Acessando o Back-end

**Objetivo**: Comprovar que o front-end consegue se comunicar com o back-end.

### Passos
1. Abrir `https://frontend-seugrupo.dominio.com` no browser
2. No campo de texto, digitar "Tarefa de Teste"
3. Clicar em "Adicionar"
4. A tarefa deve aparecer na lista abaixo

### Verificação Adicional (DevTools)
1. Abrir DevTools do browser (F12)
2. Ir na aba **"Network"**
3. Recarregar a página
4. Verificar que as requisições para `api-seugrupo.dominio.com/todos` retornam **200 OK**

### Evidência
> 📸 **Screenshot 1**: Página com a tarefa adicionada
> 📸 **Screenshot 2**: DevTools mostrando a requisição para a API com status 200

---

## Teste 4: Back-end Acessando o Banco de Dados

**Objetivo**: Comprovar que o back-end consegue ler e gravar no MongoDB Atlas.

### Comando
```bash
# Criar uma tarefa via API
curl -X POST $BACKEND_URL/todos \
  -H "Content-Type: application/json" \
  -d '{"text": "Teste de conexão com banco"}'

# Resultado esperado:
# {"_id": "...", "text": "Teste de conexão com banco", "completed": false, ...}

# Listar tarefas (deve incluir a nova tarefa)
curl -s $BACKEND_URL/todos | python -m json.tool
```

### Verificação nos Logs do Cloud Run
```bash
# Ver logs do backend para confirmar "Conectado ao MongoDB"
gcloud run services logs read backend --region=us-central1 --limit=20
```

### Evidência
> 📸 **Screenshot 1**: Resposta do POST com a tarefa criada
> 📸 **Screenshot 2**: Logs do Cloud Run mostrando "Conectado ao MongoDB"
> 📸 **Screenshot 3**: MongoDB Atlas → Browse Collections mostrando os dados

---

## Teste 5: Acesso Direto ao Back-end BLOQUEADO

**Objetivo**: Comprovar que o back-end não é acessível diretamente pela internet (sem passar pelo Load Balancer).

### Comando
```bash
# Tentar acessar diretamente a URL do Cloud Run Backend
curl -I $BACKEND_DIRECT/todos

# Resultado esperado:
# HTTP/2 403 Forbidden
# OU
# curl: (7) Failed to connect
```

### Explicação
O Cloud Run Backend está configurado com `ingress: internal-and-cloud-load-balancing`, o que significa que apenas o Load Balancer pode acessá-lo. Qualquer tentativa de acesso direto pela URL `.run.app` será bloqueada com **403 Forbidden**.

### Evidência
> 📸 **Screenshot**: Captura do terminal mostrando:
> - Comando curl com a URL direta do Cloud Run
> - Resposta 403 Forbidden

---

## Teste 6: Acesso Direto ao Banco de Dados BLOQUEADO

**Objetivo**: Comprovar que o MongoDB Atlas não é acessível diretamente pela internet.

### Comando
```bash
# Tentar conectar diretamente ao MongoDB Atlas de fora do Cloud Run
# (do seu computador local)
mongosh "mongodb+srv://cluster0.xxxxx.mongodb.net/todo-app" --username todouser

# Resultado esperado:
# MongoServerSelectionError: connection timed out
# OU
# MongoNetworkError: getaddrinfo ENOTFOUND
```

### Alternativa sem mongosh
```bash
# Tentar conectar via telnet/nc na porta 27017
nc -zv cluster0.xxxxx.mongodb.net 27017

# Resultado esperado:
# Connection timed out / Connection refused
```

### Explicação
O MongoDB Atlas está configurado com **IP Allowlist** que permite apenas os IPs de saída do Cloud Run. Qualquer outro IP (como o do seu computador) é automaticamente bloqueado.

### Evidência
> 📸 **Screenshot**: Captura do terminal mostrando:
> - Tentativa de conexão direta ao MongoDB
> - Erro de timeout ou conexão recusada

---

## Teste 7: Redundância — Front-end Disponível com Falha em uma Região

**Objetivo**: Comprovar que o front-end continua funcionando quando um dos componentes redundantes é desabilitado.

### Passos

#### 7.1 Verificar funcionamento normal
```bash
# Confirmar que o frontend está funcionando
curl -I $FRONTEND_URL
# Resultado: HTTP/2 200
```

#### 7.2 Simular falha na região primária
```bash
# Desabilitar o frontend na região primária (escalar para 0)
gcloud run services update frontend-primary \
  --max-instances=0 \
  --region=us-central1

# Aguardar ~30 segundos para o Load Balancer detectar
sleep 30
```

#### 7.3 Verificar que continua funcionando (via região secundária)
```bash
# O frontend deve continuar acessível (servido por us-east1)
curl -I $FRONTEND_URL
# Resultado: HTTP/2 200

# Testar no browser também
# Abrir https://frontend-seugrupo.dominio.com → Deve carregar normalmente
```

#### 7.4 Restaurar a região primária
```bash
# Restaurar o frontend na região primária
gcloud run services update frontend-primary \
  --max-instances=3 \
  --region=us-central1
```

### Evidência
> 📸 **Screenshot 1**: Acesso funcionando ANTES da simulação de falha
> 📸 **Screenshot 2**: Comando desabilitando a região primária
> 📸 **Screenshot 3**: Acesso funcionando DEPOIS da simulação (com uma região desabilitada)
> 📸 **Screenshot 4**: Comando restaurando a região primária

---

## Resumo dos Testes

| # | Teste | Resultado Esperado | Status |
|---|---|---|---|
| 1 | Acesso ao Frontend via domínio | HTTP 200 + HTTPS | ⬜ |
| 2 | Acesso ao Backend via domínio/API | JSON com tarefas | ⬜ |
| 3 | Frontend → Backend (criar tarefa) | Tarefa aparece na lista | ⬜ |
| 4 | Backend → MongoDB (ler/gravar) | Dados persistidos | ⬜ |
| 5 | Acesso direto ao Backend bloqueado | 403 Forbidden | ⬜ |
| 6 | Acesso direto ao MongoDB bloqueado | Connection timeout | ⬜ |
| 7 | Redundância (falha em uma região) | Site continua funcionando | ⬜ |

> **Legenda**: ⬜ Não testado | ✅ Passou | ❌ Falhou
