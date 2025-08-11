import axios from "axios";
import { getCurrentAdmin } from "./authService";
import { API_BASE_URL } from "../config/apiConfig";

const API_URL = `${API_BASE_URL}/api/analytics`;

const getAuthHeader = () => {
  const admin = getCurrentAdmin();
  return { Authorization: admin ? `Bearer ${admin.token}` : "" };
};

export const getDashboardStats = async (dateRange) => {
  const response = await axios.get(`${API_URL}/stats`, {
    headers: getAuthHeader(),
    params: dateRange,
  });
  return response.data;
};

export const getNewUsersChartData = async (period = "week") => {
  // Default to 'week'
  const response = await axios.get(`${API_URL}/new-users-chart`, {
    headers: getAuthHeader(),
    params: { period }, // Pass { period: 'week' | 'month' | 'year' }
  });
  return response.data;
};

// Function to get the top active users **
export const getMostActiveUsers = async () => {
  const response = await axios.get(`${API_URL}/most-active-users`, {
    headers: getAuthHeader(),
  });
  return response.data;
};
