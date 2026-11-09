/** API base URL — override via localStorage key tenavix_api_base */
export function getApiBase() {
  const stored = localStorage.getItem('tenavix_api_base');
  if (stored) return stored.replace(/\/$/, '');
  // Default local Shelf server
  return 'http://localhost:8080';
}

export const STORAGE_KEYS = {
  access: 'tenavix_access_token',
  refresh: 'tenavix_refresh_token',
  user: 'tenavix_user',
  refreshExp: 'tenavix_refresh_expires',
};
