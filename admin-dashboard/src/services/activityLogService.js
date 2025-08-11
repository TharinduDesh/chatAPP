// src/services/activityLogService.js
import axios from "axios";
import { getCurrentAdmin } from "./authService";
import { API_BASE_URL } from "../config/apiConfig";

const API_URL = `${API_BASE_URL}/api/logs`;

const getAuthHeader = () => {
  const admin = getCurrentAdmin();
  return { Authorization: admin ? `Bearer ${admin.token}` : "" };
};

// Update this function to accept a search term
export const getActivityLogs = async (page = 1, searchTerm = "") => {
  const response = await axios.get(API_URL, {
    headers: getAuthHeader(),
    params: { search: searchTerm, page }, // Pass both params
  });
  // The response will now be an object: { logs, totalPages, currentPage }
  return response.data;
};

// Function to get only the most recent logs **
export const getRecentActivityLogs = async () => {
  const response = await axios.get(`${API_URL}/recent`, {
    headers: getAuthHeader(),
  });
  return response.data;
};
