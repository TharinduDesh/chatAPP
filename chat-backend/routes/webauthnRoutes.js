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
const origin = `https://${rpID}`;

// ---------------------
// [POST] /register-options
// ---------------------
router.post("/register-options", async (req, res) => {
  const { email } = req.body;

  try {
    const user = await Admin.findOne({ email });
    if (!user) return res.status(404).json({ message: "User not found" });

    const userAuthenticators = await Authenticator.find({ userId: user._id });

    const options = generateRegistrationOptions({
      rpName: "ChatApp Admin",
      rpID,
      userID: user._id, // now supports ObjectId
      userName: user.email,
      attestationType: "none",
      excludeCredentials: userAuthenticators.map((auth) => ({
        id: Buffer.from(auth.credentialID, "base64url"),
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
    res.status(500).json({ message: "Server error" });
  }
});

// ---------------------
// [POST] /verify-registration
// ---------------------
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
      const { registrationInfo } = verification;
      const { credential } = registrationInfo;

      if (!credential || !credential.id || !credential.publicKey) {
        return res.status(500).json({
          message: "Verification failed due to missing credential data.",
        });
      }

      const newAuthenticator = new Authenticator({
        userId: new mongoose.Types.ObjectId(userId),
        credentialID: Buffer.from(credential.id).toString("base64url"),
        credentialPublicKey: Buffer.from(credential.publicKey).toString(
          "base64url"
        ),
        counter: registrationInfo.counter || 0,
        transports: registrationInfo.transports || ["internal"],
      });
      await newAuthenticator.save();
    } else {
      return res
        .status(400)
        .json({ message: "Could not verify authenticator." });
    }

    await expectedChallenge.deleteOne();
    res.json({ verified: verification.verified });
  } catch (error) {
    console.error("Error in /verify-registration:", error);
    res.status(500).json({ message: "Server error" });
  }
});

// ---------------------
// [POST] /auth-options
// ---------------------
router.post("/auth-options", async (req, res) => {
  try {
    const options = generateAuthenticationOptions({
      rpID,
      userVerification: "preferred",
    });

    // Convert challenge to base64url string if needed
    const challengeStr =
      typeof options.challenge === "string"
        ? options.challenge
        : Buffer.from(options.challenge).toString("base64url");

    // Save challenge to DB
    await Challenge.create({ challenge: challengeStr });

    // Replace the challenge in options with string version for browser
    const optionsForBrowser = { ...options, challenge: challengeStr };

    res.json(optionsForBrowser);
  } catch (error) {
    console.error(`Error in /auth-options:`, error);
    res.status(500).json({ message: "Server error" });
  }
});

// ---------------------
// [POST] /verify-authentication
// ---------------------
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
    if (!expectedChallenge)
      return res
        .status(400)
        .json({ message: "Challenge not found or expired" });

    const authenticator = await Authenticator.findOne({
      credentialID: Buffer.from(cred.id).toString("base64url"),
    });
    if (!authenticator)
      return res.status(404).json({
        message: "Authenticator not found. Please register this device first.",
      });

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
        transports: authenticator.transports || ["internal"],
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
    res.status(500).json({ message: "Server error" });
  }
});

module.exports = router;
