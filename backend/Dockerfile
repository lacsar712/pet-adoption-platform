FROM docker.m.daocloud.io/library/node:20-slim

WORKDIR /app

COPY package*.json ./
RUN npm config set registry https://registry.npmmirror.com && npm ci --omit=dev

COPY . .

RUN mkdir -p /app/uploads

EXPOSE 8731

CMD ["node", "src/server.js"]
