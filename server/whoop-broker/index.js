// Entry point: `node index.js` (or `npm start`). Config comes from the environment; see .env.example.
import { createServer, readConfig } from './server.js';

try {
  readConfig(process.env);
} catch (err) {
  console.error(err.message);
  process.exit(1);
}

if (!process.env.APP_KEY) {
  console.warn('APP_KEY is not set: any client can use this broker.');
}

const port = Number(process.env.PORT) || 8787;
const host = process.env.HOST || '127.0.0.1';
const server = createServer();
server.listen(port, host, () => {
  console.log(`whoop-broker listening on http://${host}:${port}`);
});

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
