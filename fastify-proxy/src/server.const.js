export const ENCODING = 'utf8';
export const VLLM_HOST = process.env.VLLM_HOST || 'host.docker.internal';
export const VLLM_PORT = process.env.VLLM_PORT || '8000';
export const PROXY_PORT = process.env.PROXY_PORT || '3000';
export const VLLM_PROXY_WEBHOOK_ON_CHAT_COMPLETE =
  process.env.VLLM_PROXY_WEBHOOK_ON_CHAT_COMPLETE || '';
export const VLLM_PROXY_WEBHOOK_ON_CHAT_COMPLETE_HEADERS =
  process.env.VLLM_PROXY_WEBHOOK_ON_CHAT_COMPLETE_HEADERS || '';
export const VLLM_PROXY_SQLITE_PATH =
  process.env.VLLM_PROXY_SQLITE_PATH || '/data/vllm-proxy.db';
export const VLLM_PROXY_SQLITE_CACHE = process.env.VLLM_PROXY_SQLITE_CACHE !== 'false';
export const VLLM_PROXY_REQUEST_TIMEOUT = parseInt(
  process.env.VLLM_PROXY_REQUEST_TIMEOUT || '900000',
  10,
); // 15 minutes default
export const VLLM_PROXY_WEBHOOK_TIMEOUT = parseInt(
  process.env.VLLM_PROXY_WEBHOOK_TIMEOUT || '30000',
  10,
); // 30 seconds default
export const VLLM_SQLITE_ENCRYPTION_KEY = process.env.VLLM_SQLITE_ENCRYPTION_KEY || '';
export const VLLM_PROXY_RESPONSE_SIGNING_SECRET =
  process.env.VLLM_PROXY_RESPONSE_SIGNING_SECRET || '';
export const VLLM_PROXY_REQUEST_SIGNING_SECRET =
  process.env.VLLM_PROXY_REQUEST_SIGNING_SECRET || '';

export const CREATE_REQUESTS_TABLE = `
    CREATE TABLE IF NOT EXISTS requests
    (
        id
        TEXT
        PRIMARY
        KEY,
        external_id
        TEXT,
        endpoint
        TEXT
        NOT
        NULL,
        request_body
        TEXT
        NOT
        NULL,
        created_at
        DATETIME
        DEFAULT
        CURRENT_TIMESTAMP
    );
`;

export const CREATE_RESPONSES_TABLE = `
    CREATE TABLE IF NOT EXISTS responses
    (
        id
        TEXT
        PRIMARY
        KEY,
        request_id
        TEXT
        NOT
        NULL,
        external_id
        TEXT,
        status
        TEXT
        NOT
        NULL,
        status_code
        INTEGER,
        response_body
        TEXT,
        created_at
        DATETIME
        DEFAULT
        CURRENT_TIMESTAMP,
        FOREIGN
        KEY
    (
        request_id
    ) REFERENCES requests
    (
        id
    )
        );
`;

export const DROP_REQUESTS_TABLE = `
    DROP TABLE IF EXISTS requests;
`;
export const DROP_RESPONSES_TABLE = `
    DROP TABLE IF EXISTS responses;
`;

export const SELECT_LATEST_SUCCESS_RESPONSE_BY_EXTERNAL_ID = `
    SELECT
        response_body,
        status_code
    FROM responses
    WHERE external_id = ?
      AND status = ?
    ORDER BY created_at DESC
    LIMIT 1
`;

export const INSERT_REQUEST_QUERY = `
    INSERT
    OR IGNORE INTO requests (id, external_id, endpoint, request_body) VALUES (?, ?, ?, ?)
`;

export const INSERT_RESPONSE_QUERY = `INSERT INTO responses (id, request_id, external_id, status, status_code, response_body)
                                      VALUES (?, ?, ?, ?, ?, ?)`;
