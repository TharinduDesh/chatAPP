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
    console.log("Starting biometric login for:", email);

    const optionsResponse = await webauthnApi.post("/auth-options", { email });
    console.log("Auth options received");

    const cred = await startAuthentication(optionsResponse.data);
    console.log("Authentication started");

    const verificationResponse = await webauthnApi.post(
      "/verify-authentication",
      { cred, email }
    );
    console.log("Verification response:", verificationResponse.data);

    // If verification is successful, call the BIOMETRIC login endpoint
    if (
      verificationResponse.data.verified &&
      verificationResponse.data.userId
    ) {
      console.log(
        "Calling biometric login endpoint with userId:",
        verificationResponse.data.userId
      );

      // Use axios directly, not webauthnApi
      const loginResponse = await axios.post(
        `${API_BASE_URL}/admin/auth/biometric-login`,
        {
          userId: verificationResponse.data.userId,
        }
      );

      console.log("Biometric login response:", loginResponse.data);
      return loginResponse.data;
    }

    console.log("Verification failed");
    return verificationResponse.data;
  } catch (error) {
    console.error(
      "Authentication failed:",
      error.response?.data || error.message
    );
    throw error;
  }
};
