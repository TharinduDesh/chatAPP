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

// ------------------- REGISTER BIOMETRICS -------------------
export const registerBiometrics = async (email, userId) => {
  try {
    // Get registration options from server
    const optionsResponse = await webauthnApi.post("/register-options", {
      email,
    });

    // Start registration in browser
    const credential = await startRegistration(optionsResponse.data);

    // Send credential to server for verification
    const verificationResponse = await webauthnApi.post(
      "/verify-registration",
      {
        userId,
        cred: credential,
      }
    );

    return verificationResponse.data;
  } catch (error) {
    console.error("Biometric registration failed:", error);
    throw error;
  }
};

// ------------------- LOGIN WITH BIOMETRICS -------------------
export const loginWithBiometrics = async (email) => {
  try {
    // Get authentication options from server
    const optionsResponse = await webauthnApi.post("/auth-options", { email });

    // Start authentication in browser
    const credential = await startAuthentication(optionsResponse.data);

    // Send credential to server for verification
    const verificationResponse = await webauthnApi.post(
      "/verify-authentication",
      {
        email,
        cred: credential,
      }
    );

    return verificationResponse.data;
  } catch (error) {
    console.error("Biometric authentication failed:", error);
    throw error;
  }
};
