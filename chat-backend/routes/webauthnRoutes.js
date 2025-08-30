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

// Make sure these match your Netlify deployment exactly

const rpID = "sltchatapp1.netlify.app";
const origin = `https://sltchatapp1.netlify.app`;

// [POST] /api/webauthn/register-options
router.post("/register-options", async (req, res) => {
  const { email } = req.body;
  console.log(
    `[${new Date().toISOString()}] Received register-options request for email: ${email}`
  );

  try {
    const user = await Admin.findOne({ email });
    if (!user) {
      console.error("User not found for email:", email);
      return res.status(404).json({ message: "User not found" });
    }

    const userAuthenticators = await Authenticator.find({ userId: user._id });

    const options = await generateRegistrationOptions({
      rpName: "ChatApp Admin", // You can give your app a name here
      rpID,
      userID: user._id,
      userName: user.email,
      attestationType: "none",
      excludeCredentials: userAuthenticators.map((auth) => ({
        id: isoUint8Array.fromBase64(auth.credentialID),
        type: "public-key",
        transports: auth.transports,
      })),
      authenticatorSelection: {
        authenticatorAttachment: "platform",
        residentKey: "preferred",
        userVerification: "required",
      },
    });

    console.log(
      `[${new Date().toISOString()}] Generated challenge: ${options.challenge}`
    );
    await Challenge.create({ challenge: options.challenge });
    console.log(`[${new Date().toISOString()}] Saved challenge to DB.`);

    res.json(options);
  } catch (error) {
    console.error(
      `[${new Date().toISOString()}] Error in /register-options:`,
      error
    );
    res.status(500).json({ message: "Server error" });
  }
});

// [POST] /api/webauthn/verify-registration
router.post("/verify-registration", async (req, res) => {
  const { userId, cred } = req.body;
  const challengeFromResponse = cred.response.clientDataJSON.challenge;
  console.log(
    `[${new Date().toISOString()}] Received verify-registration request for challenge: ${challengeFromResponse}`
  );

  try {
    const user = await Admin.findById(userId);
    if (!user) {
      console.error("Verification failed: User not found with ID:", userId);
      return res.status(404).json({ message: "User not found" });
    }

    const expectedChallenge = await Challenge.findOne({
      challenge: challengeFromResponse,
    });
    if (!expectedChallenge) {
      console.error(
        `[${new Date().toISOString()}] Verification failed: Challenge not found in DB.`
      );
      return res
        .status(400)
        .json({ message: "Challenge not found or expired" });
    }
    console.log(
      `[${new Date().toISOString()}] Found matching challenge in DB. Created at: ${expectedChallenge.createdAt.toISOString()}`
    );

    const verification = await verifyRegistrationResponse({
      response: cred,
      expectedChallenge: challengeFromResponse,
      expectedOrigin: origin,
      expectedRPID: rpID,
      requireUserVerification: false,
    });

    if (verification.verified) {
      console.log(`[${new Date().toISOString()}] Verification successful!`);
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
      console.log(
        `[${new Date().toISOString()}] Saved new authenticator for user: ${userId}`
      );
    } else {
      console.error(`[${new Date().toISOString()}] Verification failed.`);
    }

    await expectedChallenge.deleteOne();
    console.log(
      `[${new Date().toISOString()}] Deleted used challenge from DB.`
    );

    res.json({ verified: verification.verified });
  } catch (error) {
    // This is the corrected line
    console.error(
      `[${new Date().toISOString()}] Error in /verify-registration:`,
      error
    );
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
        transports: authentitor.transports,
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
