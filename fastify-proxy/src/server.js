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
  LMSTUDIO_REQUEST_TIMEOUT,
  LMSTUDIO_SQLITE_LOGGING,
  LMSTUDIO_SQLITE_PATH,
  PROXY_PORT,
} from './server.const.js';
import { callWebhook, sanitizeForLogging } from './server.utils.js';

const db = (function dbInitialization() {
  fs.mkdirSync(path.dirname(LMSTUDIO_SQLITE_PATH), { recursive: true });
  const db = new Database(LMSTUDIO_SQLITE_PATH);

  db.exec(`
        ${CREATE_REQUESTS_TABLE}
        ${CREATE_RESPONSES_TABLE}
    `);

  const insertRequest = db.prepare(INSERT_REQUEST_QUERY);
  const insertResponse = db.prepare(INSERT_RESPONSE_QUERY);

  return {
    insertRequest,
    insertResponse,
  };
})();

const fastify = Fastify({
  logger: LMSTUDIO_SQLITE_LOGGING,
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

  if (LMSTUDIO_SQLITE_LOGGING) {
    try {
      const requestBodyText = JSON.stringify(body || {});
      const requestBodyTextSanitized = sanitizeForLogging(requestBodyText);
      db.insertRequest.run(requestId, externalId, request.raw.url, requestBodyTextSanitized);
    } catch (e) {
      fastify.log.error({ e }, 'Failed to insert request in DB');
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
      headersTimeout: LMSTUDIO_REQUEST_TIMEOUT,
      bodyTimeout: LMSTUDIO_REQUEST_TIMEOUT,
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

      if (LMSTUDIO_SQLITE_LOGGING) {
        try {
          const responseId = uuidv4();
          const responseText = bodyBuffer.toString();
          const responseTextSanitized = sanitizeForLogging(responseText);

          db.insertResponse.run(
            responseId,
            requestId,
            externalId,
            WebhookStatusSchema.enum.success,
            upstream.statusCode,
            responseTextSanitized,
          );
        } catch (e) {
          fastify.log.error({ e }, 'Failed to insert non-chat response');
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

      reply.send(text);

      if (LMSTUDIO_SQLITE_LOGGING) {
        try {
          const responseId = uuidv4();
          const responseBodyForLog = sanitizeForLogging(text);

          db.insertResponse.run(
            responseId,
            requestId,
            externalId,
            WebhookStatusSchema.enum.success,
            upstream.statusCode,
            responseBodyForLog,
          );
        } catch (e) {
          fastify.log.error({ e }, 'Failed to insert non-stream response');
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
      } catch (err) {
        fastify.log.error({ err }, 'Failed to call success webhook');
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

      if (LMSTUDIO_SQLITE_LOGGING) {
        try {
          const responseId = uuidv4();
          const responseBodyForLog = sanitizeForLogging(text);
          db.insertResponse.run(
            responseId,
            requestId,
            externalId,
            WebhookStatusSchema.enum.success,
            upstream.statusCode,
            responseBodyForLog,
          );
        } catch (e) {
          fastify.log.error({ e }, 'Failed to insert stream response');
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
      } catch (err) {
        fastify.log.error({ err }, 'Failed to call success webhook (stream)');
      }
    });

    upstream.body.on('error', async (err) => {
      if (!reply.raw?.writableEnded) {
        reply.raw.end();
      }

      const errorPayload = WebhookErrorPayloadSchema.parse({
        id: externalId,
        status: WebhookStatusSchema.enum.error,
        request: body,
        error: { message: err.message },
        timestamp: new Date().toISOString(),
      });

      if (LMSTUDIO_SQLITE_LOGGING) {
        fastify.log.error({ err }, 'Upstream stream error');
        try {
          const responseId = uuidv4();
          const errorBodyText = JSON.stringify(errorPayload.error);
          const errorBodyForLog = sanitizeForLogging(errorBodyText);
          db.insertResponse.run(
            responseId,
            requestId,
            externalId,
            WebhookStatusSchema.enum.error,
            upstream.statusCode || 500,
            errorBodyForLog,
          );
        } catch (e) {
          fastify.log.error({ e }, 'Failed to insert stream error response');
        }
      }
      await callWebhook(fastify, errorPayload, WebhookEventTypeSchema.enum.error);
    });
  } catch (err) {
    fastify.log.error({ err }, 'Error proxying to LM Studio');

    if (isChatCompletion && LMSTUDIO_SQLITE_LOGGING) {
      const errorPayload = WebhookErrorPayloadSchema.parse({
        id: requestId,
        status: WebhookStatusSchema.enum.error,
        request: body || null,
        error: { message: err.message },
        timestamp: new Date().toISOString(),
      });
      try {
        const responseId = uuidv4();
        const errorBodyText = JSON.stringify(errorPayload.error);
        const errorBodyForLog = sanitizeForLogging(errorBodyText);
        db.insertResponse.run(
          responseId,
          requestId,
          externalId,
          WebhookStatusSchema.enum.error,
          500,
          errorBodyForLog,
        );
      } catch (e) {
        fastify.log.error({ e }, 'Failed to insert upstream error response');
      }
      await callWebhook(fastify, errorPayload, WebhookEventTypeSchema.enum.error);
    }

    reply.code(500).send({
      error: 'LM Studio proxy error',
      message: err.message,
    });
  }
});

fastify.get('/health', async () => ({ status: 'OK', date: new Date().toISOString() }));

fastify
  .listen({ port: Number(PROXY_PORT), host: '0.0.0.0' })
  .then((address) => {
    fastify.log.info(`Fastify LM Studio proxy listening at ${address}`);
  })
  .catch((err) => {
    fastify.log.error(err);
    process.exit(1);
  });
