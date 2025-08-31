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
    console.log("🔍 WEBAUTHN DEBUG: Starting registration for:", email, userId);

    // 1️⃣ Get registration options from server
    const optionsResponse = await webauthnApi.post("/register-options", {
      email,
    });
    const options = optionsResponse.data;
    console.log("🔍 WEBAUTHN DEBUG: Got registration options");

    // 2️⃣ Start registration in browser
    const cred = await startRegistration(options);
    console.log("🔍 WEBAUTHN DEBUG: Browser registration completed");

    // 3️⃣ Send registration response to server
    const verificationResponse = await webauthnApi.post(
      "/verify-registration",
      {
        userId,
        cred,
      }
    );
    console.log(
      "🔍 WEBAUTHN DEBUG: Registration verification response:",
      verificationResponse.data
    );

    return verificationResponse.data;
  } catch (error) {
    console.error("🔍 WEBAUTHN DEBUG: Biometric registration failed:", error);
    throw error;
  }
};

// ---------------------
// Login with Biometrics
// ---------------------
// Update your loginWithBiometrics function
export const loginWithBiometrics = async (email) => {
  try {
    const optionsResponse = await webauthnApi.post("/auth-options", { email });
    const cred = await startAuthentication(optionsResponse.data);
    const verificationResponse = await webauthnApi.post(
      "/verify-authentication",
      { cred, email }
    );

    // If verification is successful, call the biometric login endpoint
    if (
      verificationResponse.data.verified &&
      verificationResponse.data.userId
    ) {
      const loginResponse = await webauthnApi.post(
        "/admin/auth/biometric-login",
        {
          userId: verificationResponse.data.userId,
        }
      );
      return loginResponse.data;
    }

    return verificationResponse.data;
  } catch (error) {
    console.error("Authentication failed:", error);
    throw error;
  }
};
