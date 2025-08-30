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

// Make sure these match your deployment
const rpID = "sltchatapp1.netlify.app";
const origin = `https://${rpID}`;

// ------------------- REGISTER OPTIONS -------------------
router.post("/register-options", async (req, res) => {
  const { email } = req.body;

  try {
    const user = await Admin.findOne({ email: email.toLowerCase() });
    if (!user) return res.status(404).json({ message: "User not found" });

    const userAuthenticators = await Authenticator.find({ userId: user._id });

    const options = generateRegistrationOptions({
      rpName: "ChatApp Admin",
      rpID,
      userID: user._id.toString(), // must be string
      userName: user.email,
      attestationType: "none",
      excludeCredentials: userAuthenticators.map((auth) => ({
        id: auth.credentialID, // base64url string
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

// ------------------- VERIFY REGISTRATION -------------------
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

      // Save authenticator with base64url strings
      const newAuthenticator = new Authenticator({
        userId: mongoose.Types.ObjectId(userId),
        credentialID: Buffer.from(credential.id).toString("base64url"),
        credentialPublicKey: Buffer.from(credential.publicKey).toString(
          "base64url"
        ),
        counter: registrationInfo.counter || 0,
        transports: credential.transports || ["internal"],
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

// ------------------- AUTH OPTIONS -------------------
router.post("/auth-options", async (req, res) => {
  const { email } = req.body;

  try {
    const user = await Admin.findOne({ email: email.toLowerCase() });
    if (!user) return res.status(404).json({ message: "User not found" });

    const authenticators = await Authenticator.find({ userId: user._id });

    const options = generateAuthenticationOptions({
      allowCredentials: authenticators.map((auth) => ({
        id: auth.credentialID,
        type: "public-key",
        transports: auth.transports,
      })),
      userVerification: "preferred",
      rpID,
    });

    await Challenge.create({ challenge: options.challenge });
    res.json(options);
  } catch (error) {
    console.error("Error in /auth-options:", error);
    res.status(500).json({ message: "Server error" });
  }
});

// ------------------- VERIFY AUTHENTICATION -------------------
router.post("/verify-authentication", async (req, res) => {
  const { email, cred } = req.body;

  try {
    const user = await Admin.findOne({ email: email.toLowerCase() });
    if (!user) return res.status(404).json({ message: "User not found" });

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
      userId: user._id,
      credentialID: cred.id, // match base64url string
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
        credentialID: authenticator.credentialID,
        credentialPublicKey: authenticator.credentialPublicKey,
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
    res.status(500).json({ message: "Server error" });
  }
});

module.exports = router;
