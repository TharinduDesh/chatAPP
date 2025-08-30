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

// [POST] /api/webauthn/register-options
router.post("/register-options", async (req, res) => {
  const { email } = req.body;

  try {
    const user = await Admin.findOne({ email });
    if (!user) {
      return res.status(404).json({ message: "User not found" });
    }

    const userAuthenticators = await Authenticator.find({ userId: user._id });

    const options = await generateRegistrationOptions({
      rpName: "ChatApp Admin",
      rpID,
      userID: Buffer.from(user._id.toString()), // ✅ FIX: must be Buffer
      userName: user.email,
      attestationType: "none",
      excludeCredentials: userAuthenticators.map((auth) => ({
        id: auth.credentialID, // already Buffer in your fixed schema
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
    console.error(`Error in /register-options:`, error);
    res.status(500).json({ message: "Server error" });
  }
});

// [POST] /api/webauthn/verify-registration
router.post("/verify-registration", async (req, res) => {
  const { userId, cred } = req.body;

  try {
    // Decode clientDataJSON
    const clientDataJSON = Buffer.from(
      cred.response.clientDataJSON,
      "base64"
    ).toString("utf8");
    const challengeFromResponse = JSON.parse(clientDataJSON).challenge;

    // Find user
    const user = await Admin.findById(userId);
    if (!user) {
      return res.status(404).json({ message: "User not found" });
    }

    // Find expected challenge
    const expectedChallenge = await Challenge.findOne({
      challenge: challengeFromResponse,
    });
    if (!expectedChallenge) {
      return res
        .status(400)
        .json({ message: "Challenge not found or expired" });
    }

    // Verify registration response
    const verification = await verifyRegistrationResponse({
      response: cred,
      expectedChallenge: challengeFromResponse,
      expectedOrigin: origin,
      expectedRPID: rpID,
      requireUserVerification: false,
    });

    if (verification.verified && verification.registrationInfo) {
      const registrationInfo = verification.registrationInfo;

      // ✅ Extract credential from registrationInfo
      const credential = registrationInfo.credential;
      if (!credential || !credential.id || !credential.publicKey) {
        return res.status(500).json({
          message: "Verification failed due to missing credential data.",
        });
      }

      // Convert to base64url for MongoDB storage
      const credentialID = Buffer.from(credential.id).toString("base64url");
      const credentialPublicKey = Buffer.from(credential.publicKey).toString(
        "base64url"
      );
      const counter = credential.counter || 0;
      const transports = credential.transports || ["internal"];

      // Save authenticator
      const newAuthenticator = new Authenticator({
        userId: new mongoose.Types.ObjectId(userId),
        credentialID,
        credentialPublicKey,
        counter,
        transports,
      });

      await newAuthenticator.save();
    } else {
      return res
        .status(400)
        .json({ message: "Could not verify authenticator." });
    }

    // Delete challenge after verification
    await expectedChallenge.deleteOne();
    res.json({ verified: verification.verified });
  } catch (error) {
    console.error("Error in /verify-registration:", error);
    res.status(500).json({ message: "Server error", error: error.message });
  }
});

/**
 * [POST] /api/webauthn/auth-options
 */
router.post("/auth-options", async (req, res) => {
  try {
    const options = await generateAuthenticationOptions({
      rpID,
      userVerification: "preferred",
    });

    await Challenge.create({ challenge: options.challenge });
    res.json(options);
  } catch (error) {
    console.error(`Error in /auth-options:`, error);
    res.status(500).json({ message: "Server error" });
  }
});

// [POST] /api/webauthn/verify-authentication
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

    const authenticator = await Authenticator.findOne({
      credentialID: cred.id, // use directly
    });

    if (!authenticator) {
      return res.status(404).json({
        message: "Authenticator not found. Please register this device first.",
      });
    }

    const verification = await verifyAuthenticationResponse({
      response: cred,
      expectedChallenge: challengeFromResponse,
      expectedOrigin: origin,
      expectedRPID: rpID,
      authenticator: {
        credentialID: Buffer.from(authenticator.credentialID, "base64url"),
        credentialPublicKey: Buffer.from(
          authenticator.credentialPublicKey,
          "base64url"
        ),
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
    console.error(`Error in /verify-authentication:`, error);
    res.status(500).json({ message: "Server error" });
  }
});

module.exports = router;
