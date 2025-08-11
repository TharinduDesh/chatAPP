// chat-backend/routes/adminConversationRoutes.js
const express = require("express");
const router = express.Router();
const { protectAdmin } = require("../middleware/adminAuthMiddleware");
const Conversation = require("../models/Conversation");
const Message = require("../models/Message");

/**
 * @route   GET /api/admin/conversations
 * @desc    Get all conversations for the admin dashboard
 * @access  Private (Admin only)
 */
router.get("/", protectAdmin, async (req, res) => {
  try {
    const conversations = await Conversation.find({})
      .populate("participants", "fullName email") // Get participant details
      .populate("lastMessage", "content sender") // Get a snippet of the last message
      .sort({ updatedAt: -1 }); // Show the most recently active first

    res.json(conversations);
  } catch (error) {
    console.error("Admin Fetch Conversations Error:", error);
    res.status(500).json({ message: "Server error fetching conversations." });
  }
});

/**
 * @route   GET /api/admin/conversations/:id/messages
 * @desc    Get all messages for a specific conversation
 * @access  Private (Admin only)
 */
router.get("/:id/messages", protectAdmin, async (req, res) => {
  try {
    const conversationId = req.params.id;
    const conversation = await Conversation.findById(conversationId);
    if (!conversation) {
      return res.status(404).json({ message: "Conversation not found." });
    }

    const messages = await Message.find({ conversationId: conversationId })
      .populate("sender", "fullName profilePictureUrl") // Populate sender's name and avatar
      .sort({ createdAt: "asc" }); // Sort oldest to newest for viewing

    res.json({ conversation, messages });
  } catch (error) {
    console.error("Admin Fetch Messages Error:", error);
    res.status(500).json({ message: "Server error fetching messages." });
  }
});

module.exports = router;
