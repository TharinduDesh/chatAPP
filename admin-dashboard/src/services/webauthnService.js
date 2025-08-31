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

// ---------------------------------
// GET AUTHENTICATION OPTIONS
// ---------------------------------
export const getAuthenticationOptions = async () => {
  try {
    // We don't need email for this part of the flow as per backend logic
    const optionsResponse = await webauthnApi.post("/auth-options");
    console.log("🔍 WEBAUTHN DEBUG: Got authentication options");
    return optionsResponse.data;
  } catch (error) {
    console.error("🔍 WEBAUTHN DEBUG: Failed to get auth options:", error);
    throw error;
  }
};

// ---------------------------------
// VERIFY AUTHENTICATION
// ---------------------------------
export const verifyAuthentication = async (cred) => {
  try {
    const verificationResponse = await webauthnApi.post(
      "/verify-authentication",
      { cred }
    );
    console.log(
      "🔍 WEBAUTHN DEBUG: Authentication verification response:",
      verificationResponse.data
    );
    return verificationResponse.data;
  } catch (error) {
    console.error("🔍 WEBAUTHN DEBUG: Failed to verify authentication:", error);
    throw error;
  }
};

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

    // 1️⃣ Get authentication options from server
    const optionsResponse = await webauthnApi.post("/auth-options", { email });
    const options = optionsResponse.data;
    console.log("🔍 WEBAUTHN DEBUG: Got authentication options");

    // 2️⃣ Start authentication in browser
    const cred = await startAuthentication(options);
    console.log("🔍 WEBAUTHN DEBUG: Browser authentication completed");

    // 3️⃣ Send authentication response to server
    const verificationResponse = await webauthnApi.post(
      "/verify-authentication",
      {
        cred,
      }
    );
    console.log(
      "🔍 WEBAUTHN DEBUG: Authentication verification response:",
      verificationResponse.data
    );

    return verificationResponse.data;
  } catch (error) {
    console.error("🔍 WEBAUTHN DEBUG: Biometric login failed:", error);
    throw error;
  }
};
