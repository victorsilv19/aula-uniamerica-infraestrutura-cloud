# Documentação da Infraestrutura Cloud

## 1. Serviços de Nuvem Utilizados e Justificativas

A infraestrutura foi construída inteiramente utilizando serviços gerenciados e serverless no **Google Cloud Platform (GCP)** e **MongoDB Atlas**. A escolha por essas soluções foi pautada nos requisitos de alta disponibilidade, escalabilidade sob demanda e abstração da administração de servidores.

*   **Google Cloud Run (Front-end e Back-end):** Plataforma serverless altamente escalável. Foi escolhido por permitir a execução de contêineres sem necessidade de provisionar ou gerenciar infraestrutura, suportando auto-scaling de zero a N instâncias e simplificando muito os deploys (tanto do React quanto da API Node.js).
*   **Google Cloud Load Balancer (Proxy Reverso):** Serviço global de balanceamento de carga de Nível 7. Foi escolhido por fornecer IP estático global, terminação de SSL/TLS (HTTPS) de forma gerenciada, além de suportar a integração com o Cloud Armor e fazer o roteamento inteligente baseado em domínios via URL Maps.
*   **Google Cloud Armor (Firewall/WAF):** Mecanismo de segurança de borda. Escolhido para proteger a aplicação logo no proxy reverso, permitindo criar políticas rigorosas para evitar tráfego malicioso e ataques DDoS antes mesmo da requisição chegar ao Cloud Run.
*   **Serverless Network Endpoint Groups (NEGs):** Componentes fundamentais que integram o Cloud Run diretamente ao Load Balancer, sem a necessidade de instâncias intermediárias.
*   **MongoDB Atlas:** Serviço serverless de banco de dados nativo para a nuvem. Escolhido para abrigar a base NoSQL fora do escopo de computação da GCP, mantendo-se gerenciado, isolado e altamente disponível.
*   **DuckDNS (Provedor de DNS externo):** Serviço de resolução de DNS para prover subdomínios gratuitos (`deploynasexta.duckdns.org` e `api-deploynasexta.duckdns.org`), apontando para o IP estático do proxy reverso.

---

## 2. Implementação de Segurança

A segurança foi implementada sob a premissa de *Zero Trust* e isolamento de rede:
*   **Cloud Run (Ingress Interno):** Os serviços de Front-end e Back-end foram configurados com a flag `--ingress=internal-and-cloud-load-balancing`. Isso significa que os links originais fornecidos pela Google (`*.run.app`) estão permanentemente bloqueados. É impossível acessar a computação pulando o proxy reverso.
*   **Segurança de Borda (Cloud Armor):** Uma política de segurança foi anexada aos *Backend Services* do Load Balancer, atuando como o único portão de entrada, validando as requisições HTTPS e barrando eventuais requisições diretas não autorizadas ou ataques volumétricos.
*   **Banco de Dados (Network Access):** O MongoDB Atlas possui firewall próprio (IP Access List) para proibir acesso público genérico. Na configuração final idealizada, ele aceita tráfego apenas do VPC Connector atrelado ao Back-end.

---

## 3. Redundância do Front-end

Para garantir alta disponibilidade, a aplicação Front-end foi *deployada* em **duas regiões distintas da GCP simultaneamente**: `us-central1` e `us-east1`.
Cada deploy gerou um Serverless NEG isolado. O Load Balancer Global engloba ambos os NEGs no mesmo *Backend Service*.
Quando um usuário acessa o domínio, o Load Balancer roteia automaticamente a requisição para a região saudável que estiver geograficamente mais próxima com menor latência. Se a região `us-central1` cair ou ficar indisponível, o tráfego é escoado instantaneamente para `us-east1`, garantindo que a aplicação continue online sem intervenção manual.

---

## 4. Funcionamento do Proxy Reverso

O **Google Cloud Load Balancer** atua como proxy reverso global recebendo todas as requisições da Internet. Ele funciona da seguinte maneira:
1.  **Recepção Segura:** Intercepta o tráfego na porta 443 usando o certificado SSL gerenciado pelo Google.
2.  **Validação (Cloud Armor):** A requisição passa pela verificação do Cloud Armor acoplado ao proxy.
3.  **Roteamento (URL Map):** O proxy reverso inspeciona o *Host header* do HTTP.
    *   Se a requisição for para `deploynasexta.duckdns.org`, ele encaminha para o Frontend (distribuindo entre as regiões redundantes).
    *   Se a requisição for para `api-deploynasexta.duckdns.org`, ele encaminha para o Backend (Cloud Run em `us-central1`).
Nenhuma requisição externa alcança os microsserviços do Cloud Run diretamente; o proxy atua como escudo e roteador.

---

## 5. Configuração do Domínio e DNS

*   Um **IP público estático e global** foi reservado na GCP e atrelado ao Forwarding Rule do Load Balancer.
*   Utilizando a plataforma **DuckDNS**, criamos dois registros do tipo `A`:
    *   `deploynasexta.duckdns.org` (Front-end) -> Apontando para o IP Estático.
    *   `api-deploynasexta.duckdns.org` (Back-end/API) -> Apontando para o mesmo IP Estático.
*   O Google Cloud Load Balancer identificou a titularidade do domínio ao tentar resolver o DNS e gerou automaticamente um **Certificado SSL/TLS Gerenciado** para os dois domínios, ativando a criptografia HTTPS.

---

## 6. Acessos Permitidos e Bloqueados

O isolamento garante que o tráfego só flua pelos caminhos desenhados no diagrama:

**✅ Fluxos Permitidos:**
*   `Internet (Usuários) -> DNS / Load Balancer (Proxy Reverso)`: Permitido exclusivamente via HTTPS (Porta 443).
*   `Load Balancer -> Front-end (Cloud Run)`: Permitido internamente pela GCP.
*   `Load Balancer -> Back-end API (Cloud Run)`: Permitido internamente pela GCP.
*   `Front-end (Navegador do Usuário) -> DNS / Load Balancer -> Back-end API`: O Front-end em React consome a API através da internet roteando pelo proxy reverso.
*   `Back-end (Cloud Run VPC Connector) -> Banco de Dados (MongoDB Atlas)`: Permitido na porta TCP 27017 (String de Conexão).

**🚫 Fluxos Bloqueados:**
*   `Internet -> Porta 80 (HTTP)`: Bloqueado/Redirecionado pelo proxy (é exigido HTTPS).
*   `Internet -> Acesso direto ao Front-end (.run.app)`: Bloqueado no nível de Ingress da nuvem (Error 404/403).
*   `Internet -> Acesso direto ao Back-end (.run.app)`: Bloqueado no nível de Ingress da nuvem (Error 404/403).
*   `Internet -> Banco de Dados (MongoDB)`: Bloqueado pelo Network Access do Atlas. Nenhuma consulta externa sem passar pela infraestrutura do Back-end tem permissão para extrair dados.

---

## 7. Observabilidade (Painéis e Logs)

Para garantir que o grupo conheça o comportamento da arquitetura e saiba identificar problemas, foi adotada a stack nativa **Google Cloud Operations (Cloud Logging e Cloud Monitoring)**. 

O backend Node.js foi adaptado para gerar logs estruturados (JSON) utilizando a biblioteca `pino-http`, contendo informações detalhadas (método, rota, status_code, duração). O tráfego de rede (Load Balancer) já possui integração nativa. Abaixo estão descritos os 4 painéis operacionais configurados:

### Painel 1: Disponibilidade do Frontend (Uptime Check)
*   **Nome e pergunta:** O Frontend está acessível pelo domínio configurado (deploynasexta.duckdns.org)?
*   **Motivo da escolha:** É essencial garantir que o domínio público esteja respondendo adequadamente para os usuários finais; se estiver fora, todo o serviço é impactado, justificando alerta imediato.
*   **Origem dos dados:** O Cloud Monitoring faz requisições sintéticas globais recorrentes (Uptime Checks) ao IP do Load Balancer gerenciado.
*   **Consulta e cálculo:** Utiliza-se a métrica nativa de *Uptime Check Results* (`monitoring.googleapis.com/uptime_check/check_passed`), medindo a porcentagem de sucessos (status HTTP 200).
*   **Recorte temporal:** Últimas 1 hora, agrupamento a cada 1 minuto (auto-refresh a cada 1 minuto), Fuso horário UTC-3.
*   **Forma de visualização:** Gráfico de linha temporal (Line Chart) e um "Scorecard" exibindo a disponibilidade atual (ex: 100%). Facilita bater o olho e ver se houve queda em algum minuto.
*   **Interpretação:** Uma linha constante em 1 (ou 100%) indica operação normal. Quedas para 0 indicam que os acessos estão falhando.
*   **Critérios de atenção:** Disponibilidade caindo abaixo de 99% em uma janela de 5 minutos requer intervenção.
*   **Ação decorrente:** Verificar se as duas instâncias do Cloud Run (us-central1 e us-east1) caíram, verificar status do DNS DuckDNS ou falhas na política do Load Balancer.
*   **Validação:** Ao desativar o roteamento do Load Balancer temporariamente, o painel registra falha. Ao normalizar, a linha retorna a 100%.

### Painel 2: Desempenho e Latência da API
*   **Nome e pergunta:** Quais rotas da API estão demorando mais para responder e sofrendo gargalos de lentidão?
*   **Motivo da escolha:** Requisições lentas impactam criticamente a experiência do usuário, podendo causar timeouts de página e abandono de carrinho.
*   **Origem dos dados:** O backend em Node.js emite logs estruturados JSON gerados pelo `pino`. O campo `jsonPayload.duration_ms` contém o tempo exato processado pelo backend.
*   **Consulta e cálculo:** Foi criada uma métrica baseada em log (Log-based Metric) que extrai o valor de `jsonPayload.duration_ms`. O painel calcula o percentil P95 (Aggregator: 95th percentile) agrupado pela *label* `jsonPayload.route`. 
*   **Recorte temporal:** Últimas 12 horas, alinhado a cada 5 minutos.
*   **Forma de visualização:** Gráfico de calor (Heatmap) ou Gráfico de linha multi-série por rota. Facilita observar se uma rota em específico se distanciou da latência média das demais.
*   **Interpretação:** Valores consistentes abaixo de 300ms indicam normalidade. Picos espordáticos em uma rota específica (`/todos` GET, por exemplo) indicam degradação.
*   **Critérios de atenção:** Latência sustentada (P95) acima de 1 segundo para a criação ou listagem de *Todos* demanda investigação.
*   **Ação decorrente:** Escalonar a capacidade (CPU/Memória) do Cloud Run Back-end, otimizar índices no MongoDB ou revisar o código da query.
*   **Validação:** Disparar requisições massivas para a API e observar se a latência P95 aumenta no painel (Refletido durante os testes de carga manual).

### Painel 3: Taxa de Erros e Falhas da API
*   **Nome e pergunta:** Quais falhas estão ocorrendo no servidor e qual parcela das requisições não está sendo concluída com sucesso?
*   **Motivo da escolha:** Monitorar erros HTTP 5xx é vital para descobrir se atualizações recentes quebraram o código ou se o banco de dados caiu.
*   **Origem dos dados:** Logs JSON gerados pelo `pino-http` no backend e coletados pelo Cloud Logging. O campo `jsonPayload.status_code` indica o resultado.
*   **Consulta e cálculo:** Utiliza-se a linguagem MQL (Monitoring Query Language) para contar o número de logs onde `jsonPayload.status_code >= 500` (Numerador) dividido pela contagem total de requisições `jsonPayload.event = "http_request"` (Denominador), agrupado por 5 minutos.
*   **Recorte temporal:** Janela deslizante das últimas 6 horas, agrupamento a cada 5 minutos.
*   **Forma de visualização:** Gráfico de barras (Bar Chart) empilhadas, ou indicador numérico vermelho, sendo a melhor opção visual para destacar falhas acima da base normal de acessos com sucesso.
*   **Interpretação:** Barras vazias ou com índice próximo a 0% são normais (funcionamento esperado). Crescimento de barras vermelhas aponta falha sistêmica. A ausência de dados significa ausência de acessos no período (e não ausência de erros per se).
*   **Critérios de atenção:** Taxa de erro superior a 5% por mais de 5 minutos aciona um alerta severo.
*   **Ação decorrente:** Consultar imediatamente os logs detalhados (Cloud Logging) para capturar o `error_message` emitido na falha (Ex: "Failed to connect to MongoDB") e atuar no problema pontual.
*   **Validação:** Foi criada uma rota especial no backend `/api/force-error` que emite um status 500 forçado para fins de teste. Ao invocar essa rota 10 vezes consecutivas, o painel acusa os 10 erros exatos.

### Painel 4: Volume de Utilização e Eventos de Negócio
*   **Nome e pergunta:** Qual o volume de requisições processado e quais funcionalidades (GET, POST, DELETE) são mais utilizadas?
*   **Motivo da escolha:** Entender os padrões de uso da aplicação permite planejar infraestrutura, horários de pico para manutenção e identificar funcionalidades abandonadas.
*   **Origem dos dados:** As requisições HTTP interceptadas nativamente pelo *Google Cloud HTTP/S Load Balancer*.
*   **Consulta e cálculo:** Consulta-se a métrica nativa de request count do *https_lb_rule* (`loadbalancing.googleapis.com/https/request_count`), calculando a taxa (`RATE`) de requisições/segundo e agrupando pelo método HTTP (GET, POST, etc).
*   **Recorte temporal:** Últimos 7 dias, agrupados por horas.
*   **Forma de visualização:** Gráfico de linha (Stacked Line Chart) ou Área para empilhar o volume de requisições de vários métodos ao longo do tempo.
*   **Interpretação:** Gráfico subindo e descendo indica os picos diários de uso da aplicação. Gráfico plano (zerado) indica falta de acesso ou Load Balancer indisponível/desconfigurado.
*   **Critérios de atenção:** Mudança repentina e absurda de volume em um curto espaço (Ex: aumento de 1000x no número de DELETE) indicaria suspeita de ataque cibernético explorando rotas; se cair vertiginosamente, significa que ninguém está conseguindo acessar o site via DNS.
*   **Ação decorrente:** Cruzar esses dados de volume com os dados do Cloud Armor para entender se picos de acessos representam ataques (DDoS) ou acessos legítimos que demandariam aumento no limite de auto-scaling.
*   **Validação:** Gerando tráfego orgânico no frontend da aplicação, criando e apagando 20 tarefas seguidas, é possível observar os correspondentes *Spikes* nas métricas de "POST" e "DELETE" no painel.
