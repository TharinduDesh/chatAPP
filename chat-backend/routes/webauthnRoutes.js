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

      // Store the credential ID exactly as it comes from the response
      // The credential.id should be a base64url string
      const credentialID = credential.id;
      const credentialPublicKey = Buffer.from(credential.publicKey);
      const counter = registrationInfo.counter || 0;

      console.log("Registration - credentialID:", credentialID);
      console.log(
        "Registration - credentialPublicKey length:",
        credentialPublicKey.length
      );
      console.log("Registration - counter:", counter);

      const newAuthenticator = new Authenticator({
        userId: new mongoose.Types.ObjectId(userId),
        credentialID,
        credentialPublicKey,
        counter,
        transports: ["internal"], // Use default value
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

    // Use the credential ID exactly as it comes
    const incomingCredentialID = cred.id;
    console.log("Incoming credentialID:", incomingCredentialID);

    // Find authenticator by comparing strings directly
    const authenticator = await Authenticator.findOne({
      credentialID: incomingCredentialID,
    });

    if (!authenticator) {
      return res.status(404).json({
        message: "Authenticator not found. Please register this device first.",
      });
    }

    console.log(
      "Found authenticator with credentialID:",
      authenticator.credentialID
    );

    // Create the authenticator object in the exact format expected by the library
    const authenticatorForVerification = {
      credentialID: Buffer.from(authenticator.credentialID, "base64url"),
      credentialPublicKey: authenticator.credentialPublicKey,
      counter: parseInt(authenticator.counter) || 0,
    };

    console.log("Authenticator for verification:", {
      credentialID:
        authenticatorForVerification.credentialID.toString("base64"),
      credentialPublicKey:
        authenticatorForVerification.credentialPublicKey
          .toString("base64")
          .substring(0, 50) + "...",
      counter: authenticatorForVerification.counter,
    });

    // Verify authentication
    const verification = await verifyAuthenticationResponse({
      response: cred,
      expectedChallenge: challengeFromResponse,
      expectedOrigin: origin,
      expectedRPID: rpID,
      authenticator: authenticatorForVerification,
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
