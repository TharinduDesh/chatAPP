// chat-backend/routes/webauthnRoutes.js
const express = require("express");
const mongoose = require("mongoose");
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
      userID: Buffer.from(user._id.toString()),
      userName: user.email,
      attestationType: "none",
      excludeCredentials: userAuthenticators.map((auth) => ({
        id: Buffer.from(auth.credentialID, "base64url"), // Convert back to Buffer for exclusion
        type: "public-key",
        transports: auth.transports,
      })),
      authenticatorSelection: {
        residentKey: "required",
        userVerification: "required",
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

    const verification = await verifyRegistrationResponse({
      response: cred,
      expectedChallenge: challengeFromResponse,
      expectedOrigin: origin,
      expectedRPID: rpID,
      requireUserVerification: false,
    });

    if (verification.verified && verification.registrationInfo) {
      const registrationInfo = verification.registrationInfo;
      const credential = registrationInfo.credential;

      if (!credential || !credential.id || !credential.publicKey) {
        return res.status(500).json({
          message: "Verification failed due to missing credential data.",
        });
      }

      // Store the credential ID as a base64url string
      let credentialID;
      if (credential.id instanceof Uint8Array) {
        credentialID = Buffer.from(credential.id).toString("base64url");
      } else if (credential.id instanceof ArrayBuffer) {
        credentialID = Buffer.from(credential.id).toString("base64url");
      } else {
        credentialID = credential.id; // Assume it's already a string
      }

      // Store the public key as Buffer
      let credentialPublicKey;
      if (credential.publicKey instanceof Uint8Array) {
        credentialPublicKey = Buffer.from(credential.publicKey);
      } else if (credential.publicKey instanceof ArrayBuffer) {
        credentialPublicKey = Buffer.from(credential.publicKey);
      } else {
        credentialPublicKey = Buffer.from(credential.publicKey);
      }

      const counter = registrationInfo.counter || 0;

      console.log("Registration completed:", {
        credentialID,
        credentialPublicKeyLength: credentialPublicKey.length,
        counter,
      });

      const newAuthenticator = new Authenticator({
        userId: new mongoose.Types.ObjectId(userId),
        credentialID,
        credentialPublicKey,
        counter,
        transports: ["internal"],
      });

      await newAuthenticator.save();
      console.log("Authenticator saved successfully");
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

// ---------------- VERIFY AUTHENTICATION ----------------
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
    console.log("Credential rawId:", cred.rawId);

    const authenticator = await Authenticator.findOne({
      credentialID: incomingCredentialID,
    });

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

    // ✅ FIX: For v13+, use the exact format expected by the library
    const authenticatorDevice = {
      credentialID: authenticator.credentialID,
      credentialPublicKey: authenticator.credentialPublicKey,
      counter: authenticator.counter,
      transports: authenticator.transports || [],
    };

    console.log("Authenticator for verification:", {
      credentialID: authenticatorDevice.credentialID,
      credentialPublicKeyLength:
        authenticatorDevice.credentialPublicKey?.length,
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

      console.log("Verification completed:", {
        verified: verification.verified,
        authenticationInfo: verification.authenticationInfo
          ? {
              newCounter: verification.authenticationInfo.newCounter,
              userVerified: verification.authenticationInfo.userVerified,
            }
          : "undefined",
      });
    } catch (verifyError) {
      console.error("Verification function error:", verifyError);
      console.error("Error details:", {
        name: verifyError.name,
        message: verifyError.message,
        stack: verifyError.stack?.split("\n").slice(0, 5), // First 5 lines
      });

      // Clean up challenge before returning error
      await expectedChallenge.deleteOne();

      return res.status(400).json({
        message: "Authentication verification failed",
        error: verifyError.message,
        debug: {
          credentialID: authenticatorDevice.credentialID,
          counter: authenticatorDevice.counter,
          rpID: rpID,
          origin: origin,
        },
      });
    }

    // Handle successful verification
    if (verification.verified && verification.authenticationInfo) {
      // Update the counter
      authenticator.counter = verification.authenticationInfo.newCounter;
      await authenticator.save();

      console.log(
        "Authentication successful, counter updated to:",
        authenticator.counter
      );

      await expectedChallenge.deleteOne();
      res.json({
        verified: true,
        userId: authenticator.userId,
        newCounter: verification.authenticationInfo.newCounter,
      });
    } else {
      console.log("Verification failed or no authenticationInfo");
      await expectedChallenge.deleteOne();
      res.json({
        verified: false,
        message: "Authentication failed - verification returned false",
      });
    }
  } catch (error) {
    console.error("Error in /verify-authentication:", error);
    res.status(500).json({ message: "Server error", error: error.message });
  }
});

module.exports = router;
