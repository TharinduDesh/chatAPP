// chat-backend/routes/webauthnRoutes.js
const express = require("express");
const mongoose = require("mongoose");
const jwt = require("jsonwebtoken");
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
const rpID = "chatappadmin.netlify.app";
const origin = `https://chatappadmin.netlify.app`;

// ---------------- VERIFY AUTHENTICATION (FINAL, ROBUST VERSION) ----------------
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
    }).populate("userId");

    if (!authenticator) {
      await expectedChallenge.deleteOne();
      return res.status(404).json({
        message: "Authenticator not found. Please register this device first.",
      });
    }

    const adminUser = authenticator.userId;

    if (!adminUser) {
      console.error(
        "CRITICAL: Authenticator found, but the linked Admin user is missing.",
        { authenticatorId: authenticator._id }
      );
      await expectedChallenge.deleteOne();
      return res
        .status(404)
        .json({
          message: "Could not find the user associated with this passkey.",
        });
    }

    const authenticatorDevice = {
      credentialID: authenticator.credentialID,
      credentialPublicKey: authenticator.credentialPublicKey,
      counter: authenticator.counter,
      transports: authenticator.transports || ["internal"],
    };

    const verification = await verifyAuthenticationResponse({
      response: cred,
      expectedChallenge: challengeFromResponse,
      expectedOrigin: origin,
      expectedRPID: rpID,
      authenticator: authenticatorDevice,
      requireUserVerification: false,
    });

    await expectedChallenge.deleteOne();

    if (verification.verified) {
      authenticator.counter = verification.authenticationInfo.newCounter;
      await authenticator.save();

      const token = jwt.sign(
        { id: adminUser._id, role: "admin" },
        process.env.JWT_SECRET,
        { expiresIn: "1d" }
      );

      // This ensures the admin object sent to the frontend is clean and
      // matches the structure of a normal password login response.
      const adminDataForFrontend = {
        id: adminUser._id,
        fullName: adminUser.fullName,
        email: adminUser.email,
      };

      res.status(200).json({
        message: "Biometric login successful!",
        token,
        admin: adminDataForFrontend, // Send the clean, consistent object
      });
    } else {
      res.status(401).json({
        verified: false,
        message: "Authentication verification failed.",
      });
    }
  } catch (error) {
    console.error("Error in /verify-authentication:", error);
    res.status(500).json({ message: "Server error", error: error.message });
  }
});

// --- Other routes like /register-options, /verify-registration, and /auth-options ---
// (No changes are needed for these routes)
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
      userDisplayName: user.fullName || user.email,
      attestationType: "none",
      excludeCredentials: userAuthenticators.map((auth) => ({
        id: auth.credentialID,
        type: "public-key",
        transports: auth.transports,
      })),
      authenticatorSelection: {
        residentKey: "preferred",
        userVerification: "preferred",
      },
    });
    await Challenge.create({ challenge: options.challenge });
    res.json(options);
  } catch (error) {
    console.error("Error in /register-options:", error);
    res.status(500).json({ message: "Server error", error: error.message });
  }
});

router.post("/verify-registration", async (req, res) => {
  const { userId, cred } = req.body;
  try {
    const user = await Admin.findById(userId);
    if (!user) return res.status(404).json({ message: "User not found" });

    const expectedChallengeDoc = await Challenge.findOne({
      challenge: JSON.parse(
        Buffer.from(cred.response.clientDataJSON, "base64").toString("utf8")
      ).challenge,
    });
    if (!expectedChallengeDoc)
      return res.status(400).json({ message: "Challenge not found." });
    const expectedChallenge = expectedChallengeDoc.challenge;

    const verification = await verifyRegistrationResponse({
      response: cred,
      expectedChallenge,
      expectedOrigin: origin,
      expectedRPID: rpID,
    });

    if (verification.verified && verification.registrationInfo) {
      const { credentialID, credentialPublicKey, counter } =
        verification.registrationInfo;
      const newAuthenticator = new Authenticator({
        userId: userId,
        credentialID: Buffer.from(credentialID).toString("base64url"),
        credentialPublicKey: Buffer.from(credentialPublicKey),
        counter,
        transports: cred.response.transports || [],
      });
      await newAuthenticator.save();
    }
    await expectedChallengeDoc.deleteOne();
    res.json({ verified: verification.verified });
  } catch (error) {
    console.error("Error in /verify-registration:", error);
    res.status(500).json({ message: "Server error", error: error.message });
  }
});

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

module.exports = router;
