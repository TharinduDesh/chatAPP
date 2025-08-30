const express = require("express");
const router = express.Router();
const mongoose = require("mongoose");
const {
  generateRegistrationOptions,
  verifyRegistrationResponse,
  generateAuthenticationOptions,
  verifyAuthenticationResponse,
} = require("@simplewebauthn/server");

const Admin = require("../models/Admin");
const Authenticator = require("../models/Authenticator");

// --- Registration Options ---
router.post("/register-options", async (req, res) => {
  try {
    const { email } = req.body;
    const admin = await Admin.findOne({ email });
    if (!admin) return res.status(404).json({ message: "Admin not found" });

    const options = generateRegistrationOptions({
      rpName: "SLT Chat App",
      rpID: process.env.RP_ID || "localhost",
      userID: admin._id.toString(),
      userName: admin.email,
      attestationType: "none",
      authenticatorSelection: {
        userVerification: "required",
      },
    });

    // ---- THIS LINE CAUSED ISSUES ----
    admin.currentChallenge = options.challenge;
    await admin.save();

    res.json(options);
  } catch (error) {
    console.error("Error in /register-options:", error);
    res
      .status(500)
      .json({ message: "Failed to generate registration options" });
  }
});

// --- Verify Registration ---
router.post("/verify-registration", async (req, res) => {
  try {
    const { userId, cred } = req.body;
    const admin = await Admin.findById(userId);
    if (!admin) return res.status(404).json({ message: "Admin not found" });

    const verification = await verifyRegistrationResponse({
      credential: cred,
      expectedChallenge: admin.currentChallenge,
      expectedOrigin: process.env.ORIGIN || "http://localhost:3000",
      expectedRPID: process.env.RP_ID || "localhost",
    });

    if (verification.verified) {
      const { credentialID, credentialPublicKey, counter, transports } =
        verification.registrationInfo;

      const newAuthenticator = new Authenticator({
        userId: admin._id,
        credentialID: Buffer.from(credentialID, "base64").toString("base64"),
        credentialPublicKey:
          Buffer.from(credentialPublicKey).toString("base64"),
        counter,
        transports,
      });

      await newAuthenticator.save();
    }

    res.json({ verified: verification.verified });
  } catch (error) {
    console.error("Error in /verify-registration:", error);
    res.status(500).json({ message: "Failed to verify registration" });
  }
});

// --- Authentication Options ---
router.post("/auth-options", async (req, res) => {
  try {
    const { email } = req.body;
    const admin = await Admin.findOne({ email });
    if (!admin) return res.status(404).json({ message: "Admin not found" });

    // ---- THE ROOT CAUSE ----
    // The query below was returning empty, so login always failed:
    const authenticators = await Authenticator.find({ userId: admin._id });
    if (!authenticators.length)
      return res.status(404).json({
        message: "Authenticator not found. Please register this device first.",
      });

    const options = generateAuthenticationOptions({
      allowCredentials: authenticators.map((a) => ({
        id: Buffer.from(a.credentialID, "base64"),
        type: "public-key",
        transports: a.transports,
      })),
      userVerification: "required",
      rpID: process.env.RP_ID || "localhost",
    });

    res.json(options);
  } catch (error) {
    console.error("Error in /auth-options:", error);
    res
      .status(500)
      .json({ message: "Failed to generate authentication options" });
  }
});

// --- Verify Authentication ---
router.post("/verify-authentication", async (req, res) => {
  try {
    const { cred } = req.body;

    const authenticator = await Authenticator.findOne({
      credentialID: Buffer.from(cred.id, "base64").toString("base64"),
    });
    if (!authenticator)
      return res.status(404).json({ message: "Authenticator not found." });

    const verification = await verifyAuthenticationResponse({
      credential: cred,
      expectedChallenge: cred.response.clientDataJSON.challenge,
      expectedOrigin: process.env.ORIGIN || "http://localhost:3000",
      expectedRPID: process.env.RP_ID || "localhost",
      authenticator: {
        credentialPublicKey: Buffer.from(
          authenticator.credentialPublicKey,
          "base64"
        ),
        counter: authenticator.counter,
      },
    });

    if (verification.verified) {
      authenticator.counter = verification.authenticationInfo.newCounter;
      await authenticator.save();
    }

    res.json({ verified: verification.verified });
  } catch (error) {
    console.error("Error in /verify-authentication:", error);
    res.status(500).json({ message: "Failed to verify authentication" });
  }
});

module.exports = router;
