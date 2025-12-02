import Fastify from 'fastify';
import { request as undiciRequest } from 'undici';
import Database from 'better-sqlite3';
import { v4 as uuidv4 } from 'uuid';
import fs from 'fs';
import path from 'path';
import {
  WebhookErrorPayloadSchema,
  WebhookEventTypeSchema,
  WebhookStatusSchema,
  WebhookSuccessPayloadSchema,
} from './server.schemas.js';
import {
  CREATE_REQUESTS_TABLE,
  CREATE_RESPONSES_TABLE,
  ENCODING,
  INSERT_REQUEST_QUERY,
  INSERT_RESPONSE_QUERY,
  LMSTUDIO_HOST,
  LMSTUDIO_PORT,
  LMSTUDIO_PROXY_SQLITE_CACHE,
  LMSTUDIO_PROXY_REQUEST_TIMEOUT,
  LMSTUDIO_SQLITE_ENCRYPTION_KEY,
  LMSTUDIO_PROXY_SQLITE_PATH,
  PROXY_PORT,
  SELECT_LATEST_SUCCESS_RESPONSE_BY_EXTERNAL_ID,
} from './server.const.js';
import { callWebhook } from './server.utils.js';
import { EncryptionService } from './services/encryption.service.js';
import { SigningService } from './services/signing.service.js';

const encryptionService = new EncryptionService(LMSTUDIO_SQLITE_ENCRYPTION_KEY);
const signingService = new SigningService();

const db = (function dbInitialization() {
  fs.mkdirSync(path.dirname(LMSTUDIO_PROXY_SQLITE_PATH), { recursive: true });
  const db = new Database(LMSTUDIO_PROXY_SQLITE_PATH);

  db.exec(`
        ${CREATE_REQUESTS_TABLE}
        ${CREATE_RESPONSES_TABLE}
    `);

  const insertRequest = db.prepare(INSERT_REQUEST_QUERY);
  const insertResponse = db.prepare(INSERT_RESPONSE_QUERY);
  const selectLatestByExternalId = db.prepare(SELECT_LATEST_SUCCESS_RESPONSE_BY_EXTERNAL_ID);

  return {
    insertRequest,
    insertResponse,
    selectLatestByExternalId,
  };
})();

const fastify = Fastify({
  logger: LMSTUDIO_PROXY_SQLITE_CACHE,
});

fastify.all('/v1/*', async (request, reply) => {
  const targetUrl = `http://${LMSTUDIO_HOST}:${LMSTUDIO_PORT}${request.raw.url}`;
  const isChatCompletion =
    request.method === 'POST' && request.raw.url.startsWith('/v1/chat/completions');

  let body;

  if (request.method === 'POST' || request.method === 'PUT' || request.method === 'PATCH') {
    body = request.body;
  }

  const requestId = uuidv4();
  const externalId = body?.id;

  if (externalId) {
    try {
      const cached = db.selectLatestByExternalId.get(externalId, WebhookStatusSchema.enum.success);

      if (cached && cached.response_body) {
        const decryptedBody = encryptionService.decrypt(cached.response_body);
        reply.code(cached.status_code || 200);
        reply.header('content-type', 'application/json');
        reply.send(decryptedBody);

        try {
          const parsedResponse = (() => {
            try {
              return JSON.parse(decryptedBody);
            } catch {
              return { raw: decryptedBody };
            }
          })();
          const payload = WebhookSuccessPayloadSchema.parse({
            id: externalId,
            status: WebhookStatusSchema.enum.success,
            request: body || null,
            response: parsedResponse,
            timestamp: new Date().toISOString(),
          });
          await callWebhook(fastify, payload, WebhookEventTypeSchema.enum.success);
        } catch (error) {
          fastify.log.error({ error }, 'Failed to call success webhook (cache hit)');
        }

        return;
      }
    } catch (error) {
      fastify.log.error({ error }, 'Failed to read cached response by external_id');
    }
  }

  if (LMSTUDIO_PROXY_SQLITE_CACHE) {
    try {
      const requestBodyText = JSON.stringify(body || {});
      const encryptedRequestBody = encryptionService.encrypt(requestBodyText);
      db.insertRequest.run(requestId, externalId, request.raw.url, encryptedRequestBody);
    } catch (error) {
      fastify.log.error({ error }, 'Failed to insert request in DB');
    }
  }

  const isStream = body && body.stream === true;

  try {
    const upstreamHeaders = {
      ...request.headers,
      host: `${LMSTUDIO_HOST}:${LMSTUDIO_PORT}`,
    };
    const upstream = await undiciRequest(targetUrl, {
      method: request.method,
      body: body ? JSON.stringify(body) : undefined,
      headers: upstreamHeaders,
      headersTimeout: LMSTUDIO_PROXY_REQUEST_TIMEOUT,
      bodyTimeout: LMSTUDIO_PROXY_REQUEST_TIMEOUT,
      reset: true,
    });

    if (!isChatCompletion) {
      reply.code(upstream.statusCode);

      const chunks = [];
      for await (const chunk of upstream.body) {
        chunks.push(chunk);
      }
      const bodyBuffer = Buffer.concat(chunks);
      const ct = upstream.headers['content-type'];

      if (ct) {
        reply.header('content-type', ct);
      }

      try {
        const responseTextForSignature = bodyBuffer.toString();
        const signature = await signingService.createHmac(responseTextForSignature);
        if (signature) {
          reply.header('x-response-signature', signature);
        }
      } catch {}

      if (LMSTUDIO_PROXY_SQLITE_CACHE) {
        try {
          const responseId = uuidv4();
          const responseText = bodyBuffer.toString();
          const encryptedResponseBody = encryptionService.encrypt(responseText);

          db.insertResponse.run(
            responseId,
            requestId,
            externalId,
            WebhookStatusSchema.enum.success,
            upstream.statusCode,
            encryptedResponseBody,
          );
        } catch (error) {
          fastify.log.error({ error }, 'Failed to insert non-chat response');
        }
      }

      reply.send(bodyBuffer);
      return;
    }

    reply.code(upstream.statusCode);

    for (const [key, value] of Object.entries(upstream.headers)) {
      if (key.toLowerCase() === 'content-length') continue;
      reply.header(key, value);
    }

    if (!isStream) {
      const chunks = [];

      for await (const chunk of upstream.body) {
        chunks.push(chunk);
      }

      const text = Buffer.concat(chunks).toString(ENCODING);

      try {
        const signature = await signingService.createHmac(text);
        if (signature) {
          reply.header('x-response-signature', signature);
        }
      } catch {}

      reply.send(text);

      if (LMSTUDIO_PROXY_SQLITE_CACHE) {
        try {
          const responseId = uuidv4();
          const encryptedResponseBody = encryptionService.encrypt(text);

          db.insertResponse.run(
            responseId,
            requestId,
            externalId,
            WebhookStatusSchema.enum.success,
            upstream.statusCode,
            encryptedResponseBody,
          );
        } catch (error) {
          fastify.log.error({ error }, 'Failed to insert non-stream response');
        }
      }

      try {
        const parsedResponse = (() => {
          try {
            return JSON.parse(text);
          } catch {
            return { raw: text };
          }
        })();
        const payload = WebhookSuccessPayloadSchema.parse({
          id: externalId,
          status: WebhookStatusSchema.enum.success,
          request: body || null,
          response: parsedResponse,
          timestamp: new Date().toISOString(),
        });
        await callWebhook(fastify, payload, WebhookEventTypeSchema.enum.success);
      } catch (error) {
        fastify.log.error({ error }, 'Failed to call success webhook');
      }
      return;
    }

    const chunks = [];
    upstream.body.on('data', (chunk) => {
      chunks.push(chunk);
      reply.raw.write(chunk);
    });

    upstream.body.on('end', async () => {
      reply.raw.end();
      const text = Buffer.concat(chunks).toString(ENCODING);

      if (LMSTUDIO_PROXY_SQLITE_CACHE) {
        try {
          const responseId = uuidv4();
          const encryptedResponseBody = encryptionService.encrypt(text);

          db.insertResponse.run(
            responseId,
            requestId,
            externalId,
            WebhookStatusSchema.enum.success,
            upstream.statusCode,
            encryptedResponseBody,
          );
        } catch (error) {
          fastify.log.error({ error }, 'Failed to insert stream response');
        }
      }

      try {
        const payload = WebhookSuccessPayloadSchema.parse({
          id: externalId,
          status: WebhookStatusSchema.enum.success,
          request: body || null,
          response: { raw: text },
          timestamp: new Date().toISOString(),
        });
        await callWebhook(fastify, payload, WebhookEventTypeSchema.enum.success);
      } catch (error) {
        fastify.log.error({ error }, 'Failed to call success webhook (stream)');
      }
    });

    upstream.body.on('error', async (error) => {
      if (!reply.raw?.writableEnded) {
        reply.raw.end();
      }

      const errorPayload = WebhookErrorPayloadSchema.parse({
        id: externalId,
        status: WebhookStatusSchema.enum.error,
        request: body,
        error: { message: error.message },
        timestamp: new Date().toISOString(),
      });

      if (LMSTUDIO_PROXY_SQLITE_CACHE) {
        fastify.log.error({ error }, 'Upstream stream error');
        try {
          const responseId = uuidv4();
          const errorBodyText = JSON.stringify(errorPayload.error);
          const encryptedErrorBody = encryptionService.encrypt(errorBodyText);

          db.insertResponse.run(
            responseId,
            requestId,
            externalId,
            WebhookStatusSchema.enum.error,
            upstream.statusCode || 500,
            encryptedErrorBody,
          );
        } catch (error) {
          fastify.log.error({ error }, 'Failed to insert stream error response');
        }
      }
      await callWebhook(fastify, errorPayload, WebhookEventTypeSchema.enum.error);
    });
  } catch (error) {
    fastify.log.error({ error }, 'error proxying to LM Studio');

    if (isChatCompletion && LMSTUDIO_PROXY_SQLITE_CACHE) {
      const errorPayload = WebhookErrorPayloadSchema.parse({
        id: requestId,
        status: WebhookStatusSchema.enum.error,
        request: body || null,
        error: { message: error.message },
        timestamp: new Date().toISOString(),
      });
      try {
        const responseId = uuidv4();
        const errorBodyText = JSON.stringify(errorPayload.error);
        const encryptedErrorBody = encryptionService.encrypt(errorBodyText);
        db.insertResponse.run(
          responseId,
          requestId,
          externalId,
          WebhookStatusSchema.enum.error,
          500,
          encryptedErrorBody,
        );
      } catch (error) {
        fastify.log.error({ error }, 'Failed to insert upstream error response');
      }
      await callWebhook(fastify, errorPayload, WebhookEventTypeSchema.enum.error);
    }

    reply.code(500).send({
      error: 'LM Studio proxy error',
      message: error.message,
    });
  }
});

fastify.get('/health', async () => ({ status: 'OK', date: new Date().toISOString() }));

fastify
  .listen({ port: Number(PROXY_PORT), host: '0.0.0.0' })
  .then((address) => {
    fastify.log.info(`Fastify LM Studio proxy listening at ${address}`);
  })
  .catch((error) => {
    fastify.log.error(error);
    process.exit(1);
  });
