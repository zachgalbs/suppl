import { test, describe, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createServer, DEFAULT_TOKEN_URL } from '../server.js';

const SECRET = 'test-secret-do-not-leak-7f3a';
const baseEnv = {
  WHOOP_CLIENT_ID: 'client-123',
  WHOOP_CLIENT_SECRET: SECRET,
  WHOOP_REDIRECT_URI: 'suppl://whoop/callback',
};

/** A fake fetch that records calls and answers with `reply`. */
function fakeFetch(reply = { status: 200, body: { access_token: 'a1', refresh_token: 'r1', expires_in: 3600, scope: 'offline read:workout read:sleep', token_type: 'bearer' } }) {
  const calls = [];
  const impl = async (url, init) => {
    calls.push({ url, init, form: new URLSearchParams(init.body) });
    if (reply instanceof Error) throw reply;
    const text = typeof reply.body === 'string' ? reply.body : JSON.stringify(reply.body);
    return new Response(text, { status: reply.status, headers: { 'content-type': 'application/json' } });
  };
  impl.calls = calls;
  return impl;
}

async function start({ env = baseEnv, fetchImpl = fakeFetch() } = {}) {
  const lines = [];
  const server = createServer({ env, fetchImpl, log: (line) => lines.push(line) });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address();
  return {
    url: `http://127.0.0.1:${port}`,
    fetchImpl,
    lines,
    close: () => new Promise((resolve) => server.close(resolve)),
  };
}

async function post(base, path, body, headers = {}) {
  const res = await fetch(base + path, {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...headers },
    body: typeof body === 'string' ? body : JSON.stringify(body),
  });
  const text = await res.text();
  return { status: res.status, text, json: text ? JSON.parse(text) : null, headers: res.headers };
}

describe('config', () => {
  test('refuses to start without a client secret', () => {
    assert.throws(() => createServer({ env: { WHOOP_CLIENT_ID: 'x' }, fetchImpl: fakeFetch() }), /WHOOP_CLIENT_SECRET/);
  });
});

describe('POST /whoop/token', () => {
  let s;
  before(async () => { s = await start(); });
  after(() => s.close());

  test('exchanges the code with the right form fields', async () => {
    const res = await post(s.url, '/whoop/token', { code: 'auth-code-1' });
    assert.equal(res.status, 200);
    assert.deepEqual(res.json, { access_token: 'a1', refresh_token: 'r1', expires_in: 3600, scope: 'offline read:workout read:sleep', token_type: 'bearer' });
    assert.equal(res.headers.get('cache-control'), 'no-store');

    const call = s.fetchImpl.calls.at(-1);
    assert.equal(call.url, DEFAULT_TOKEN_URL);
    assert.equal(call.init.method, 'POST');
    assert.equal(call.init.headers['content-type'], 'application/x-www-form-urlencoded');
    assert.deepEqual(Object.fromEntries(call.form), {
      grant_type: 'authorization_code',
      code: 'auth-code-1',
      client_id: 'client-123',
      client_secret: SECRET,
      redirect_uri: 'suppl://whoop/callback',
    });
  });

  test('missing code is a 400 and never reaches WHOOP', async () => {
    const before = s.fetchImpl.calls.length;
    const res = await post(s.url, '/whoop/token', {});
    assert.equal(res.status, 400);
    assert.equal(res.json.error, 'missing_code');
    assert.equal(s.fetchImpl.calls.length, before);
  });

  test('rejects non-JSON bodies', async () => {
    const res = await fetch(s.url + '/whoop/token', { method: 'POST', headers: { 'content-type': 'text/plain' }, body: 'code=x' });
    assert.equal(res.status, 415);
  });

  test('rejects malformed JSON', async () => {
    const res = await post(s.url, '/whoop/token', '{"code":');
    assert.equal(res.status, 400);
    assert.equal(res.json.error, 'invalid_json');
  });

  test('rejects bodies over 16 KB', async () => {
    const res = await post(s.url, '/whoop/token', { code: 'x'.repeat(17 * 1024) });
    assert.equal(res.status, 413);
  });

  test('rejects chunked bodies over 16 KB (no content-length)', async () => {
    const chunk = new TextEncoder().encode('x'.repeat(4096));
    let sent = 0;
    const body = new ReadableStream({
      pull(controller) {
        if (sent++ < 8) controller.enqueue(chunk);
        else controller.close();
      },
    });
    const res = await fetch(s.url + '/whoop/token', {
      method: 'POST', headers: { 'content-type': 'application/json' }, body, duplex: 'half',
    }).catch((err) => err);
    // Either we read the 413, or the server closed the socket after sending it.
    if (res instanceof Error) return;
    assert.equal(res.status, 413);
  });

  test('wrong method is a 405, unknown path a 404', async () => {
    assert.equal((await fetch(s.url + '/whoop/token')).status, 405);
    assert.equal((await post(s.url, '/nope', { code: 'x' })).status, 404);
  });

  test('logs method, path, and status only', async () => {
    await post(s.url, '/whoop/token', { code: 'code-that-must-not-be-logged' });
    const joined = s.lines.join('\n');
    assert.match(joined, /POST \/whoop\/token 200/);
    assert.ok(!joined.includes('code-that-must-not-be-logged'));
    assert.ok(!joined.includes('a1'));
    assert.ok(!joined.includes(SECRET));
  });
});

describe('POST /whoop/refresh', () => {
  test('sends grant_type refresh_token with scope offline', async () => {
    const s = await start({ fetchImpl: fakeFetch({ status: 200, body: { access_token: 'a2', refresh_token: 'r2', expires_in: 3600, token_type: 'bearer' } }) });
    try {
      const res = await post(s.url, '/whoop/refresh', { refresh_token: 'r1' });
      assert.equal(res.status, 200);
      assert.equal(res.json.access_token, 'a2');
      assert.equal(res.json.refresh_token, 'r2');
      assert.deepEqual(Object.fromEntries(s.fetchImpl.calls[0].form), {
        grant_type: 'refresh_token',
        refresh_token: 'r1',
        client_id: 'client-123',
        client_secret: SECRET,
        scope: 'offline',
      });
    } finally {
      await s.close();
    }
  });

  test('missing refresh_token is a 400', async () => {
    const s = await start();
    try {
      const res = await post(s.url, '/whoop/refresh', { code: 'x' });
      assert.equal(res.status, 400);
      assert.equal(res.json.error, 'missing_refresh_token');
    } finally {
      await s.close();
    }
  });

  test('passes WHOOP error status through without leaking the secret', async () => {
    const s = await start({ fetchImpl: fakeFetch({ status: 400, body: { error: 'invalid_grant', error_description: `bad client_secret=${SECRET}`, debug: SECRET } }) });
    try {
      const res = await post(s.url, '/whoop/refresh', { refresh_token: 'old' });
      assert.equal(res.status, 400);
      assert.equal(res.json.error, 'invalid_grant');
      assert.ok(!res.text.includes(SECRET), 'secret must not appear in the response');
      assert.equal(res.json.debug, undefined, 'unexpected fields are dropped');
    } finally {
      await s.close();
    }
  });
});

describe('upstream failures', () => {
  test('unreachable WHOOP is a 502', async () => {
    const s = await start({ fetchImpl: fakeFetch(new Error(`connect ECONNREFUSED ${SECRET}`)) });
    try {
      const res = await post(s.url, '/whoop/token', { code: 'x' });
      assert.equal(res.status, 502);
      assert.equal(res.json.error, 'upstream_unreachable');
      assert.ok(!res.text.includes(SECRET));
    } finally {
      await s.close();
    }
  });

  test('non-JSON from WHOOP is a 502', async () => {
    const s = await start({ fetchImpl: fakeFetch({ status: 200, body: '<html>oops</html>' }) });
    try {
      const res = await post(s.url, '/whoop/token', { code: 'x' });
      assert.equal(res.status, 502);
      assert.equal(res.json.error, 'upstream_invalid_response');
    } finally {
      await s.close();
    }
  });

  test('a success response that echoes the secret is scrubbed', async () => {
    const s = await start({ fetchImpl: fakeFetch({ status: 200, body: { access_token: 'a', scope: `offline ${SECRET}`, client_secret: SECRET } }) });
    try {
      const res = await post(s.url, '/whoop/token', { code: 'x' });
      assert.equal(res.status, 200);
      assert.ok(!res.text.includes(SECRET));
    } finally {
      await s.close();
    }
  });
});

describe('APP_KEY', () => {
  let s;
  before(async () => { s = await start({ env: { ...baseEnv, APP_KEY: 'speed-bump' } }); });
  after(() => s.close());

  test('wrong or missing key is a 401 and never reaches WHOOP', async () => {
    assert.equal((await post(s.url, '/whoop/token', { code: 'x' }, { 'x-suppl-key': 'nope' })).status, 401);
    assert.equal((await post(s.url, '/whoop/token', { code: 'x' })).status, 401);
    assert.equal(s.fetchImpl.calls.length, 0);
  });

  test('right key works', async () => {
    const res = await post(s.url, '/whoop/token', { code: 'x' }, { 'x-suppl-key': 'speed-bump' });
    assert.equal(res.status, 200);
  });

  test('healthz needs no key', async () => {
    const res = await fetch(s.url + '/healthz');
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { ok: true });
  });
});
