FROM node:20-alpine

WORKDIR /app

RUN apk add --no-cache python3 make g++ curl

COPY package.json package-lock.json* ./
RUN npm install --production || npm install --production --ignore-scripts

COPY src ./src

ENV PROXY_PORT=3000
EXPOSE 3000

CMD ["npm", "start"]
