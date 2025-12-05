import { z } from 'zod';

export const HeadersSchema = z.enum(['x-response-signature']);

export const WebhookStatusSchema = z.enum(['success', 'error']);
export const WebhookEventTypeSchema = z.enum(['success', 'error']);
export const HealthStatusSchema = z.enum(['OK', 'DEGRADED', 'UNHEALTHY', 'UNREACHABLE']);
const WebhookBasePayloadSchema = z.object({
  id: z.string().optional(),
  status: WebhookStatusSchema,
  request: z.record(z.any()).default({}),
  timestamp: z.string(),
});
export const WebhookSuccessPayloadSchema = WebhookBasePayloadSchema.extend({
  status: z.literal(WebhookStatusSchema.enum.success),
  response: z.record(z.any()),
});
export const WebhookErrorPayloadSchema = WebhookBasePayloadSchema.extend({
  status: z.literal(WebhookStatusSchema.enum.error),
  error: z.record(z.any()),
});
