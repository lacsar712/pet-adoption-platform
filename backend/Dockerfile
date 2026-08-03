FROM docker.m.daocloud.io/library/node:20-slim

WORKDIR /app

ARG NPM_REGISTRY=https://registry.npmmirror.com

COPY package*.json ./
RUN npm config set registry "${NPM_REGISTRY}" && npm ci --omit=dev

COPY . .

RUN mkdir -p /app/uploads

EXPOSE 8731

CMD ["node", "src/server.js"]
