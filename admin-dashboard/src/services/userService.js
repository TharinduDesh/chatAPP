// src/services/userService.js
import axios from "axios";
import { getCurrentAdmin } from "./authService";
import { API_BASE_URL } from "../config/apiConfig";

const API_URL = `${API_BASE_URL}/api`;

// ... (getAuthToken and adminUserApi setup remains the same) ...
const getAuthToken = () => {
  const admin = getCurrentAdmin();
  return admin ? `Bearer ${admin.token}` : "";
};

const adminUserApi = axios.create({
  baseURL: `${API_URL}/admin/users`,
  headers: { "Content-Type": "application/json" },
});

adminUserApi.interceptors.request.use((config) => {
  config.headers.Authorization = getAuthToken();
  return config;
});

// ** CHANGE THIS FUNCTION **
export const getAllUsers = async (page = 1) => {
  // Pass the page number as a query parameter
  const response = await adminUserApi.get("/", { params: { page, limit: 10 } });
  return response.data; // This will now return { users, totalPages, currentPage }
};

// ... (addUser and deleteUser functions remain the same) ...
export const addUser = async (userData) => {
  const response = await adminUserApi.post("/", userData);
  return response.data;
};

export const deleteUser = async (userId) => {
  const response = await adminUserApi.delete(`/${userId}`);
  return response.data;
};

// Function for an admin to update a user **
export const updateUser = async (userId, userData) => {
  const response = await adminUserApi.put(`/${userId}`, userData);
  return response.data;
};

// Function to permanently delete a user **
export const permanentDeleteUser = async (userId) => {
  const response = await adminUserApi.delete(`/${userId}/permanent`);
  return response.data;
};

// Function to ban a user **
export const banUser = async (userId, banData) => {
  // banData will be { reason, durationInDays }
  const response = await adminUserApi.put(`/${userId}/ban`, banData);
  return response.data;
};

// Function to unban a user **
export const unbanUser = async (userId) => {
  const response = await adminUserApi.put(`/${userId}/unban`);
  return response.data;
};

// Function to get banned users **
export const getBannedUsers = async () => {
  const response = await adminUserApi.get("/banned");
  return response.data;
};

// Function to get deleted users **
export const getDeletedUsers = async () => {
  const response = await adminUserApi.get("/deleted");
  return response.data;
};

// Function to revert a user's deletion **
export const revertUserDeletion = async (userId) => {
  const response = await adminUserApi.put(`/${userId}/revert-delete`);
  return response.data;
};

// Function to get all users for exporting **
export const getUsersForExport = async () => {
  const response = await adminUserApi.get("/export");
  return response.data;
};
