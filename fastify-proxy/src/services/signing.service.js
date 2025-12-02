import crypto from 'crypto';
import {ENCODING, LMSTUDIO_PROXY_RESPONSE_SIGNING_SECRET} from '../server.const.js';

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
    } catch (error) {
      return;
    }
  }
}
