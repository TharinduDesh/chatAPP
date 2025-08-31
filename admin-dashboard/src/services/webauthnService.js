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

// Create a separate axios instance for auth endpoints
const authApi = axios.create({
  baseURL: API_BASE_URL, // Use the base URL without /api/webauthn
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
export const loginWithBiometrics = async (email) => {
  try {
    console.log("🔍 WEBAUTHN DEBUG: Starting biometric login for:", email);

    // 1. Get authentication options
    const optionsResponse = await webauthnApi.post("/auth-options", { email });
    console.log(
      "🔍 WEBAUTHN DEBUG: Auth options received:",
      optionsResponse.data
    );

    // 2. Start browser authentication
    const cred = await startAuthentication(optionsResponse.data);
    console.log("🔍 WEBAUTHN DEBUG: Browser authentication completed");

    // 3. Verify authentication with server
    const verificationResponse = await webauthnApi.post(
      "/verify-authentication",
      { cred, email }
    );
    console.log(
      "🔍 WEBAUTHN DEBUG: Verification response:",
      verificationResponse.data
    );

    // 4. If verification is successful, call the biometric login endpoint
    if (
      verificationResponse.data.verified &&
      verificationResponse.data.userId
    ) {
      console.log(
        "🔍 WEBAUTHN DEBUG: Calling biometric login endpoint with userId:",
        verificationResponse.data.userId
      );

      // Use the authApi instance for the biometric login endpoint
      const loginResponse = await authApi.post("/admin/auth/biometric-login", {
        userId: verificationResponse.data.userId,
      });

      console.log(
        "🔍 WEBAUTHN DEBUG: Biometric login response:",
        loginResponse.data
      );
      return loginResponse.data;
    }

    console.log("🔍 WEBAUTHN DEBUG: Verification failed");
    return verificationResponse.data;
  } catch (error) {
    console.error("🔍 WEBAUTHN DEBUG: Authentication failed:", {
      message: error.message,
      response: error.response?.data,
      status: error.response?.status,
      url: error.config?.url,
    });

    // Check if it's a network error or specific API error
    if (error.response) {
      // The request was made and the server responded with a status code
      console.error(
        "🔍 WEBAUTHN DEBUG: Server responded with error:",
        error.response.status
      );
      console.error("🔍 WEBAUTHN DEBUG: Error data:", error.response.data);
    } else if (error.request) {
      // The request was made but no response was received
      console.error("🔍 WEBAUTHN DEBUG: No response received:", error.request);
    } else {
      // Something happened in setting up the request
      console.error("🔍 WEBAUTHN DEBUG: Request setup error:", error.message);
    }

    throw error;
  }
};
