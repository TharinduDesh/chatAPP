// Purpose: Handles user signup and login routes.
const expressAuthRoutes = require("express"); // Renamed
const routerAuthRoutes = expressAuthRoutes.Router(); // Renamed
const bcryptAuthRoutes = require("bcryptjs"); // Renamed
const jwtAuthRoutes = require("jsonwebtoken"); // Renamed
const UserAuthRoutes = require("../models/User"); // Path to User model
const JWT_SECRET_AUTH_ROUTES = process.env.JWT_SECRET;

// @desc    Register a new user
// @route   POST /api/auth/signup
// @access  Public
routerAuthRoutes.post("/signup", async (req, res) => {
  try {
    const { fullName, email, password } = req.body;

    // Basic validation
    if (!fullName || !email || !password) {
      return res
        .status(400)
        .json({ message: "Please provide full name, email, and password." });
    }
    // Password length validation is now in the schema, but can be kept here for early feedback
    if (password.length < 6) {
      return res
        .status(400)
        .json({ message: "Password must be at least 6 characters long." });
    }

    // Check if user already exists
    let existingUser = await UserAuthRoutes.findOne({ email });
    if (existingUser) {
      return res
        .status(400)
        .json({ message: "User with this email already exists." });
    }

    // Create new user (password will be hashed by pre-save hook in User model)
    const newUser = new UserAuthRoutes({
      fullName,
      email,
      password,
    });

    await newUser.save();

    // Generate JWT token
    const token = jwtAuthRoutes.sign(
      { userId: newUser._id, email: newUser.email }, // Payload
      JWT_SECRET_AUTH_ROUTES,
      { expiresIn: "7d" } // Token expiration
    );

    // Prepare user response (excluding password)
    const userResponse = {
      _id: newUser._id,
      fullName: newUser.fullName,
      email: newUser.email,
      profilePictureUrl: newUser.profilePictureUrl,
      createdAt: newUser.createdAt,
    };

    res.status(201).json({
      message: "User registered successfully!",
      token,
      user: userResponse,
    });
  } catch (error) {
    console.error("Signup Error:", error.message);
    // Handle Mongoose validation errors
    if (error.name === "ValidationError") {
      const messages = Object.values(error.errors).map((val) => val.message);
      return res.status(400).json({ message: messages.join(". ") });
    }
    res
      .status(500)
      .json({ message: "Server error during signup.", error: error.message });
  }
});

// @desc    Authenticate user & get token
// @route   POST /api/auth/login
// @access  Public
routerAuthRoutes.post("/login", async (req, res) => {
  try {
    const { email, password: passwordRequest } = req.body;

    if (!email || !passwordRequest) {
      return res
        .status(400)
        .json({ message: "Please provide email and password." });
    }

    const user = await UserAuthRoutes.findOne({ email });
    if (!user) {
      return res
        .status(401)
        .json({ message: "Invalid credentials. User not found." });
    }

    // *Check if the account is deactivated **
    if (user.deletedAt) {
      return res
        .status(403)
        .json({
          message:
            "This account has been deactivated and is scheduled for deletion.",
        });
    }

    // BAN CHECK LOGIC **
    if (user.isBanned) {
      const now = new Date();
      // Check if the ban has a specific expiry date and if it has passed
      if (
        user.banDetails &&
        user.banDetails.expiresAt &&
        user.banDetails.expiresAt < now
      ) {
        // Ban has expired, so we unban the user automatically
        user.isBanned = false;
        user.banDetails = undefined;
        await user.save();
      } else {
        // User is actively banned
        let banMessage = `This account has been banned. Reason: ${
          user.banDetails.reason || "Not specified"
        }.`;
        if (user.banDetails && user.banDetails.expiresAt) {
          banMessage += ` The ban will be lifted on ${new Date(
            user.banDetails.expiresAt
          ).toLocaleDateString()}.`;
        }
        return res.status(403).json({ message: banMessage }); // 403 Forbidden
      }
    }

    const isMatch = await user.comparePassword(passwordRequest);
    if (!isMatch) {
      return res
        .status(401)
        .json({ message: "Invalid credentials. Password incorrect." });
    }

    // ... (rest of the login logic remains the same: generate token and send response)
    const token = jwtAuthRoutes.sign(
      { userId: user._id, email: user.email },
      JWT_SECRET_AUTH_ROUTES,
      { expiresIn: "7d" }
    );
    const userResponse = {
      _id: user._id,
      fullName: user.fullName,
      email: user.email,
      profilePictureUrl: user.profilePictureUrl,
      createdAt: user.createdAt,
    };
    res
      .status(200)
      .json({ message: "Logged in successfully!", token, user: userResponse });
  } catch (error) {
    console.error("Login Error:", error.message);
    res
      .status(500)
      .json({ message: "Server error during login.", error: error.message });
  }
});

module.exports = routerAuthRoutes;
