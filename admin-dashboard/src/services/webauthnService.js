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

// ---------------------
// Register Biometrics
// ---------------------
export const registerBiometrics = async (email, userId) => {
  try {
    // 1️⃣ Get registration options from server
    const optionsResponse = await webauthnApi.post("/register-options", {
      email,
    });
    const options = optionsResponse.data;

    // 2️⃣ Start registration in browser
    const cred = await startRegistration(options);

    // 3️⃣ Send registration response to server
    const verificationResponse = await webauthnApi.post(
      "/verify-registration",
      {
        userId,
        cred,
      }
    );

    return verificationResponse.data;
  } catch (error) {
    console.error("Biometric registration failed:", error);
    throw error;
  }
};

// ---------------------
// Login with Biometrics
// ---------------------
export const loginWithBiometrics = async (email) => {
  try {
    // 1️⃣ Get authentication options from server
    const optionsResponse = await webauthnApi.post("/auth-options", { email });
    const options = optionsResponse.data;

    // 2️⃣ Start authentication in browser
    const cred = await startAuthentication(options);

    // 3️⃣ Send authentication response to server
    const verificationResponse = await webauthnApi.post(
      "/verify-authentication",
      {
        cred,
      }
    );

    return verificationResponse.data;
  } catch (error) {
    console.error("Biometric login failed:", error);
    throw error;
  }
};
