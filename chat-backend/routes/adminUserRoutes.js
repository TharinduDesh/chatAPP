// chat-backend/routes/adminUserRoutes.js
const express = require("express");
const router = express.Router();
const { protectAdmin } = require("../middleware/adminAuthMiddleware");
const User = require("../models/User");
const ActivityLog = require("../models/ActivityLog");

// Helper function to create logs
const createLog = async (req, action, target, details = "") => {
  const log = new ActivityLog({
    adminId: req.admin._id,
    adminName: req.admin.fullName,
    action: action,
    targetType: "USER",
    targetId: target._id,
    targetName: target.fullName,
    details: details,
  });
  await log.save();
};

// Route for admins to get all users **
// @desc    Get all users for the admin dashboard with pagination
// @route   GET /api/admin/users
// @access  Private (Admin only)
/**
 * @route   GET /api/admin/users
 * @desc    Get all active users for the admin dashboard with pagination
 * @access  Private (Admin only)
 */
router.get("/", protectAdmin, async (req, res) => {
  try {
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 10;
    const skip = (page - 1) * limit;

    const query = {
      deletedAt: { $exists: false },

      $or: [
        { isBanned: { $exists: false } }, // The isBanned field doesn't exist (for old users)
        { isBanned: false }, // OR the isBanned field is explicitly false
      ],
    };

    const totalUsers = await User.countDocuments(query);
    const totalPages = Math.ceil(totalUsers / limit);

    const users = await User.find(query)
      .select("-password")
      .populate("createdBy", "fullName")
      .populate("deletedBy", "fullName")
      .populate("banDetails.bannedBy", "fullName")
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(limit);

    res.json({
      users,
      totalPages,
      currentPage: page,
    });
  } catch (error) {
    console.error("Admin fetch users error:", error);
    res.status(500).json({ message: "Server error fetching users." });
  }
});

// @desc    Add a new user
// @route   POST /api/admin/users
// @access  Private (Admin only)
router.post("/", protectAdmin, async (req, res) => {
  const { fullName, email, password } = req.body;
  const adminId = req.admin._id;

  // ... validation ...

  const newUser = new User({
    fullName,
    email,
    password,
    createdBy: adminId,
  });

  await newUser.save();
  await createLog(req, "CREATED_USER", newUser);
  res.status(201).json(newUser);
});

// @desc    Delete a user (soft delete)
// @route   DELETE /api/admin/users/:id
// @access  Private (Admin only)
router.delete("/:id", protectAdmin, async (req, res) => {
  const userId = req.params.id;
  const adminId = req.admin._id;

  const user = await User.findById(userId);

  if (!user) {
    return res.status(404).json({ message: "User not found" });
  }

  user.deletedAt = new Date();
  user.deletedBy = adminId;
  await user.save();
  await createLog(req, "DEACTIVATED_USER", user);

  res.json({ message: "User deleted successfully" });
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
    await createLog(req, "EDITED_USER", updatedUser);
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

//  Permanant delete

/**
 * @route   DELETE /api/admin/users/:id/permanent
 * @desc    Permanently delete a user and their data from the database
 * @access  Private (Admin only)
 */
router.delete("/:id/permanent", protectAdmin, async (req, res) => {
  try {
    const user = await User.findByIdAndDelete(req.params.id);

    if (!user) {
      return res.status(404).json({ message: "User not found" });
    }

    // IMPORTANT: In a larger application, you would also need to handle
    // all of the user's associated data here, such as deleting their
    // messages, removing them from conversations, etc. For now, this
    // will just delete the user document.

    await createLog(req, "PERMANENTLY_DELETED_USER", user);
    res.json({ message: "User permanently deleted successfully." });
  } catch (error) {
    console.error("Admin Permanent Delete User Error:", error);
    res
      .status(500)
      .json({ message: "Server error permanently deleting user." });
  }
});

// User ban

/**
 * @route   PUT /api/admin/users/:id/ban
 * @desc    Ban a user temporarily or permanently
 * @access  Private (Admin only)
 */
router.put("/:id/ban", protectAdmin, async (req, res) => {
  try {
    const { reason, durationInDays } = req.body;
    if (!reason) {
      return res
        .status(400)
        .json({ message: "A reason for the ban is required." });
    }

    const user = await User.findById(req.params.id);
    if (!user) {
      return res.status(404).json({ message: "User not found" });
    }

    // ... (logic to calculate expiresAt remains the same)
    let expiresAt = null;
    if (durationInDays && durationInDays > 0) {
      expiresAt = new Date();
      expiresAt.setDate(expiresAt.getDate() + parseInt(durationInDays, 10));
    }

    user.isBanned = true;
    user.banDetails = {
      reason: reason,
      bannedAt: new Date(),
      expiresAt: expiresAt,
      bannedBy: req.admin._id,
    };

    await user.save();

    const logDetails = `Reason: ${reason}. Duration: ${
      durationInDays > 0 ? `${durationInDays} days` : "Permanent"
    }`;
    await createLog(req, "BANNED_USER", user, logDetails);

    res.json(user);
  } catch (error) {
    console.error("Admin Ban User Error:", error);
    res.status(500).json({ message: "Server error banning user." });
  }
});

/**
 * @route   PUT /api/admin/users/:id/unban
 * @desc    Unban a user
 * @access  Private (Admin only)
 */
router.put("/:id/unban", protectAdmin, async (req, res) => {
  try {
    const user = await User.findById(req.params.id);
    if (!user) {
      return res.status(404).json({ message: "User not found" });
    }

    user.isBanned = false;
    user.banDetails = undefined; // Remove the ban details

    await user.save();
    await createLog(req, "UNBANNED_USER", user);
    res.json(user);
  } catch (error) {
    console.error("Admin Unban User Error:", error);
    res.status(500).json({ message: "Server error unbanning user." });
  }
});

// Route to get ONLY banned users **
router.get("/banned", protectAdmin, async (req, res) => {
  try {
    const bannedUsers = await User.find({ isBanned: true })
      .select("-password")
      .populate("banDetails.bannedBy", "fullName"); // Get the banning admin's name
    res.json(bannedUsers);
  } catch (error) {
    res.status(500).json({ message: "Server error fetching banned users." });
  }
});

// Route to get ONLY deactivated (soft-deleted) users **
router.get("/deleted", protectAdmin, async (req, res) => {
  try {
    const deletedUsers = await User.find({ deletedAt: { $exists: true } })
      .select("-password")
      .populate("deletedBy", "fullName"); // Get the deleting admin's name
    res.json(deletedUsers);
  } catch (error) {
    res.status(500).json({ message: "Server error fetching deleted users." });
  }
});

/**
 * @route   PUT /api/admin/users/:id/revert-delete
 * @desc    Restore a soft-deleted user account
 * @access  Private (Admin only)
 */
router.put("/:id/revert-delete", protectAdmin, async (req, res) => {
  try {
    const user = await User.findById(req.params.id);
    if (!user) {
      return res.status(404).json({ message: "User not found" });
    }

    // Clear the deletion fields to restore the user
    user.deletedAt = undefined;
    user.deletedBy = undefined;

    await user.save();
    await createLog(req, "RESTORED_USER", user);
    res.json({ message: "User account restored successfully.", user });
  } catch (error) {
    console.error("Admin Revert Deletion Error:", error);
    res.status(500).json({ message: "Server error restoring user." });
  }
});

/**
 * @route   GET /api/admin/users/export
 * @desc    Get all users for a CSV export (no pagination)
 * @access  Private (Admin only)
 */
router.get("/export", protectAdmin, async (req, res) => {
  try {
    const allUsers = await User.find({})
      .select("-password") // Exclude sensitive data
      .populate("createdBy", "fullName")
      .populate("deletedBy", "fullName")
      .populate("banDetails.bannedBy", "fullName")
      .sort({ createdAt: -1 });

    res.json(allUsers);
  } catch (error) {
    console.error("Admin Export Users Error:", error);
    res.status(500).json({ message: "Server error exporting users." });
  }
});

module.exports = router;
