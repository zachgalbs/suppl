// Token broker for the suppl. iOS app.
//
// The app can't hold WHOOP's client secret, so it sends the OAuth code (or a refresh token) here and
// we add the secret and forward to WHOOP's token endpoint. Nothing is stored and no body is logged.

import http from 'node:http';
import { timingSafeEqual } from 'node:crypto';

export const DEFAULT_TOKEN_URL = 'https://api.prod.whoop.com/oauth/oauth2/token';
export const MAX_BODY_BYTES = 16 * 1024;
const UPSTREAM_TIMEOUT_MS = 10_000;
// Only these fields of WHOOP's token response go back to the app.
const TOKEN_FIELDS = ['access_token', 'refresh_token', 'expires_in', 'scope', 'token_type'];
const ERROR_FIELDS = ['error', 'error_description'];

class HttpError extends Error {
  constructor(status, code) {
    super(code);
    this.status = status;
    this.code = code;
  }
}

/** Reads the env the broker needs. Throws if a required value is missing. */
export function readConfig(env) {
  const config = {
    clientId: env.WHOOP_CLIENT_ID ?? '',
    clientSecret: env.WHOOP_CLIENT_SECRET ?? '',
    redirectUri: env.WHOOP_REDIRECT_URI || 'suppl://whoop/callback',
    tokenUrl: env.WHOOP_TOKEN_URL || DEFAULT_TOKEN_URL,
    appKey: env.APP_KEY ?? '',
  };
  const missing = [];
  if (!config.clientId) missing.push('WHOOP_CLIENT_ID');
  if (!config.clientSecret) missing.push('WHOOP_CLIENT_SECRET');
  if (missing.length) throw new Error(`Missing env: ${missing.join(', ')}`);
  return config;
}

/**
 * Builds the HTTP server. `fetchImpl` and `env` are injectable for tests.
 * Routes: GET /healthz, POST /whoop/token {code}, POST /whoop/refresh {refresh_token}.
 */
export function createServer({ fetchImpl = globalThis.fetch, env = process.env, log = defaultLog } = {}) {
  const config = readConfig(env);

  const routes = {
    '/whoop/token': (body) => {
      const code = requireString(body, 'code');
      return {
        grant_type: 'authorization_code',
        code,
        client_id: config.clientId,
        client_secret: config.clientSecret,
        redirect_uri: config.redirectUri,
      };
    },
    '/whoop/refresh': (body) => {
      const refreshToken = requireString(body, 'refresh_token');
      return {
        grant_type: 'refresh_token',
        refresh_token: refreshToken,
        client_id: config.clientId,
        client_secret: config.clientSecret,
        scope: 'offline',
      };
    },
  };

  return http.createServer(async (req, res) => {
    const started = Date.now();
    // Path only: never log query strings or bodies.
    const path = (req.url ?? '/').split('?')[0];
    let status = 500;
    try {
      if (path === '/healthz') {
        if (req.method !== 'GET' && req.method !== 'HEAD') throw new HttpError(405, 'method_not_allowed');
        status = send(res, 200, { ok: true });
        return;
      }
      const route = routes[path];
      if (!route) throw new HttpError(404, 'not_found');
      if (req.method !== 'POST') throw new HttpError(405, 'method_not_allowed');
      checkAppKey(req, config.appKey);
      const body = await readJson(req);
      const form = route(body);
      const upstream = await exchange(fetchImpl, config.tokenUrl, form);
      status = send(res, upstream.status, scrub(upstream.body, config.clientSecret));
    } catch (err) {
      if (err instanceof HttpError) {
        // Don't keep reading an oversized upload on a kept-alive connection.
        if (err.status === 413) res.setHeader('connection', 'close');
        status = send(res, err.status, { error: err.code });
      } else {
        status = send(res, 500, { error: 'internal_error' });
      }
    } finally {
      log(`${req.method} ${path} ${status} ${Date.now() - started}ms`);
    }
  });
}

function defaultLog(line) {
  console.log(line);
}

function send(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(payload),
    'cache-control': 'no-store',
  });
  res.end(payload);
  return status;
}

/** The key ships inside the app, so this only keeps casual traffic out. It is not a secret. */
function checkAppKey(req, expected) {
  if (!expected) return;
  const given = Buffer.from(String(req.headers['x-suppl-key'] ?? ''));
  const want = Buffer.from(expected);
  if (given.length !== want.length || !timingSafeEqual(given, want)) {
    throw new HttpError(401, 'unauthorized');
  }
}

async function readJson(req) {
  const type = String(req.headers['content-type'] ?? '').toLowerCase();
  if (!type.startsWith('application/json')) throw new HttpError(415, 'expected_json');
  if (Number(req.headers['content-length'] ?? 0) > MAX_BODY_BYTES) throw new HttpError(413, 'body_too_large');
  const raw = await readBody(req);
  try {
    const parsed = JSON.parse(raw.toString('utf8'));
    if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) throw new Error('not an object');
    return parsed;
  } catch {
    throw new HttpError(400, 'invalid_json');
  }
}

/** Collects the body, rejecting once it passes the limit (covers chunked bodies with no content-length). */
function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    const onData = (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY_BYTES) {
        req.off('data', onData);
        reject(new HttpError(413, 'body_too_large'));
        return;
      }
      chunks.push(chunk);
    };
    req.on('data', onData);
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', () => reject(new HttpError(400, 'bad_request')));
  });
}

function requireString(body, field) {
  const value = body[field];
  if (typeof value !== 'string' || value.length === 0 || value.length > 4096) {
    throw new HttpError(400, `missing_${field}`);
  }
  return value;
}

/** POSTs the form to WHOOP and returns its status with only the expected fields of its JSON. */
async function exchange(fetchImpl, tokenUrl, form) {
  let response;
  try {
    response = await fetchImpl(tokenUrl, {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded', accept: 'application/json' },
      body: new URLSearchParams(form).toString(),
      signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
    });
  } catch {
    throw new HttpError(502, 'upstream_unreachable');
  }
  let json;
  try {
    json = JSON.parse(await response.text());
  } catch {
    throw new HttpError(502, 'upstream_invalid_response');
  }
  if (json === null || typeof json !== 'object') throw new HttpError(502, 'upstream_invalid_response');
  if (response.ok) {
    if (typeof json.access_token !== 'string') throw new HttpError(502, 'upstream_invalid_response');
    return { status: 200, body: pick(json, TOKEN_FIELDS) };
  }
  // Pass WHOOP's status through (400 invalid_grant tells the app to sign in again), but only its error fields.
  const status = response.status >= 400 && response.status < 600 ? response.status : 502;
  const body = pick(json, ERROR_FIELDS);
  if (!body.error) body.error = 'upstream_error';
  return { status, body };
}

function pick(obj, fields) {
  const out = {};
  for (const field of fields) {
    if (obj[field] !== undefined && (typeof obj[field] === 'string' || typeof obj[field] === 'number')) {
      out[field] = obj[field];
    }
  }
  return out;
}

/** Belt and braces: the secret must never leave this process, even if WHOOP echoes it back. */
function scrub(body, secret) {
  const out = {};
  for (const [key, value] of Object.entries(body)) {
    out[key] = typeof value === 'string' && secret && value.includes(secret) ? value.split(secret).join('[redacted]') : value;
  }
  return out;
}
