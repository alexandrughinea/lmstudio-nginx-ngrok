export const ENCODING = 'utf8';
export const LMSTUDIO_HOST = process.env.LMSTUDIO_HOST || 'host.docker.internal';
export const LMSTUDIO_PORT = process.env.LMSTUDIO_PORT || '1234';
export const PROXY_PORT = process.env.PROXY_PORT || '3000';
export const LMSTUDIO_WEBHOOK_ON_CHAT_COMPLETE =
  process.env.LMSTUDIO_WEBHOOK_ON_CHAT_COMPLETE || '';
export const LMSTUDIO_WEBHOOK_ON_CHAT_COMPLETE_HEADERS =
  process.env.LMSTUDIO_WEBHOOK_ON_CHAT_COMPLETE_HEADERS || '';
export const LMSTUDIO_SQLITE_PATH = process.env.LMSTUDIO_SQLITE_PATH || '/data/lmstudio-proxy.db';
export const LMSTUDIO_SQLITE_LOGGING = process.env.LMSTUDIO_SQLITE_LOGGING !== 'false';
export const LMSTUDIO_SQLITE_PRIVACY_TRIM = process.env.LMSTUDIO_SQLITE_PRIVACY_TRIM === 'true';

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

export const INSERT_REQUEST_QUERY = `
    INSERT
    OR IGNORE INTO requests (id, external_id, endpoint, request_body) VALUES (?, ?, ?, ?)
`;

export const INSERT_RESPONSE_QUERY = `INSERT INTO responses (id, request_id, external_id, status, status_code, response_body)
                                      VALUES (?, ?, ?, ?, ?, ?)`;
