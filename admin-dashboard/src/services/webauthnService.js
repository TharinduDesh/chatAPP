// admin-dashboard/src/services/webauthnService.js
import axios from "axios";
import {
  startRegistration,
  startAuthentication,
} from "@simplewebauthn/browser";
import { API_BASE_URL } from "../config/apiConfig";

const webauthnApi = axios.create({
  baseURL: `${API_BASE_URL}/api/webauthn`,
});

// --- CHANGE: The first argument is now 'email' ---
export const registerBiometrics = async (email, userId) => {
  try {
    // --- CHANGE: Send the data as '{ email }' ---
    const optionsResponse = await webauthnApi.post("/register-options", {
      email,
    });
    const cred = await startRegistration(optionsResponse.data);
    const verificationResponse = await webauthnApi.post(
      "/verify-registration",
      { userId, cred }
    );
    return verificationResponse.data;
  } catch (error) {
    console.error("Registration failed:", error);
    throw error;
  }
};

// --- CHANGE: The argument is now 'email' ---
export const loginWithBiometrics = async (email) => {
  try {
    // --- CHANGE: Send the data as '{ email }' ---
    const optionsResponse = await webauthnApi.post("/auth-options", { email });
    const cred = await startAuthentication(optionsResponse.data);
    const verificationResponse = await webauthnApi.post(
      "/verify-authentication",
      { cred, email } // Include email in the verification request
    );
    return verificationResponse.data;
  } catch (error) {
    console.error("Authentication failed:", error);
    throw error;
  }
};
