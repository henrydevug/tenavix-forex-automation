/**
 * Lightweight smoke tests for API client helpers (Node).
 * Run: node assets/js/api.test.mjs
 */
import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// Minimal localStorage polyfill for Node
const store = new Map();
globalThis.localStorage = {
  getItem: (k) => (store.has(k) ? store.get(k) : null),
  setItem: (k, v) => store.set(k, String(v)),
  removeItem: (k) => store.delete(k),
};

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Dynamic import of config
const { getApiBase, STORAGE_KEYS } = await import(
  pathToFileURL(path.join(__dirname, 'config.js')).href
);

assert.equal(typeof getApiBase(), 'string');
assert.ok(getApiBase().startsWith('http'));
assert.ok(STORAGE_KEYS.access);

const { api } = await import(pathToFileURL(path.join(__dirname, 'api.js')).href);

api.saveSession({
  accessToken: 'a',
  refreshToken: 'r',
  refreshExpiresAt: '2099-01-01T00:00:00Z',
  user: { email: 't@example.com', roles: ['TRADER'] },
});
assert.equal(api.getAccessToken(), 'a');
assert.equal(api.getUser().email, 't@example.com');
api.clearSession();
assert.equal(api.getAccessToken(), null);

console.log('api.test.mjs: OK');
