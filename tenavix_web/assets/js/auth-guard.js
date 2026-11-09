import { api } from './api.js';

/** Redirect to login if no session. Returns user or null after redirect. */
export function requireAuth(loginPath = '../pages/login.html') {
  const user = api.getUser();
  const token = api.getAccessToken();
  if (!user || !token) {
    const next = encodeURIComponent(window.location.pathname + window.location.search);
    window.location.replace(`${loginPath}?next=${next}`);
    return null;
  }
  return user;
}

export function requireAdmin(loginPath = '../pages/login.html') {
  const user = requireAuth(loginPath);
  if (!user) return null;
  const roles = user.roles || [];
  if (!roles.includes('ADMIN')) {
    window.location.replace('../pages/dashboard.html');
    return null;
  }
  return user;
}

export function redirectIfAuthenticated(target = '../pages/dashboard.html') {
  if (api.getUser() && api.getAccessToken()) {
    window.location.replace(target);
  }
}
