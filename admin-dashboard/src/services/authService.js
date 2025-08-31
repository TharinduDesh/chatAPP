// src/services/authService.js
import axios from "axios";
import { API_BASE_URL } from "../config/apiConfig";

const API_URL = `${API_BASE_URL}/api/admin/auth/`;

const getAuthToken = () => {
  const admin = JSON.parse(localStorage.getItem("admin"));
  return admin ? `Bearer ${admin.token}` : "";
};

// Function to handle admin login
export const login = async (email, password) => {
  const response = await axios.post(API_URL + "login", { email, password });
  if (response.data.token) {
    // Store user and token in local storage
    localStorage.setItem("admin", JSON.stringify(response.data));
  }
  return response.data;
};

// ✅ NEW: Function to handle biometric login
export const biometricLogin = async (email) => {
  console.log("FRONTEND: biometricLogin called with email:", email);
  try {
    const response = await axios.post(API_URL + "biometric-login", { email });
    console.log("FRONTEND: Biometric login response:", response.data);

    if (response.data.token) {
      localStorage.setItem("admin", JSON.stringify(response.data));
      console.log("FRONTEND: Token stored in localStorage");
    }
    return response.data;
  } catch (error) {
    console.error("FRONTEND: Biometric login error:", error);
    throw error;
  }
};

// Function to handle admin logout
export const logout = () => {
  localStorage.removeItem("admin");
};

// Function to handle admin signup **
export const signup = async (userData) => {
  // userData will be { fullName, email, password, secretKey }
  const response = await axios.post(API_URL + "signup", userData);
  if (response.data.token) {
    // Automatically log in the new admin upon successful signup
    localStorage.setItem("admin", JSON.stringify(response.data));
  }
  return response.data;
};

// Function to get the current admin from local storage
export const getCurrentAdmin = () => {
  return JSON.parse(localStorage.getItem("admin"));
};

// Function to get the logged-in admin's profile **
export const getAdminProfile = async () => {
  const response = await axios.get(API_URL + "me", {
    headers: { Authorization: getAuthToken() },
  });
  return response.data;
};

// Function to update the admin's profile **
export const updateAdminProfile = async (profileData) => {
  const response = await axios.put(API_URL + "me", profileData, {
    headers: { Authorization: getAuthToken() },
  });
  // After updating, we should also update the local storage
  const currentAdmin = getCurrentAdmin();
  if (currentAdmin) {
    const updatedAdmin = { ...currentAdmin, admin: response.data };
    localStorage.setItem("admin", JSON.stringify(updatedAdmin));
  }
  return response.data;
};

// Function to change the admin's password **
export const changeAdminPassword = async (passwordData) => {
  const response = await axios.put(API_URL + "change-password", passwordData, {
    headers: { Authorization: getAuthToken() },
  });
  return response.data;
};
