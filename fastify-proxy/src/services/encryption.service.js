import crypto from 'crypto';
import { ENCODING } from '../server.const.js';

export class EncryptionService {
  constructor(secret) {
    if (!secret) {
      throw new Error('`LMSTUDIO_SQLITE_ENCRYPTION_KEY` is required for EncryptionService');
    }
    this.key = crypto.createHash('sha256').update(secret, ENCODING).digest();
  }

  encrypt(plaintext) {
    if (plaintext == null) {
      return '';
    }

    const iv = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv('aes-256-gcm', this.key, iv);
    const ciphertext = Buffer.concat([cipher.update(String(plaintext), ENCODING), cipher.final()]);

    const tag = cipher.getAuthTag();
    const payload = Buffer.concat([iv, tag, ciphertext]);

    return payload.toString('base64');
  }

  decrypt(encoded) {
    if (!encoded) {
      return '';
    }

    const buffer = Buffer.from(encoded, 'base64');

    const iv = buffer.subarray(0, 12);
    const tag = buffer.subarray(12, 28);
    const ciphertext = buffer.subarray(28);

    const decipher = crypto.createDecipheriv('aes-256-gcm', this.key, iv);
    decipher.setAuthTag(tag);

    const decrypted = Buffer.concat([decipher.update(ciphertext), decipher.final()]);

    return decrypted.toString(ENCODING);
  }
}
