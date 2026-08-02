const API_URL = `${import.meta.env.VITE_API_URL}/auth`;

export const login = (userData) => {
  return fetch(`${API_URL}/login`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json"
    },
    body: JSON.stringify(userData)
  });
};

export const register = (userData) => {
  return fetch(`${API_URL}/register`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json"
    },
    body: JSON.stringify(userData)
  });
};

export const getMe = (token) => {
  return fetch(`${API_URL}/me`, {
    headers: {
      Authorization: `Bearer ${token}`
    }
  });
};