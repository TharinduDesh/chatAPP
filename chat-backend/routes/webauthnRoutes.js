// chat-backend/routes/webauthnRoutes.js
const express = require("express");
const mongoose = require("mongoose");
const jwt = require("jsonwebtoken"); // <-- ADDED: Import for creating session tokens
const {
  generateRegistrationOptions,
  verifyRegistrationResponse,
  generateAuthenticationOptions,
  verifyAuthenticationResponse,
} = require("@simplewebauthn/server");
const Admin = require("../models/Admin");
const Authenticator = require("../models/Authenticator");
const Challenge = require("../models/Challenge");

const router = express.Router();

// Make sure these match your Netlify deployment exactly
const rpID = "sltchatapp1.netlify.app";
const origin = `https://sltchatapp1.netlify.app`;

// ---------------- REGISTER OPTIONS ----------------
router.post("/register-options", async (req, res) => {
  const { email } = req.body;

  try {
    const user = await Admin.findOne({ email });
    if (!user) return res.status(404).json({ message: "User not found" });

    const userAuthenticators = await Authenticator.find({ userId: user._id });

    const options = await generateRegistrationOptions({
      rpName: "ChatApp Admin",
      rpID,
      userID: Buffer.from(user._id.toString()), // Convert to Buffer for v10
      userName: user.email,
      userDisplayName: user.fullName || user.email, // Add display name
      attestationType: "none",
      excludeCredentials: userAuthenticators.map((auth) => ({
        id: auth.credentialID, // Keep as string for v10
        type: "public-key",
        transports: auth.transports,
      })),
      authenticatorSelection: {
        residentKey: "preferred", // Changed from "required" for better compatibility
        userVerification: "preferred", // Changed from "required"
      },
    });

    await Challenge.create({ challenge: options.challenge });
    res.json(options);
  } catch (error) {
    console.error("Error in /register-options:", error);
    res.status(500).json({ message: "Server error", error: error.message });
  }
});

// ---------------- VERIFY REGISTRATION ----------------
router.post("/verify-registration", async (req, res) => {
  const { userId, cred } = req.body;

  try {
    const clientDataJSON = Buffer.from(
      cred.response.clientDataJSON,
      "base64"
    ).toString("utf8");
    const challengeFromResponse = JSON.parse(clientDataJSON).challenge;

    const user = await Admin.findById(userId);
    if (!user) return res.status(404).json({ message: "User not found" });

    const expectedChallenge = await Challenge.findOne({
      challenge: challengeFromResponse,
    });
    if (!expectedChallenge)
      return res
        .status(400)
        .json({ message: "Challenge not found or expired" });

    console.log("Registration verification input:", {
      hasCredential: !!cred,
      hasResponse: !!cred.response,
      hasAttestationObject: !!cred.response?.attestationObject,
      hasClientDataJSON: !!cred.response?.clientDataJSON,
      credentialId: cred.id,
    });

    const verification = await verifyRegistrationResponse({
      response: cred,
      expectedChallenge: challengeFromResponse,
      expectedOrigin: origin,
      expectedRPID: rpID,
      requireUserVerification: false,
    });

    console.log("Registration verification result:", {
      verified: verification.verified,
      hasRegistrationInfo: !!verification.registrationInfo,
    });

    if (verification.verified && verification.registrationInfo) {
      const { credentialID, credentialPublicKey, counter } =
        verification.registrationInfo;

      console.log("Registration info received:", {
        hasCredentialID: !!credentialID,
        hasCredentialPublicKey: !!credentialPublicKey,
        counter: counter,
        credentialIDType: typeof credentialID,
        credentialPublicKeyType: typeof credentialPublicKey,
      });

      // For v10, handle the credential data properly
      let finalCredentialID;
      if (typeof credentialID === "string") {
        finalCredentialID = credentialID;
      } else if (credentialID instanceof Buffer) {
        finalCredentialID = credentialID.toString("base64url");
      } else if (credentialID instanceof Uint8Array) {
        finalCredentialID = Buffer.from(credentialID).toString("base64url");
      } else {
        console.error("Unexpected credentialID type:", typeof credentialID);
        return res.status(500).json({
          message: "Verification failed due to unexpected credential format.",
        });
      }

      // Handle credentialPublicKey
      let finalCredentialPublicKey;
      if (credentialPublicKey instanceof Buffer) {
        finalCredentialPublicKey = credentialPublicKey;
      } else if (credentialPublicKey instanceof Uint8Array) {
        finalCredentialPublicKey = Buffer.from(credentialPublicKey);
      } else {
        console.error(
          "Unexpected credentialPublicKey type:",
          typeof credentialPublicKey
        );
        return res.status(500).json({
          message: "Verification failed due to unexpected public key format.",
        });
      }

      console.log("Final credential data:", {
        credentialID: finalCredentialID,
        credentialPublicKeyLength: finalCredentialPublicKey.length,
        counter: counter || 0,
      });

      const newAuthenticator = new Authenticator({
        userId: new mongoose.Types.ObjectId(userId),
        credentialID: finalCredentialID,
        credentialPublicKey: finalCredentialPublicKey,
        counter: counter || 0,
        transports: ["internal"], // Default transport for v10
      });

      await newAuthenticator.save();
      console.log("Authenticator saved successfully for v10");
    } else {
      return res
        .status(400)
        .json({ message: "Could not verify authenticator." });
    }

    await expectedChallenge.deleteOne();
    res.json({ verified: verification.verified });
  } catch (error) {
    console.error("Error in /verify-registration:", error);
    res.status(500).json({ message: "Server error", error: error.message });
  }
});

// ---------------- AUTH OPTIONS ----------------
router.post("/auth-options", async (req, res) => {
  try {
    const options = await generateAuthenticationOptions({
      rpID,
      userVerification: "preferred",
    });

    await Challenge.create({ challenge: options.challenge });
    res.json(options);
  } catch (error) {
    console.error("Error in /auth-options:", error);
    res.status(500).json({ message: "Server error", error: error.message });
  }
});

// ---------------- VERIFY AUTHENTICATION (Compatible with v10.x) ----------------
router.post("/verify-authentication", async (req, res) => {
  const { cred } = req.body;

  try {
    // Extract challenge from the client data
    const clientDataJSON = Buffer.from(
      cred.response.clientDataJSON,
      "base64"
    ).toString("utf8");
    const challengeFromResponse = JSON.parse(clientDataJSON).challenge;

    // Find and validate the challenge
    const expectedChallenge = await Challenge.findOne({
      challenge: challengeFromResponse,
    });
    if (!expectedChallenge) {
      return res
        .status(400)
        .json({ message: "Challenge not found or expired" });
    }

    // Find the authenticator using the credential ID
    const incomingCredentialID = cred.id;
    console.log("Incoming credentialID:", incomingCredentialID);

    // --- START: MODIFICATION ---
    // Use .populate('userId') to fetch the admin data along with the authenticator
    const authenticator = await Authenticator.findOne({
      credentialID: incomingCredentialID,
    }).populate("userId");
    // --- END: MODIFICATION ---

    if (!authenticator) {
      await expectedChallenge.deleteOne();
      return res.status(404).json({
        message: "Authenticator not found. Please register this device first.",
      });
    }

    console.log("Found authenticator:", {
      credentialID: authenticator.credentialID,
      counter: authenticator.counter,
      hasCredentialPublicKey: !!authenticator.credentialPublicKey,
    });

    // ✅ CORRECT FORMAT for @simplewebauthn/server v10.x
    const authenticatorDevice = {
      credentialID: authenticator.credentialID, // Keep as base64url string for v10
      credentialPublicKey: authenticator.credentialPublicKey, // Keep as Buffer
      counter: authenticator.counter,
      transports: authenticator.transports || ["internal"],
    };

    console.log("Authenticator prepared for v10 verification:", {
      credentialID: authenticatorDevice.credentialID,
      credentialIDType: typeof authenticatorDevice.credentialID,
      credentialPublicKeyLength: authenticatorDevice.credentialPublicKey.length,
      credentialPublicKeyType: typeof authenticatorDevice.credentialPublicKey,
      counter: authenticatorDevice.counter,
      transports: authenticatorDevice.transports,
    });

    // Verify the authentication response
    let verification;
    try {
      verification = await verifyAuthenticationResponse({
        response: cred,
        expectedChallenge: challengeFromResponse,
        expectedOrigin: origin,
        expectedRPID: rpID,
        authenticator: authenticatorDevice,
        requireUserVerification: false,
      });

      console.log("V10 Verification result:", {
        verified: verification.verified,
        authenticationInfo: verification.authenticationInfo
          ? {
              newCounter: verification.authenticationInfo.newCounter,
              userVerified: verification.authenticationInfo.userVerified,
            }
          : null,
      });
    } catch (verifyError) {
      console.error("V10 Verification error:", verifyError);
      await expectedChallenge.deleteOne();

      return res.status(400).json({
        message: "Authentication verification failed",
        error: verifyError.message,
      });
    }

    // Clean up the challenge now that it has been used
    await expectedChallenge.deleteOne();

    // Handle the verification result
    if (verification.verified) {
      // Update counter if authenticationInfo is available
      if (verification.authenticationInfo) {
        authenticator.counter = verification.authenticationInfo.newCounter;
        await authenticator.save();
        console.log("Counter updated to:", authenticator.counter);
      }

      // --- START: MODIFIED LOGIC ---
      // The admin user is now attached to authenticator.userId because we used .populate()
      const adminUser = authenticator.userId;

      if (!adminUser) {
        return res
          .status(404)
          .json({ message: "Authenticated admin user not found." });
      }

      // Generate a JWT for the admin session
      const token = jwt.sign(
        { id: adminUser._id, role: "admin" },
        process.env.JWT_SECRET, // Ensure you have JWT_SECRET in your .env file
        { expiresIn: "1d" } // Token is valid for 1 day
      );

      // Send the token and user data back to the frontend
      res.status(200).json({
        message: "Biometric login successful!",
        token,
        admin: {
          id: adminUser._id,
          username: adminUser.username,
          email: adminUser.email,
          fullName: adminUser.fullName,
        },
      });
      // --- END: MODIFIED LOGIC ---
    } else {
      res.status(401).json({
        verified: false,
        message: "Authentication verification failed.",
      });
    }
  } catch (error) {
    console.error("Error in /verify-authentication:", error);
    res.status(500).json({ message: "Server error", error: error.message });
  }
});

module.exports = router;
