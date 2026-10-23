# whoop-broker

A small HTTP service that holds WHOOP's client secret for the suppl. iOS app. WHOOP's token endpoint needs the secret for both the code exchange and every refresh, and a secret inside an app binary is public. So the app sends the code (or refresh token) here, the broker adds the secret, forwards to WHOOP, and returns WHOOP's token JSON.

The broker stores nothing, logs only `METHOD /path STATUS ms`, and never sees WHOOP health data: the app calls WHOOP's data API directly with the access token.

No dependencies. Node 22 or later.

## Endpoints

| Method | Path | Body | What it does |
|---|---|---|---|
| `POST` | `/whoop/token` | `{"code": "..."}` | `grant_type=authorization_code` with `client_id`, `client_secret`, `redirect_uri` |
| `POST` | `/whoop/refresh` | `{"refresh_token": "..."}` | `grant_type=refresh_token` with `client_id`, `client_secret`, `scope=offline` |
| `GET` | `/healthz` | | `{"ok": true}` |

Success returns WHOOP's `access_token`, `refresh_token`, `expires_in`, `scope`, `token_type` and nothing else. A WHOOP error keeps WHOOP's status code (the app treats a 400 on refresh as "sign in again") with only `error` and `error_description`. Other errors: 400 missing field or bad JSON, 401 wrong `x-suppl-key`, 404, 405, 413 body over 16 KB, 415 not `application/json`, 502 WHOOP unreachable or not JSON.

## Run locally

```sh
cd server/whoop-broker
cp .env.example .env      # fill in WHOOP_CLIENT_ID and WHOOP_CLIENT_SECRET
npm run dev               # node --env-file=.env index.js, listens on 127.0.0.1:8787
curl http://127.0.0.1:8787/healthz
npm test                  # node --test, uses a fake fetch, no network
```

The app only talks to an `https://` broker URL, so a phone can't use a laptop on plain HTTP. For a device test, use the VPS setup below or a tunnel that gives you HTTPS.

## Deploy on a VPS behind HTTPS

1. Copy this folder to the server, for example `/opt/whoop-broker`. Node 22+ must be installed.
2. Put the env in `/etc/whoop-broker.env` (mode `600`, owned by root):
   ```
   WHOOP_CLIENT_ID=...
   WHOOP_CLIENT_SECRET=...
   WHOOP_REDIRECT_URI=suppl://whoop/callback
   APP_KEY=...
   HOST=127.0.0.1
   PORT=8787
   ```
3. systemd unit `/etc/systemd/system/whoop-broker.service`:
   ```ini
   [Unit]
   Description=suppl WHOOP token broker
   After=network-online.target

   [Service]
   EnvironmentFile=/etc/whoop-broker.env
   ExecStart=/usr/bin/node /opt/whoop-broker/index.js
   DynamicUser=yes
   Restart=on-failure
   NoNewPrivileges=yes
   ProtectSystem=strict
   ProtectHome=yes

   [Install]
   WantedBy=multi-user.target
   ```
   Then `systemctl enable --now whoop-broker`.
4. HTTPS in front. With Caddy (gets a certificate on its own), `/etc/caddy/Caddyfile`:
   ```
   whoop.example.com {
       reverse_proxy 127.0.0.1:8787
   }
   ```
   With nginx, proxy `location / { proxy_pass http://127.0.0.1:8787; }` inside a `server` block that has a Let's Encrypt certificate (certbot). Either way, keep the broker bound to `127.0.0.1` so it is only reachable through the proxy. Consider a per-IP rate limit at the proxy.
5. Check: `curl https://whoop.example.com/healthz` returns `{"ok":true}`.

### About APP_KEY

If `APP_KEY` is set, `/whoop/token` and `/whoop/refresh` require the same value in an `x-suppl-key` header. The key ships inside the app, so anyone who unpacks the app can read it. It keeps drive-by traffic out. It is not a secret and does not protect the client secret: that protection comes from the secret never leaving this server.

The app sends the header only if its Info.plist has a non-empty `WHOOPAppKey`. That key is not in `project.yml` yet. To use it, add `WHOOPAppKey: $(WHOOP_APP_KEY)` under the Suppl target's `info.properties` and `WHOOP_APP_KEY =` to `Config/Suppl.xcconfig`. Until then, leave `APP_KEY` unset on the broker.

## Register a WHOOP developer app

1. Sign in at https://developer-dashboard.whoop.com with a WHOOP account and create a team, then an app (up to 5 apps per team).
2. Redirect URL: `suppl://whoop/callback`. It must match exactly what the app sends.
3. Scopes: `read:workout` and `read:sleep`. Nothing else is needed. The app also requests `offline` at sign-in, which is what makes WHOOP return a refresh token.
4. Copy the Client ID and Client Secret. The secret goes only into the broker's env.

**Member limit.** A new WHOOP app starts on the Sandbox tier, which allows up to 10 WHOOP members to connect. Going past 10 needs WHOOP's app approval (tested with at least one member, accurate dashboard info, WHOOP brand guidelines). Developers on WHOOP's forum report approval taking months, so plan TestFlight around 10 WHOOP users.

## Turn WHOOP on in the app

Create `Config/Secrets.xcconfig` in the repo root (gitignored, included by `Config/Suppl.xcconfig`):

```
WHOOP_CLIENT_ID = your-whoop-client-id
WHOOP_BROKER_URL = https:/$()/whoop.example.com
```

The `$()` is needed because xcconfig treats `//` as a comment. Rebuild. With either value empty, the WHOOP card says "Not available yet" and has no Connect button. Never put the client secret in any xcconfig.

## What was checked against WHOOP's docs (2026-10-23)

Sources: developer.whoop.com `docs/developing/oauth`, `docs/developing/rate-limiting`, `docs/developing/app-approval`, `docs/developing/user-data/sleep`, `docs/tutorials/refresh-token-javascript`, and the API reference at `developer.whoop.com/api`.

- Authorize URL `https://api.prod.whoop.com/oauth/oauth2/auth`, token URL `https://api.prod.whoop.com/oauth/oauth2/token`. Confirmed.
- `state` must be 8 characters if you generate it. Confirmed. The app generates 8 random alphanumerics and checks it on return.
- Redirect URL must be registered in the dashboard; WHOOP's own example uses a custom scheme (`whoop://example/redirect`), so `suppl://whoop/callback` is allowed.
- Scopes listed in the API reference: `read:recovery`, `read:cycles`, `read:workout`, `read:sleep`, `read:profile`, `read:body_measurement`. `offline` is documented on the OAuth page as the scope that yields a refresh token.
- Token requests are `application/x-www-form-urlencoded` POSTs (WHOOP's refresh tutorial uses `URLSearchParams`). Refresh body: `grant_type=refresh_token`, `refresh_token`, `client_id`, `client_secret`, `scope=offline`. The authorization-code body is not spelled out in the docs; the broker sends the standard OAuth 2.0 fields (`grant_type=authorization_code`, `code`, `client_id`, `client_secret`, `redirect_uri`).
- Token response: `access_token`, `expires_in` (3600 in the example), `refresh_token`, `scope`, `token_type` ("bearer").
- Refresh tokens rotate: the app must use the new refresh token next time, and the old access token stops working. Of two simultaneous refreshes, only the first succeeds. The app runs one refresh at a time and saves the new pair before using it.
- Data endpoints: `GET https://api.prod.whoop.com/developer/v2/activity/workout` and `.../v2/activity/sleep`. Query: `limit` (max 25), `start` (inclusive), `end` (exclusive, default now), `nextToken`. Response: `records` and `next_token`, newest first.
- Record fields used: workout `start`, `end`; sleep `start`, `end`, `nap` (boolean). `score_state` is `SCORED`, `PENDING_SCORE`, or `UNSCORABLE`; the app ignores it because a wake time doesn't depend on scoring. Timestamps are ISO 8601 UTC with milliseconds.
- Revoke: `DELETE https://api.prod.whoop.com/developer/v2/user/access` returns 204. The app calls it on disconnect and ignores failures.
- Rate limits: 100 requests per minute and 10,000 per day per client by default. Headers `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset` (seconds). Over the limit returns 429. The docs don't mention `Retry-After`; the app honours it if present, else `X-RateLimit-Reset`, else backs off 1, 2, 4 minutes and so on, up to an hour.
- An expired or invalid access token returns 401. The app refreshes once and retries.

Differences from the original build brief: none in the URLs, scopes, paths, or state rule. Two additions: WHOOP does have a revoke endpoint (used), and WHOOP documents `X-RateLimit-Reset` rather than `Retry-After`.
