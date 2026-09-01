# Etapa 1: Construção da aplicação
FROM node:18-alpine as build

# Definindo o diretório de trabalho dentro do container
WORKDIR /app

# Copiando o package.json e o package-lock.json para instalar as dependências
COPY package*.json ./

# Instalando as dependências do projeto
RUN npm install

# Copiando todo o conteúdo da pasta do projeto para o container
COPY . .

# Variável de ambiente para a URL da API do Back-end
# Em produção, definir via --build-arg REACT_APP_API_URL=https://api-seugrupo.dominio.com
ARG REACT_APP_API_URL=http://localhost:5000
ENV REACT_APP_API_URL=$REACT_APP_API_URL

# Construindo a aplicação para produção
RUN npm run build

# Etapa 2: Servindo a aplicação com Nginx
FROM nginx:alpine

# Configuração do Nginx para SPA (redireciona todas as rotas para index.html)
RUN echo 'server { \
    listen 80; \
    listen 8080; \
    server_name _; \
    root /usr/share/nginx/html; \
    index index.html; \
    location / { \
        try_files $uri $uri/ /index.html; \
    } \
}' > /etc/nginx/conf.d/default.conf

# Copiando o build da etapa anterior para o diretório padrão do Nginx
COPY --from=build /app/build /usr/share/nginx/html

# Cloud Run usa a porta definida em $PORT (padrão 8080)
EXPOSE 8080

# Comando para iniciar o Nginx e servir a aplicação
CMD ["nginx", "-g", "daemon off;"]

