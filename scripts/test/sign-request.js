#!/usr/bin/env node

/**
 * Generate HMAC signature for request body
 * Usage: node scripts/sign-request.js <secret> <json-body>
 */

const crypto = require('crypto');

const secret = process.argv[2];
const body = process.argv[3];

if (!secret || !body) {
  console.error('Usage: node scripts/sign-request.js <secret> <json-body>');
  console.error('');
  console.error('Example:');
  console.error('  node scripts/sign-request.js "my-secret" \'{"model":"test","messages":[]}\'');
  process.exit(1);
}

try {
  // Parse and re-stringify to normalize the JSON (same as server does)
  const parsedBody = JSON.parse(body);
  const normalizedBody = JSON.stringify(parsedBody);
  
  // Generate HMAC SHA256 signature
  const hmac = crypto.createHmac('sha256', secret);
  hmac.update(normalizedBody, 'utf8');
  const signature = hmac.digest('hex');
  
  console.log(signature);
} catch (error) {
  console.error('Error:', error.message);
  process.exit(1);
}
