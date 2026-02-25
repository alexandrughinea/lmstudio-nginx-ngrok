import { request as undiciRequest } from 'undici';
import {
  VLLM_PROXY_WEBHOOK_ON_CHAT_COMPLETE,
  VLLM_PROXY_WEBHOOK_ON_CHAT_COMPLETE_HEADERS,
  VLLM_PROXY_WEBHOOK_TIMEOUT,
  VLLM_PROXY_REQUEST_SIGNING_SECRET,
} from './server.const.js';
import { SigningService } from './services/signing.service.js';
import { HeadersSchema } from './server.schemas.js';

const signingService = new SigningService();

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

export async function verifyRequestSignature(body, headers) {
  if (!VLLM_PROXY_REQUEST_SIGNING_SECRET) {
    return true;
  }

  const signatureHeader = headers[HeadersSchema.enum['x-request-signature']];
  const signature = Array.isArray(signatureHeader) ? signatureHeader[0] : signatureHeader;
  const payloadForSigning = JSON.stringify(body || {});

  return signingService.verifyHmac(
    payloadForSigning,
    signature,
    VLLM_PROXY_REQUEST_SIGNING_SECRET,
  );
}

export async function callWebhook(fastify, webhookPayload, webhookEventType) {
  if (!VLLM_PROXY_WEBHOOK_ON_CHAT_COMPLETE) {
    fastify?.log.warn('VLLM_PROXY_WEBHOOK_ON_CHAT_COMPLETE is not set; skipping webhook');
    return;
  }

  const separator = VLLM_PROXY_WEBHOOK_ON_CHAT_COMPLETE.includes('?') ? '&' : '?';
  const encodedEventType = encodeURIComponent(webhookEventType);
  const url = `${VLLM_PROXY_WEBHOOK_ON_CHAT_COMPLETE}${separator}eventType=${encodedEventType}`;
  const parsedHeaders = parseWebhookHeaders(VLLM_PROXY_WEBHOOK_ON_CHAT_COMPLETE_HEADERS);
  const headers = new Headers(parsedHeaders);

  try {
    fastify?.log.info({ url, webhookEventType }, 'Calling webhook');

    const response = await undiciRequest(url, {
      method: 'POST',
      headers,
      body: JSON.stringify(webhookPayload),
      headersTimeout: VLLM_PROXY_WEBHOOK_TIMEOUT,
      bodyTimeout: VLLM_PROXY_WEBHOOK_TIMEOUT,
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
