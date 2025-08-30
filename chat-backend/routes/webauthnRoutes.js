// chat-backend/routes/webauthnRoutes.js
const express = require("express");
const {
  generateRegistrationOptions,
  verifyRegistrationResponse,
  generateAuthenticationOptions,
  verifyAuthenticationResponse,
} = require("@simplewebauthn/server");
// We no longer need the isoUint8Array helper
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
      userID: user._id,
      userName: user.email,
      attestationType: "none",
      excludeCredentials: userAuthenticators.map((auth) => ({
        // FIX: Use Node.js Buffer to convert from Base64URL
        id: Buffer.from(auth.credentialID, "base64url"),
        type: "public-key",
        transports: auth.transports,
      })),
      authenticatorSelection: {
        authenticatorAttachment: "platform",
        residentKey: "preferred",
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
    const clientDataJSON = Buffer.from(
      cred.response.clientDataJSON,
      "base64"
    ).toString("utf8");
    const challengeFromResponse = JSON.parse(clientDataJSON).challenge;

    const user = await Admin.findById(userId);
    if (!user) {
      return res.status(404).json({ message: "User not found" });
    }

    const expectedChallenge = await Challenge.findOne({
      challenge: challengeFromResponse,
    });
    if (!expectedChallenge) {
      return res
        .status(400)
        .json({ message: "Challenge not found or expired" });
    }

    const verification = await verifyRegistrationResponse({
      response: cred,
      expectedChallenge: challengeFromResponse,
      expectedOrigin: origin,
      expectedRPID: rpID,
      requireUserVerification: false,
    });

    if (verification.verified) {
      const { registrationInfo } = verification;
      const newAuthenticator = new Authenticator({
        userId,
        // FIX: Use Node.js Buffer to convert to Base64URL
        credentialID: Buffer.from(registrationInfo.credentialID).toString(
          "base64url"
        ),
        credentialPublicKey: Buffer.from(
          registrationInfo.credentialPublicKey
        ).toString("base64url"),
        counter: registrationInfo.counter,
        transports: cred.response.transports,
      });
      await newAuthenticator.save();
    }

    await expectedChallenge.deleteOne();
    res.json({ verified: verification.verified });
  } catch (error) {
    console.error(`Error in /verify-registration:`, error);
    res.status(500).json({ message: "Server error" });
  }
});

// [POST] /api/webauthn/auth-options
router.post("/auth-options", async (req, res) => {
  const { email } = req.body;
  if (!email) {
    return res.status(400).json({ message: "Email is required" });
  }

  try {
    const user = await Admin.findOne({ email });
    if (!user) {
      return res.status(404).json({ message: "User not found" });
    }

    const userAuthenticators = await Authenticator.find({ userId: user._id });

    const options = await generateAuthenticationOptions({
      rpID,
      allowCredentials: userAuthenticators.map((auth) => ({
        // FIX: Use Node.js Buffer to convert from Base64URL
        id: Buffer.from(auth.credentialID, "base64url"),
        type: "public-key",
        transports: auth.transports,
      })),
      userVerification: "preferred",
    });

    await Challenge.create({ challenge: options.challenge });
    res.json(options);
  } catch (error) {
    console.error(error);
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
      credentialID: cred.id,
    });
    if (!authenticator) {
      return res.status(404).json({ message: "Authenticator not found" });
    }

    const verification = await verifyAuthenticationResponse({
      response: cred,
      expectedChallenge: challengeFromResponse,
      expectedOrigin: origin,
      expectedRPID: rpID,
      authenticator: {
        // FIX: Use Node.js Buffer to convert from Base64URL
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
    console.error(error);
    res.status(500).json({ message: "Server error" });
  }
});

module.exports = router;
