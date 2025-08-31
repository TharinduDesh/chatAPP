// chat-backend/routes/adminAuthRoutes.js
const express = require("express");
const router = express.Router();
const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const Admin = require("../models/Admin"); // Assuming you have an Admin model
const Authenticator = require("../models/Authenticator"); // ✅ Add this import for biometric login
const JWT_SECRET = process.env.JWT_SECRET;

/**
 * @route   POST /api/admin/auth/signup
 * @desc    Register a new administrator
 * @access  Public (or could be restricted to existing admins)
 */
router.post("/signup", async (req, res) => {
  try {
    const { fullName, email, password, secretKey } = req.body;

    // First, check if the provided secret key matches the one in our .env file.
    if (secretKey !== process.env.ADMIN_SIGNUP_SECRET) {
      return res.status(403).json({
        message:
          "Invalid Invitation Code. Not authorized to create an admin account.",
      });
    }

    // Basic validation
    if (!fullName || !email || !password) {
      return res
        .status(400)
        .json({ message: "Please provide full name, email, and password." });
    }
    if (password.length < 6) {
      return res
        .status(400)
        .json({ message: "Password must be at least 6 characters long." });
    }

    // Check if admin already exists
    let existingAdmin = await Admin.findOne({ email });
    if (existingAdmin) {
      return res
        .status(400)
        .json({ message: "Admin with this email already exists." });
    }

    // Create a new admin instance
    const newAdmin = new Admin({
      fullName,
      email,
      password, // Password will be hashed by the pre-save hook in the Admin model
    });

    // Save the new admin to the database
    await newAdmin.save();

    // Generate JWT for the new admin
    const token = jwt.sign(
      { userId: newAdmin._id, email: newAdmin.email },
      JWT_SECRET,
      { expiresIn: "7d" } // Token expires in 7 days
    );

    // Prepare the admin data to be sent in the response (excluding the password)
    const adminResponse = {
      _id: newAdmin._id,
      fullName: newAdmin.fullName,
      email: newAdmin.email,
      createdAt: newAdmin.createdAt,
    };

    res.status(201).json({
      message: "Admin registered successfully!",
      token,
      admin: adminResponse,
    });
  } catch (error) {
    console.error("Admin Signup Error:", error.message);
    if (error.name === "ValidationError") {
      const messages = Object.values(error.errors).map((val) => val.message);
      return res.status(400).json({ message: messages.join(". ") });
    }
    res.status(500).json({
      message: "Server error during admin signup.",
      error: error.message,
    });
  }
});

/**
 * @route   POST /api/admin/auth/login
 * @desc    Authenticate an admin and get a token
 * @access  Public
 */
router.post("/login", async (req, res) => {
  try {
    const { email, password } = req.body;

    // Basic validation
    if (!email || !password) {
      return res
        .status(400)
        .json({ message: "Please provide email and password." });
    }

    // Find admin by email
    const admin = await Admin.findOne({ email });
    if (!admin) {
      return res
        .status(401)
        .json({ message: "Invalid credentials. Admin not found." });
    }

    // Compare the provided password with the hashed password in the database
    const isMatch = await admin.comparePassword(password);
    if (!isMatch) {
      return res
        .status(401)
        .json({ message: "Invalid credentials. Password incorrect." });
    }

    // If credentials are correct, generate a new JWT
    const token = jwt.sign(
      { userId: admin._id, email: admin.email },
      JWT_SECRET,
      { expiresIn: "7d" }
    );

    // Prepare the admin data for the response
    const adminResponse = {
      _id: admin._id,
      fullName: admin.fullName,
      email: admin.email,
      createdAt: admin.createdAt,
    };

    res.status(200).json({
      message: "Logged in successfully!",
      token,
      admin: adminResponse,
    });
  } catch (error) {
    console.error("Admin Login Error:", error.message);
    res.status(500).json({
      message: "Server error during admin login.",
      error: error.message,
    });
  }
});

/**
 * @route   POST /api/admin/auth/biometric-login
 * @desc    Create session after successful biometric authentication
 * @access  Public (but relies on prior WebAuthn verification)
 */
router.post("/biometric-login", async (req, res) => {
  const { email } = req.body;

  try {
    // Basic validation
    if (!email) {
      return res
        .status(400)
        .json({ message: "Email is required for biometric login." });
    }

    // Find the admin by email
    const admin = await Admin.findOne({ email });
    if (!admin) {
      return res.status(404).json({ message: "Admin not found" });
    }

    // Check if this admin has registered biometric authenticators
    const hasAuthenticators = await Authenticator.findOne({
      userId: admin._id,
    });
    if (!hasAuthenticators) {
      return res.status(400).json({
        message:
          "No biometric authenticators found for this account. Please register biometrics first.",
      });
    }

    // Generate JWT token (same as regular login)
    const token = jwt.sign(
      { userId: admin._id, email: admin.email },
      JWT_SECRET,
      { expiresIn: "7d" } // Same expiry as regular login
    );

    // Prepare the admin data for the response (same structure as regular login)
    const adminResponse = {
      _id: admin._id,
      fullName: admin.fullName,
      email: admin.email,
      createdAt: admin.createdAt,
    };

    console.log("Biometric login successful for:", admin.email);

    // Return the same response structure as regular login
    res.json({
      message: "Biometric login successful!",
      token,
      admin: adminResponse,
    });
  } catch (error) {
    console.error("Error in biometric login:", error);
    res.status(500).json({
      message: "Server error during biometric login.",
      error: error.message,
    });
  }
});

/**
 * @route   GET /api/admin/auth/me
 * @desc    Get current logged-in admin's profile
 * @access  Private (requires admin token)
 */
const { protectAdmin } = require("../middleware/adminAuthMiddleware"); // Make sure to import this

router.get("/me", protectAdmin, async (req, res) => {
  // The protectAdmin middleware already attaches the admin user to req.admin
  if (req.admin) {
    res.json(req.admin);
  } else {
    res.status(404).json({ message: "Admin not found." });
  }
});

/**
 * @route   PUT /api/admin/auth/me
 * @desc    Update current logged-in admin's profile
 * @access  Private (requires admin token)
 */
router.put("/me", protectAdmin, async (req, res) => {
  try {
    const admin = await Admin.findById(req.admin._id);

    if (!admin) {
      return res.status(404).json({ message: "Admin not found" });
    }

    // Update fields if they are provided
    admin.fullName = req.body.fullName || admin.fullName;
    admin.email = req.body.email || admin.email;

    const updatedAdmin = await admin.save();

    res.json({
      _id: updatedAdmin._id,
      fullName: updatedAdmin.fullName,
      email: updatedAdmin.email,
      createdAt: updatedAdmin.createdAt,
    });
  } catch (error) {
    console.error("Admin Profile Update Error:", error);
    res.status(500).json({ message: "Error updating admin profile" });
  }
});

/**
 * @route   PUT /api/admin/auth/change-password
 * @desc    Change admin's password
 * @access  Private (requires admin token)
 */
router.put("/change-password", protectAdmin, async (req, res) => {
  const { currentPassword, newPassword } = req.body;

  if (!currentPassword || !newPassword) {
    return res
      .status(400)
      .json({ message: "Please provide current and new passwords." });
  }

  if (newPassword.length < 6) {
    return res
      .status(400)
      .json({ message: "New password must be at least 6 characters long." });
  }

  try {
    const admin = await Admin.findById(req.admin._id);

    // Check if the provided current password is correct
    const isMatch = await admin.comparePassword(currentPassword);
    if (!isMatch) {
      return res.status(401).json({ message: "Incorrect current password." });
    }

    // Set the new password (the pre-save hook in Admin.js will hash it)
    admin.password = newPassword;
    await admin.save();

    res.json({ message: "Password updated successfully." });
  } catch (error) {
    console.error("Admin Password Change Error:", error);
    res.status(500).json({ message: "Server error changing password." });
  }
});

// Update user details

/**
 * @route   PUT /api/admin/users/:id
 * @desc    Update a user's details by Admin
 * @access  Private (Admin only)
 */
router.put("/:id", protectAdmin, async (req, res) => {
  try {
    const { fullName, email } = req.body;
    const user = await User.findById(req.params.id);

    if (!user) {
      return res.status(404).json({ message: "User not found" });
    }

    user.fullName = fullName || user.fullName;
    user.email = email || user.email;

    const updatedUser = await user.save();
    res.json(updatedUser);
  } catch (error) {
    // Handle potential duplicate email error
    if (error.code === 11000) {
      return res
        .status(400)
        .json({ message: "This email address is already in use." });
    }
    console.error("Admin Update User Error:", error);
    res.status(500).json({ message: "Server error updating user." });
  }
});

module.exports = router;
