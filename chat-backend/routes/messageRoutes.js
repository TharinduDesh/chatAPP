// Purpose: API endpoints for fetching messages.
const expressMsgRoutes = require("express");
const routerMsgRoutes = expressMsgRoutes.Router();
const { protect: protectMsgRoutes } = require("../middleware/authMiddleware");
const MessageModelMsgRoutes = require("../models/Message");
const ConversationModelMsgRoutes = require("../models/Conversation"); // To verify user is part of convo

// @desc    Get all messages for a specific conversation
// @route   GET /api/messages/:conversationId
// @access  Private
routerMsgRoutes.get("/:conversationId", protectMsgRoutes, async (req, res) => {
  const { conversationId } = req.params;
  const currentUserId = req.user._id;

  try {
    // Optional: Verify the current user is part of the conversation
    const conversation = await ConversationModelMsgRoutes.findById(
      conversationId
    );
    if (!conversation) {
      return res.status(404).json({ message: "Conversation not found." });
    }
    if (!conversation.participants.includes(currentUserId)) {
      return res
        .status(403)
        .json({ message: "You are not authorized to view these messages." });
    }

    const messages = await MessageModelMsgRoutes.find({
      conversationId: conversationId,
    })
      .populate("sender", "fullName email profilePictureUrl") // Populate sender details for each message
      .sort({ createdAt: 1 }); // Fetch messages in chronological order (older first)

    res.json(messages);
  } catch (error) {
    console.error(
      `Get Messages for Conversation ${conversationId} Error:`,
      error
    );
    res
      .status(500)
      .json({
        message: "Server error fetching messages.",
        error: error.message,
      });
  }
});

module.exports = routerMsgRoutes;
