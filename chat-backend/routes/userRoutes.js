// Purpose: Handles routes related to user profile, including avatar upload.
const expressUserRoutes = require("express");
const routerUserRoutes = expressUserRoutes.Router();
const { protect: protectUserRoutes } = require("../middleware/authMiddleware");
const {
  upload: uploadMiddleware,
  handleMulterError: handleMulterErrorMiddleware,
} = require("../middleware/uploadMiddleware"); // Import upload middleware
const UserModelUserRoutes = require("../models/User");
const path = require("path"); // For constructing file paths
const fs = require("fs"); // For deleting old avatars

// @desc    Get all users (excluding current user, for chat list)
// @route   GET /api/users
// @access  Private
routerUserRoutes.get("/", protectUserRoutes, async (req, res) => {
  try {
    const users = await UserModelUserRoutes.find({ _id: { $ne: req.user._id } }) // $ne selects documents where the value of the field is not equal to the specified value.
      .select("-password") // Exclude password
      .sort({ fullName: 1 }); // Sort by name
    res.json(users);
  } catch (error) {
    console.error("Get All Users Error:", error.message);
    res
      .status(500)
      .json({ message: "Server error fetching users.", error: error.message });
  }
});

// @desc    Get current user's profile
// @route   GET /api/users/me
// @access  Private
routerUserRoutes.get("/me", protectUserRoutes, async (req, res) => {
  try {
    if (req.user) {
      res.json(req.user);
    } else {
      res.status(404).json({ message: "User not found." });
    }
  } catch (error) {
    console.error("Get User Profile Error:", error.message);
    res
      .status(500)
      .json({ message: "Server Error getting profile.", error: error.message });
  }
});

// @desc    Update current user's profile (fullName, email)
// @route   PUT /api/users/me
// @access  Private
routerUserRoutes.put("/me", protectUserRoutes, async (req, res) => {
  const { fullName, email } = req.body;
  const userId = req.user._id;

  try {
    const user = await UserModelUserRoutes.findById(userId);
    if (!user) {
      return res.status(404).json({ message: "User not found for update." });
    }

    if (fullName !== undefined) user.fullName = fullName;
    if (email && email !== user.email) {
      const existingUserWithNewEmail = await UserModelUserRoutes.findOne({
        email: email,
      });
      if (
        existingUserWithNewEmail &&
        existingUserWithNewEmail._id.toString() !== userId.toString()
      ) {
        return res
          .status(400)
          .json({ message: "This email address is already in use." });
      }
      user.email = email;
    }

    const updatedUser = await user.save();
    res.json({
      _id: updatedUser._id,
      fullName: updatedUser.fullName,
      email: updatedUser.email,
      profilePictureUrl: updatedUser.profilePictureUrl,
      createdAt: updatedUser.createdAt,
      message: "Profile updated successfully.",
    });
  } catch (error) {
    console.error("Update User Profile Error:", error.message);
    if (error.name === "ValidationError") {
      const messages = Object.values(error.errors).map((val) => val.message);
      return res.status(400).json({ message: messages.join(". ") });
    }
    if (error.code === 11000 && error.keyPattern && error.keyPattern.email) {
      return res
        .status(400)
        .json({ message: "This email address is already registered." });
    }
    res
      .status(500)
      .json({
        message: "Server Error updating profile.",
        error: error.message,
      });
  }
});

// @desc    Upload or update user's profile picture
// @route   POST /api/users/me/avatar
// @access  Private
routerUserRoutes.post(
  "/me/avatar",
  protectUserRoutes, // Ensure user is authenticated
  uploadMiddleware.single("avatar"), // 'avatar' is the field name in the form-data
  handleMulterErrorMiddleware, // Use the custom error handler for multer
  async (req, res) => {
    try {
      if (!req.file) {
        return res
          .status(400)
          .json({ message: "No file uploaded. Please select an image." });
      }

      const user = await UserModelUserRoutes.findById(req.user._id);
      if (!user) {
        // Should not happen if protectUserRoutes works, but good practice to check
        return res.status(404).json({ message: "User not found." });
      }

      // Delete old avatar if it exists and is not a default one
      if (
        user.profilePictureUrl &&
        user.profilePictureUrl.startsWith("/uploads/profile_pictures/")
      ) {
        const oldAvatarFileName = path.basename(user.profilePictureUrl);
        const oldAvatarPath = path.join(
          __dirname,
          "..",
          "uploads",
          "profile_pictures",
          oldAvatarFileName
        );
        // Check if oldAvatarPath exists and delete
        if (fs.existsSync(oldAvatarPath)) {
          try {
            fs.unlinkSync(oldAvatarPath);
            console.log("Successfully deleted old avatar:", oldAvatarPath);
          } catch (unlinkErr) {
            console.error("Error deleting old avatar:", unlinkErr);
            // Not a fatal error, so we can continue
          }
        } else {
          console.log("Old avatar not found at path:", oldAvatarPath);
        }
      }

      // Construct the URL path for the new avatar.
      // req.file.filename is generated by multer's storage configuration.
      // This URL will be relative to the server's root.
      const newProfilePictureUrl = `/uploads/profile_pictures/${req.file.filename}`;
      user.profilePictureUrl = newProfilePictureUrl;
      await user.save();

      res.json({
        message: "Profile picture uploaded successfully!",
        profilePictureUrl: user.profilePictureUrl, // Send back the new URL
        user: {
          // Also send back the updated user object without password
          _id: user._id,
          fullName: user.fullName,
          email: user.email,
          profilePictureUrl: user.profilePictureUrl,
          createdAt: user.createdAt,
        },
      });
    } catch (error) {
      console.error("Avatar Upload Error:", error);
      // If it's a known multer error not caught by handleMulterError (should be rare)
      if (error instanceof multer.MulterError) {
        return res.status(400).json({ message: error.message });
      }
      // Generic server error
      res
        .status(500)
        .json({
          message: "Server error during avatar upload.",
          error: error.message,
        });
    }
  }
);

module.exports = routerUserRoutes;
