// FILE: models/Message.js
// Purpose: Updated schema for individual chat messages to include read receipt status.
const mongooseMsg = require("mongoose");
const SchemaMsg = mongooseMsg.Schema;

// Define a schema for a single reaction
const reactionSchema = new SchemaMsg(
  {
    emoji: { type: String, required: true },
    user: { type: SchemaMsg.Types.ObjectId, ref: "User", required: true },
    userName: { type: String, required: true }, // Store user's name for easy display
  },
  { _id: false }
);

const messageSchema = new SchemaMsg(
  {
    conversationId: {
      type: SchemaMsg.Types.ObjectId,
      ref: "Conversation",
      required: true,
    },
    sender: {
      type: SchemaMsg.Types.ObjectId,
      ref: "User",
      required: false,
    },
    content: {
      type: String,
      trim: true,
    },
    // Field to identify message type
    messageType: {
      type: String,
      enum: ["text", "image", "audio", "video", "system"],
      default: "text",
    },
    isEncrypted: {
      type: Boolean,
      default: false,
    },
    reactions: [reactionSchema],
    // Fields for file sharing
    fileUrl: {
      type: String,
      default: "",
    },
    fileType: {
      type: String, // e.g., 'image', 'pdf', 'video'
      default: "",
    },
    fileName: {
      type: String,
      default: "",
    },
    // <<< NEW: Status field for read receipts >>>
    // This approach is simpler for 1-to-1 chats.
    // A 'readBy' array is better for group chats but more complex to manage for individual status icons.
    // We will focus on 1-to-1 receipts for now.
    status: {
      type: String,
      enum: ["sent", "delivered", "read"],
      default: "sent",
    },
    isEdited: {
      type: Boolean,
      default: false,
    },
    deletedAt: {
      type: Date,
    },
    replyTo: {
      type: SchemaMsg.Types.ObjectId,
      ref: "Message", // Reference to the message being replied to
      default: null,
    },
    // To avoid extra lookups, we can store a snippet of the original message
    replySnippet: {
      type: String,
      default: "",
    },
    replySenderName: {
      // And the original sender's name
      type: String,
      default: "",
    },

    // The 'readBy' array from the unread message feature can coexist or be removed
    // if you prefer this status-based approach for all chat types.
    // For this feature, we will assume `status` is for 1-to-1 and `readBy` is for unread counts.
    readBy: [
      {
        type: SchemaMsg.Types.ObjectId,
        ref: "User",
      },
    ],
  },
  { timestamps: true }
);

// Index for faster querying of messages by conversation
messageSchema.index({ conversationId: 1, createdAt: -1 });

// Add a text index on the content field for searching
messageSchema.index({ content: "text" });

const Message = mongooseMsg.model("Message", messageSchema);
module.exports = Message;
