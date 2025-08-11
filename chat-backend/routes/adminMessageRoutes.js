// chat-backend/routes/adminMessageRoutes.js
const express = require("express");
const router = express.Router();
const { protectAdmin } = require("../middleware/adminAuthMiddleware");
const Message = require("../models/Message");
const ActivityLog = require("../models/ActivityLog");

/**
 * @route   DELETE /api/admin/messages/:id
 * @desc    Admin deletes a specific message from any conversation
 * @access  Private (Admin only)
 */
router.delete("/:id", protectAdmin, async (req, res) => {
  try {
    const message = await Message.findById(req.params.id);

    if (!message) {
      return res.status(404).json({ message: "Message not found." });
    }

    // To avoid breaking the chat flow, we'll "soft delete" the message
    // by overwriting its content. This is better than removing it completely.
    message.content = "This message was removed by an administrator.";
    message.fileUrl = ""; // Clear any associated files
    message.fileType = "";
    message.fileName = "";
    message.reactions = []; // Clear reactions
    // You could add a specific field like `isModerated: true` if needed.

    const savedMessage = await message.save();

    // Log this important moderation action
    const log = new ActivityLog({
      adminId: req.admin._id,
      adminName: req.admin.fullName,
      action: "DELETED_MESSAGE", // You should add this to your ActivityLog enum
      targetType: "MESSAGE",
      targetId: savedMessage._id,
      details: `Deleted a message in conversation: ${savedMessage.conversationId}`,
    });
    await log.save();

    res.json({ message: "Message successfully moderated." });
  } catch (error) {
    console.error("Admin Delete Message Error:", error);
    res.status(500).json({ message: "Server error while deleting message." });
  }
});

module.exports = router;
