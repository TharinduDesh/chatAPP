// chat-backend/routes/webauthnRoutes.js
const express = require("express");
const {
  generateRegistrationOptions,
  verifyRegistrationResponse,
  generateAuthenticationOptions,
  verifyAuthenticationResponse,
} = require("@simplewebauthn/server");
const { isoUint8Array } = require("@simplewebauthn/server/helpers");
const Admin = require("../models/Admin");
const Authenticator = require("../models/Authenticator");
const Challenge = require("../models/Challenge");

const router = express.Router();

const rpName = "Your App Name";
const rpID = "localhost";
const origin = `http://${rpID}:3000`;

// [POST] /api/webauthn/register-options
router.post("/register-options", async (req, res) => {
  // --- CHANGE: Expect 'email' instead of 'username' ---
  const { email } = req.body;

  try {
    // --- CHANGE: Find user by 'email' ---
    const user = await Admin.findOne({ email });
    if (!user) {
      return res.status(404).json({ message: "User not found" });
    }

    const userAuthenticators = await Authenticator.find({ userId: user.id });

    const options = await generateRegistrationOptions({
      rpName,
      rpID,
      userID: user._id,
      userName: user.email, // Use email as the userName for WebAuthn
      attestationType: "none",
      excludeCredentials: userAuthenticators.map((auth) => ({
        id: isoUint8Array.fromBase64(auth.credentialID),
        type: "public-key",
        transports: auth.transports,
      })),
      authenticatorSelection: {
        residentKey: "required",
        userVerification: "preferred",
      },
    });

    await Challenge.create({ challenge: options.challenge });
    res.json(options);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: "Server error" });
  }
});

// [POST] /api/webauthn/verify-registration
// ... (This route remains the same, no changes needed here)
router.post("/verify-registration", async (req, res) => {
  const { userId, cred } = req.body;

  try {
    const user = await Admin.findById(userId);
    if (!user) {
      return res.status(404).json({ message: "User not found" });
    }

    const expectedChallenge = await Challenge.findOne({
      challenge: cred.response.clientDataJSON.challenge,
    });
    if (!expectedChallenge) {
      return res
        .status(400)
        .json({ message: "Challenge not found or expired" });
    }

    const verification = await verifyRegistrationResponse({
      response: cred,
      expectedChallenge: cred.response.clientDataJSON.challenge,
      expectedOrigin: origin,
      expectedRPID: rpID,
      requireUserVerification: false,
    });

    if (verification.verified) {
      const { registrationInfo } = verification;
      const newAuthenticator = new Authenticator({
        userId,
        credentialID: isoUint8Array.toBase64(registrationInfo.credentialID),
        credentialPublicKey: isoUint8Array.toBase64(
          registrationInfo.credentialPublicKey
        ),
        counter: registrationInfo.counter,
        transports: cred.response.transports,
      });
      await newAuthenticator.save();
    }

    await expectedChallenge.deleteOne();
    res.json({ verified: verification.verified });
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: "Server error" });
  }
});

// [POST] /api/webauthn/auth-options
router.post("/auth-options", async (req, res) => {
  // --- CHANGE: Expect 'email' instead of 'username' ---
  const { email } = req.body;
  if (!email) {
    return res.status(400).json({ message: "Email is required" });
  }

  try {
    // --- CHANGE: Find user by 'email' ---
    const user = await Admin.findOne({ email });
    if (!user) {
      return res.status(404).json({ message: "User not found" });
    }

    const userAuthenticators = await Authenticator.find({ userId: user.id });

    const options = await generateAuthenticationOptions({
      rpID,
      allowCredentials: userAuthenticators.map((auth) => ({
        id: isoUint8Array.fromBase64(auth.credentialID),
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
// ... (This route also remains the same)
router.post("/verify-authentication", async (req, res) => {
  const { cred } = req.body;

  try {
    const expectedChallenge = await Challenge.findOne({
      challenge: cred.response.clientDataJSON.challenge,
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
      expectedChallenge: cred.response.clientDataJSON.challenge,
      expectedOrigin: origin,
      expectedRPID: rpID,
      authenticator: {
        credentialID: isoUint8Array.fromBase64(authenticator.credentialID),
        credentialPublicKey: isoUint8Array.fromBase64(
          authenticator.credentialPublicKey
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
