import crypto from 'crypto';
import { ENCODING, LMSTUDIO_PROXY_RESPONSE_SIGNING_SECRET } from '../server.const.js';

export class SigningService {
  /**
   * @description
   * Creates an HMAC signature for response verification
   */
  async createHmac(data) {
    if (!LMSTUDIO_PROXY_RESPONSE_SIGNING_SECRET) {
      return;
    }

    try {
      const hmac = crypto.createHmac('sha256', LMSTUDIO_PROXY_RESPONSE_SIGNING_SECRET);
      hmac.update(String(data), ENCODING);
      return hmac.digest('hex');
    } catch (error) {}
  }

  /**
   * @description
   * Verifies an HMAC signature with the provided secret.
   * Intended for inbound request verification.
   */
  async verifyHmac(data, signature, secret) {
    if (!secret || !signature) {
      return false;
    }

    try {
      const hmac = crypto.createHmac('sha256', secret);
      hmac.update(String(data), ENCODING);
      const expected = hmac.digest('hex');

      const expectedBuffer = Buffer.from(expected, 'hex');
      const providedBuffer = Buffer.from(String(signature), 'hex');

      if (expectedBuffer.length !== providedBuffer.length) {
        return false;
      }

      return crypto.timingSafeEqual(expectedBuffer, providedBuffer);
    } catch (error) {
      return false;
    }
  }
}
