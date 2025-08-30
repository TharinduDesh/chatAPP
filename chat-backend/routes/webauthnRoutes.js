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
      userID: Buffer.from(user._id.toString()), // Buffer for userID
      userName: user.email,
      attestationType: "none",
      excludeCredentials: userAuthenticators.map((auth) => ({
        id: auth.credentialID, // Use Buffer directly
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

      // DEBUG: Log what we're getting from the registration
      console.log("Raw credential.id:", credential.id);
      console.log("Raw credential.id type:", typeof credential.id);

      if (credential.id instanceof Uint8Array) {
        console.log("Credential.id is Uint8Array");
      } else if (credential.id instanceof ArrayBuffer) {
        console.log("Credential.id is ArrayBuffer");
      }

      // Store the credential ID exactly as received (as Buffer)
      // The credential.id should be an ArrayBuffer or Uint8Array
      let credentialIDBuffer;
      if (credential.id instanceof ArrayBuffer) {
        credentialIDBuffer = Buffer.from(credential.id);
      } else if (credential.id instanceof Uint8Array) {
        credentialIDBuffer = Buffer.from(credential.id.buffer);
      } else {
        // If it's already a Buffer or something else
        credentialIDBuffer = Buffer.from(credential.id);
      }

      console.log(
        "Storing credentialID as:",
        credentialIDBuffer.toString("base64")
      );

      const credentialPublicKey = Buffer.from(credential.publicKey);
      const counter = registrationInfo.counter || 0;
      const transports = cred.response.transports || ["internal"];

      const newAuthenticator = new Authenticator({
        userId: new mongoose.Types.ObjectId(userId),
        credentialID: credentialIDBuffer,
        credentialPublicKey,
        counter,
        transports,
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
    const clientDataJSON = Buffer.from(
      cred.response.clientDataJSON,
      "base64"
    ).toString("utf8");
    const challengeFromResponse = JSON.parse(clientDataJSON).challenge;

    const expectedChallenge = await Challenge.findOne({
      challenge: challengeFromResponse,
    });
    if (!expectedChallenge) {
      return res
        .status(400)
        .json({ message: "Challenge not found or expired" });
    }

    // Convert incoming credential ID to Buffer for comparison
    let incomingCredentialIDBuffer;
    if (typeof cred.id === "string") {
      // If it's a base64url string, convert to Buffer
      incomingCredentialIDBuffer = Buffer.from(cred.id, "base64url");
    } else if (cred.id instanceof ArrayBuffer) {
      // If it's an ArrayBuffer, convert to Buffer
      incomingCredentialIDBuffer = Buffer.from(cred.id);
    } else if (cred.id instanceof Uint8Array) {
      // If it's a Uint8Array, convert to Buffer
      incomingCredentialIDBuffer = Buffer.from(cred.id.buffer);
    } else {
      console.error("Unknown cred.id type:", typeof cred.id, cred.id);
      return res.status(400).json({ message: "Invalid credential ID format" });
    }

    console.log(
      "Incoming credentialID (Buffer):",
      incomingCredentialIDBuffer.toString("base64")
    );

    // Find authenticator by comparing Buffer objects
    const authenticator = await Authenticator.findOne({
      credentialID: incomingCredentialIDBuffer,
    });

    if (!authenticator) {
      // Debug: log all stored credential IDs
      const allAuthenticators = await Authenticator.find({});
      console.log(
        "All stored authenticators:",
        allAuthenticators.map((auth) => ({
          credentialID: auth.credentialID.toString("base64"),
          userId: auth.userId,
        }))
      );

      return res.status(404).json({
        message: "Authenticator not found. Please register this device first.",
      });
    }

    console.log(
      "Found authenticator with credentialID:",
      authenticator.credentialID.toString("base64")
    );

    // Verify authentication - use the Buffer objects directly
    const verification = await verifyAuthenticationResponse({
      response: cred,
      expectedChallenge: challengeFromResponse,
      expectedOrigin: origin,
      expectedRPID: rpID,
      authenticator: {
        credentialID: authenticator.credentialID, // Use Buffer directly
        credentialPublicKey: authenticator.credentialPublicKey, // Use Buffer directly
        counter: authenticator.counter,
        transports: authenticator.transports,
      },
      requireUserVerification: false,
    });

    if (verification.verified) {
      authenticator.counter = verification.authenticationInfo.newCounter;
      await authenticator.save();
    }

    await expectedChallenge.deleteOne();
    res.json({ verified: verification.verified });
  } catch (error) {
    console.error("Error in /verify-authentication:", error);
    res.status(500).json({ message: "Server error", error: error.message });
  }
});

module.exports = router;
