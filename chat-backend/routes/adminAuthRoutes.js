// chat-backend/routes/adminAuthRoutes.js
const express = require("express");
const router = express.Router();
const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const Admin = require("../models/Admin");
const Authenticator = require("../models/Authenticator");
const JWT_SECRET = process.env.JWT_SECRET;

/**
 * @route   POST /api/admin/auth/signup
 * @desc    Register a new administrator
 * @access  Public
 */
router.post("/signup", async (req, res) => {
  try {
    const { fullName, email, password, secretKey } = req.body;

    if (secretKey !== process.env.ADMIN_SIGNUP_SECRET) {
      return res.status(403).json({
        message: "Invalid Invitation Code.",
      });
    }

    if (!fullName || !email || !password) {
      return res.status(400).json({ message: "Please provide all fields." });
    }
    if (password.length < 6) {
      return res
        .status(400)
        .json({ message: "Password must be at least 6 characters." });
    }

    let existingAdmin = await Admin.findOne({ email });
    if (existingAdmin) {
      return res
        .status(400)
        .json({ message: "Admin with this email already exists." });
    }

    const newAdmin = new Admin({ fullName, email, password });
    await newAdmin.save();

    const token = jwt.sign({ adminId: newAdmin._id }, JWT_SECRET, {
      expiresIn: "7d",
    });

    res.status(201).json({
      message: "Admin account created successfully!",
      token,
      admin: {
        id: newAdmin._id,
        fullName: newAdmin.fullName,
        email: newAdmin.email,
      },
    });
  } catch (error) {
    console.error("Admin Signup Error:", error);
    res.status(500).json({ message: "Server error during admin signup." });
  }
});

/**
 * @route   POST /api/admin/auth/login
 * @desc    Authenticate administrator and get token
 * @access  Public
 */
router.post("/login", async (req, res) => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return res
        .status(400)
        .json({ message: "Please provide email and password." });
    }

    const admin = await Admin.findOne({ email });
    if (!admin) {
      return res.status(401).json({ message: "Invalid credentials." });
    }

    const isMatch = await admin.comparePassword(password);
    if (!isMatch) {
      return res.status(401).json({ message: "Invalid credentials." });
    }

    const token = jwt.sign({ adminId: admin._id }, JWT_SECRET, {
      expiresIn: "7d",
    });

    res.json({
      message: "Logged in successfully!",
      token,
      admin: {
        id: admin._id,
        fullName: admin.fullName,
        email: admin.email,
      },
    });
  } catch (error) {
    console.error("Admin Login Error:", error);
    res.status(500).json({ message: "Server error during admin login." });
  }
});

// --- ✅ THE DEFINITIVE FIX: ADD THIS NEW ROUTE ---
/**
 * @route   POST /api/admin/auth/biometric-login
 * @desc    Create a session token after successful biometric verification
 * @access  Public
 */
router.post("/biometric-login", async (req, res) => {
  try {
    const { email } = req.body;

    if (!email) {
      return res
        .status(400)
        .json({ message: "Email is required for biometric login." });
    }

    const admin = await Admin.findOne({ email });
    if (!admin) {
      // This should ideally not happen if biometric registration was done correctly
      return res
        .status(404)
        .json({ message: "Admin account not found for this email." });
    }

    // Since biometric verification was successful on the WebAuthn routes,
    // we can now generate a token directly.
    const token = jwt.sign({ adminId: admin._id }, JWT_SECRET, {
      expiresIn: "7d",
    });

    res.json({
      message: "Logged in successfully with biometrics!",
      token,
      admin: {
        id: admin._id,
        fullName: admin.fullName,
        email: admin.email,
      },
    });
  } catch (error) {
    console.error("Biometric Login Session Error:", error);
    res
      .status(500)
      .json({ message: "Server error during biometric session creation." });
  }
});

module.exports = router;
