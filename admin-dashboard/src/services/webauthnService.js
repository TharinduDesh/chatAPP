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

// ------------------- Utility -------------------
// Convert ArrayBuffer to Base64URL
function arrayBufferToBase64URL(buffer) {
  let binary = "";
  const bytes = new Uint8Array(buffer);
  for (let i = 0; i < bytes.byteLength; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

// ------------------- REGISTER BIOMETRICS -------------------
export const registerBiometrics = async (email, userId) => {
  try {
    // 1️⃣ Get registration options from backend
    const optionsResponse = await webauthnApi.post("/register-options", {
      email,
    });

    // 2️⃣ Start registration with authenticator
    const cred = await startRegistration(optionsResponse.data);

    // 3️⃣ Convert id/rawId to Base64URL
    const credId = arrayBufferToBase64URL(cred.rawId || cred.id);

    // 4️⃣ Send to backend
    const verificationResponse = await webauthnApi.post(
      "/verify-registration",
      {
        userId,
        cred: {
          ...cred,
          id: credId,
          rawId: credId,
        },
      }
    );

    return verificationResponse.data;
  } catch (error) {
    console.error("Registration failed:", error);
    throw error;
  }
};

// ------------------- LOGIN WITH BIOMETRICS -------------------
export const loginWithBiometrics = async (email) => {
  try {
    // 1️⃣ Get authentication options from backend
    const optionsResponse = await webauthnApi.post("/auth-options", { email });

    // 2️⃣ Start authentication
    const cred = await startAuthentication(optionsResponse.data);

    // 3️⃣ Convert id/rawId to Base64URL
    const credId = arrayBufferToBase64URL(cred.rawId || cred.id);

    // 4️⃣ Send to backend
    const verificationResponse = await webauthnApi.post(
      "/verify-authentication",
      {
        cred: {
          ...cred,
          id: credId,
          rawId: credId,
        },
      }
    );

    return verificationResponse.data;
  } catch (error) {
    console.error("Authentication failed:", error);
    throw error;
  }
};
