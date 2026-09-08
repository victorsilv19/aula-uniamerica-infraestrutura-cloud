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
