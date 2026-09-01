# Etapa 1: Construção da aplicação
FROM node:18-alpine

# Definindo o diretório de trabalho dentro do container
WORKDIR /app

# Copiando o package.json e o package-lock.json para instalar as dependências
COPY package*.json ./

# Instalando as dependências do projeto
RUN npm install

# Copiando o restante do conteúdo do projeto para o container
COPY . .

# Cloud Run define a porta via variável de ambiente PORT
# Valor padrão 5000 para desenvolvimento local
ENV PORT=5000
EXPOSE 5000

# Comando para rodar a aplicação
CMD ["node", "index.js"]

