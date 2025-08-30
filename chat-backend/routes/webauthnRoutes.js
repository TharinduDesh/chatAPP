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

// ------------------------
// [POST] /register-options
// ------------------------
router.post("/register-options", async (req, res) => {
  const { email } = req.body;

  try {
    const user = await Admin.findOne({ email });
    if (!user) return res.status(404).json({ message: "User not found" });

    const userAuthenticators = await Authenticator.find({ userId: user._id });

    const options = generateRegistrationOptions({
      rpName: "ChatApp Admin",
      rpID,
      userID: user._id.toString(), // Must be string
      userName: user.email,
      attestationType: "none",
      excludeCredentials: userAuthenticators.map((auth) => ({
        id: Buffer.from(auth.credentialID, "base64url"),
        type: "public-key",
        transports: auth.transports || ["internal"],
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

// ------------------------
// [POST] /verify-registration
// ------------------------
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
        userId: mongoose.Types.ObjectId(userId),
        credentialID: Buffer.from(credential.id).toString("base64url"),
        credentialPublicKey: Buffer.from(credential.publicKey).toString(
          "base64url"
        ),
        counter: registrationInfo.counter || 0,
        transports: cred.transports || ["internal"],
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

// ------------------------
// [POST] /auth-options
// ------------------------
router.post("/auth-options", async (req, res) => {
  try {
    const { email } = req.body;

    if (!email) return res.status(400).json({ message: "Email is required" });

    const admin = await Admin.findOne({ email });
    if (!admin) return res.status(404).json({ message: "Admin not found" });

    const authenticators = await Authenticator.find({ userId: admin._id });

    const allowCredentials = authenticators.map((auth) => {
      let credId = auth.credentialID;

      // If credentialID is stored as object, extract base64
      if (credId && credId.toString) {
        credId = credId.toString();
      }

      return {
        id: Buffer.from(credId, "base64url"),
        type: "public-key",
        transports: auth.transports || ["internal"],
      };
    });

    const options = generateAuthenticationOptions({
      userVerification: "preferred",
      allowCredentials: allowCredentials.length ? allowCredentials : undefined,
      rpID: process.env.RP_ID || "sltchatapp1.netlify.app",
    });

    if (!options || !options.challenge) {
      return res.status(500).json({ message: "Failed to generate challenge" });
    }

    // Save challenge as base64url string
    await Challenge.create({
      userId: admin._id,
      challenge: options.challenge.toString("base64url"),
    });

    res.json(options);
  } catch (error) {
    console.error("Error in /auth-options:", error);
    res
      .status(500)
      .json({ message: error.message || "Failed to generate auth options" });
  }
});

// ------------------------
// [POST] /verify-authentication
// ------------------------
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
      credentialID: cred.id ? Buffer.from(cred.id).toString("base64url") : null,
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
    console.error("Error in /verify-authentication:", error);
    res.status(500).json({ message: "Server error" });
  }
});

module.exports = router;
