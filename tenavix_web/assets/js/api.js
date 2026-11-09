import { getApiBase, STORAGE_KEYS } from './config.js';

/**
 * Central API client for Tenavix Shelf backend.
 * Handles JSON, Bearer tokens, and basic 401 → refresh retry.
 */
class ApiClient {
  constructor() {
    this.base = getApiBase();
  }

  setBase(url) {
    this.base = url.replace(/\/$/, '');
    localStorage.setItem('tenavix_api_base', this.base);
  }

  getAccessToken() {
    return localStorage.getItem(STORAGE_KEYS.access);
  }

  getRefreshToken() {
    return localStorage.getItem(STORAGE_KEYS.refresh);
  }

  saveSession({ accessToken, refreshToken, refreshExpiresAt, user }) {
    if (accessToken) localStorage.setItem(STORAGE_KEYS.access, accessToken);
    if (refreshToken) localStorage.setItem(STORAGE_KEYS.refresh, refreshToken);
    if (refreshExpiresAt) localStorage.setItem(STORAGE_KEYS.refreshExp, refreshExpiresAt);
    if (user) localStorage.setItem(STORAGE_KEYS.user, JSON.stringify(user));
  }

  clearSession() {
    Object.values(STORAGE_KEYS).forEach((k) => localStorage.removeItem(k));
  }

  getUser() {
    try {
      const raw = localStorage.getItem(STORAGE_KEYS.user);
      return raw ? JSON.parse(raw) : null;
    } catch {
      return null;
    }
  }

  async request(path, { method = 'GET', body, auth = true, retry = true } = {}) {
    const headers = { Accept: 'application/json' };
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    if (auth) {
      const token = this.getAccessToken();
      if (token) headers.Authorization = `Bearer ${token}`;
    }

    let res;
    try {
      res = await fetch(`${this.base}${path}`, {
        method,
        headers,
        body: body !== undefined ? JSON.stringify(body) : undefined,
      });
    } catch (err) {
      const e = new Error('Cannot reach API. Is the backend running?');
      e.code = 'network_error';
      e.cause = err;
      throw e;
    }

    if (res.status === 401 && auth && retry && this.getRefreshToken()) {
      const refreshed = await this.tryRefresh();
      if (refreshed) return this.request(path, { method, body, auth, retry: false });
    }

    const text = await res.text();
    let data = null;
    if (text) {
      try {
        data = JSON.parse(text);
      } catch {
        data = { message: text };
      }
    }

    if (!res.ok) {
      const e = new Error(data?.message || data?.error || `Request failed (${res.status})`);
      e.status = res.status;
      e.code = data?.code || 'http_error';
      e.data = data;
      throw e;
    }
    return data;
  }

  async tryRefresh() {
    const refreshToken = this.getRefreshToken();
    if (!refreshToken) return false;
    try {
      const data = await this.request('/api/v1/auth/refresh', {
        method: 'POST',
        body: { refreshToken },
        auth: false,
        retry: false,
      });
      this.saveSession(data);
      return true;
    } catch {
      this.clearSession();
      return false;
    }
  }

  // Auth
  register({ email, password, fullName }) {
    return this.request('/api/v1/auth/register', {
      method: 'POST',
      body: { email, password, fullName },
      auth: false,
    });
  }

  login({ email, password }) {
    return this.request('/api/v1/auth/login', {
      method: 'POST',
      body: { email, password },
      auth: false,
    });
  }

  logout() {
    const refreshToken = this.getRefreshToken();
    return this.request('/api/v1/auth/logout', {
      method: 'POST',
      body: { refreshToken, allSessions: false },
    }).finally(() => this.clearSession());
  }

  // Accounts
  listAccounts() {
    return this.request('/api/v1/accounts');
  }

  createAccount(payload) {
    return this.request('/api/v1/accounts', { method: 'POST', body: payload });
  }

  getAccount(id) {
    return this.request(`/api/v1/accounts/${id}`);
  }

  // Subscriptions
  activateSubscription(tradingAccountId) {
    return this.request('/api/v1/subscriptions/activate', {
      method: 'POST',
      body: { tradingAccountId },
    });
  }

  getSubscription(accountId) {
    return this.request(`/api/v1/subscriptions/${accountId}`);
  }

  // Admin
  listUsers({ q, status, limit = 50, offset = 0 } = {}) {
    const params = new URLSearchParams();
    if (q) params.set('q', q);
    if (status) params.set('status', status);
    params.set('limit', String(limit));
    params.set('offset', String(offset));
    return this.request(`/api/v1/admin/users?${params}`);
  }

  listAuditEvents({ limit = 50, actorUserId } = {}) {
    const params = new URLSearchParams();
    params.set('limit', String(limit));
    if (actorUserId) params.set('actorUserId', actorUserId);
    return this.request(`/api/v1/admin/audit-events?${params}`);
  }

  suspendUser(userId, reason) {
    return this.request(`/api/v1/admin/users/${userId}/suspend`, {
      method: 'POST',
      body: { reason },
    });
  }

  health() {
    return this.request('/health', { auth: false });
  }
}

export const api = new ApiClient();
