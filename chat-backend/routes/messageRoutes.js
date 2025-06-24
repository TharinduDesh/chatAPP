// Purpose: API endpoints for fetching messages and uploading message-related content.
const expressMsgRoutes = require("express");
const routerMsgRoutes = expressMsgRoutes.Router();
const { protect: protectMsgRoutes } = require("../middleware/authMiddleware");
const MessageModelMsgRoutes = require("../models/Message");
const ConversationModelMsgRoutes = require("../models/Conversation"); // To verify user is part of convo

// Import the uploader and error handler for chat files
const {
  uploadChatFile,
  handleMulterError,
} = require("../middleware/uploadMiddleware");

// @desc    Upload a file to be sent in a chat
// @route   POST /api/messages/upload-file
// @access  Private
routerMsgRoutes.post(
  "/upload-file",
  protectMsgRoutes,
  uploadChatFile.single("chatfile"), // "chatfile" is the field name the client will use
  handleMulterError,
  async (req, res) => {
    try {
      if (!req.file) {
        return res.status(400).json({ message: "No file uploaded." });
      }

      // Construct the URL path for the client to access the file
      const fileUrl = `/uploads/chat_files/${req.file.filename}`;

      // Return the file metadata to the client
      res.status(200).json({
        message: "File uploaded successfully",
        fileUrl: fileUrl,
        fileName: req.file.originalname,
        fileType: req.file.mimetype,
      });
    } catch (error) {
      console.error("File Upload Route Error:", error);
      res.status(500).json({ message: "Server error during file upload." });
    }
  }
);

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
    res.status(500).json({
      message: "Server error fetching messages.",
      error: error.message,
    });
  }
});

// @desc    Edit a message
// @route   PUT /api/messages/:messageId/edit
// @access  Private
routerMsgRoutes.put("/:messageId/edit", protectMsgRoutes, async (req, res) => {
  const { messageId } = req.params;
  const { content } = req.body;
  const currentUserId = req.user._id;

  try {
    const message = await MessageModelMsgRoutes.findById(messageId);
    if (!message)
      return res.status(404).json({ message: "Message not found." });

    // Ensure the user editing the message is the sender
    if (message.sender.toString() !== currentUserId.toString()) {
      return res
        .status(403)
        .json({ message: "You are not authorized to edit this message." });
    }

    message.content = content;
    message.isEdited = true;
    await message.save();

    const populatedMessage = await message.populate(
      "sender",
      "fullName email profilePictureUrl"
    );

    // TODO: Emit socket event to notify clients of the update
    // Example: io.to(message.conversationId.toString()).emit('messageUpdated', populatedMessage);

    res.json(populatedMessage);
  } catch (error) {
    res.status(500).json({ message: "Server error editing message." });
  }
});

// @desc    Delete a message (for everyone)
// @route   DELETE /api/messages/:messageId
// @access  Private
routerMsgRoutes.delete("/:messageId", protectMsgRoutes, async (req, res) => {
  const { messageId } = req.params;
  const currentUserId = req.user._id;

  try {
    const message = await MessageModelMsgRoutes.findById(messageId);
    if (!message)
      return res.status(404).json({ message: "Message not found." });

    if (message.sender.toString() !== currentUserId.toString()) {
      return res
        .status(403)
        .json({ message: "You are not authorized to delete this message." });
    }

    // "Soft delete": clear content and mark as deleted
    message.content = "This message was deleted";
    message.fileUrl = ""; // Clear file info as well
    message.fileType = "";
    message.fileName = "";
    message.deletedAt = new Date();
    await message.save();

    const populatedMessage = await message.populate(
      "sender",
      "fullName email profilePictureUrl"
    );

    // TODO: Emit socket event to notify clients of the update
    // Example: io.to(message.conversationId.toString()).emit('messageUpdated', populatedMessage);

    res.json(populatedMessage);
  } catch (error) {
    res.status(500).json({ message: "Server error deleting message." });
  }
});

module.exports = routerMsgRoutes;
