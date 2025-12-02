import { request as undiciRequest } from 'undici';
import {
  ENCODING,
  LMSTUDIO_PROXY_WEBHOOK_ON_CHAT_COMPLETE,
  LMSTUDIO_PROXY_WEBHOOK_ON_CHAT_COMPLETE_HEADERS,
  LMSTUDIO_PROXY_WEBHOOK_TIMEOUT,
} from './server.const.js';

function parseWebhookHeaders(envHeaders) {
  if (!envHeaders) {
    return Object.create(null);
  }

  try {
    return JSON.parse(envHeaders);
  } catch {
    return Object.create(null);
  }
}

export function sanitizeForLogging(text) {
  return text;
}

export async function callWebhook(fastify, webhookPayload, webhookEventType) {
  if (!LMSTUDIO_PROXY_WEBHOOK_ON_CHAT_COMPLETE) {
    fastify?.log.warn('LMSTUDIO_PROXY_WEBHOOK_ON_CHAT_COMPLETE is not set; skipping webhook');
    return;
  }

  const separator = LMSTUDIO_PROXY_WEBHOOK_ON_CHAT_COMPLETE.includes('?') ? '&' : '?';
  const encodedEventType = encodeURIComponent(webhookEventType);
  const url = `${LMSTUDIO_PROXY_WEBHOOK_ON_CHAT_COMPLETE}${separator}eventType=${encodedEventType}`;
  const parsedHeaders = parseWebhookHeaders(LMSTUDIO_PROXY_WEBHOOK_ON_CHAT_COMPLETE_HEADERS);
  const headers = new Headers(parsedHeaders);

  try {
    fastify?.log.info({ url, webhookEventType }, 'Calling webhook');

    const response = await undiciRequest(url, {
      method: 'POST',
      headers,
      body: JSON.stringify(webhookPayload),
      headersTimeout: LMSTUDIO_PROXY_WEBHOOK_TIMEOUT,
      bodyTimeout: LMSTUDIO_PROXY_WEBHOOK_TIMEOUT,
    });

    await response.body.text();

    fastify?.log.info(
      { url, webhookEventType, statusCode: response.statusCode },
      'Webhook call succeeded',
    );
  } catch (err) {
    fastify?.log.error({ err, url, webhookEventType }, 'Failed to call webhook');
  }
}
