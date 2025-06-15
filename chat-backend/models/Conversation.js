// FILE: models/Conversation.js
// Purpose: Defines the schema for chat conversations/rooms.
const mongoose = require("mongoose"); // Standard mongoose require
const Schema = mongoose.Schema;

const conversationSchema = new Schema(
  {
    participants: [
      {
        type: Schema.Types.ObjectId,
        ref: "User",
        required: true,
      },
    ],
    isGroupChat: {
      type: Boolean,
      default: false,
    },
    groupName: {
      type: String,
      trim: true,
    },
    // <<< MODIFIED: groupAdmin to groupAdmins (Array of ObjectIds) >>>
    groupAdmins: [
      {
        type: Schema.Types.ObjectId,
        ref: "User",
        // No longer 'required' here as it's handled by creation logic,
        // and a group might temporarily have no admin during transfer if not handled carefully,
        // though our logic will aim to prevent that.
      },
    ],
    groupPictureUrl: {
      type: String,
      default: "",
    },
    lastMessage: {
      type: Schema.Types.ObjectId,
      ref: "Message",
    },
  },
  { timestamps: true }
);

conversationSchema.index({ participants: 1 });
// Optional: Index for groupAdmins if you query by it frequently
// conversationSchema.index({ groupAdmins: 1 });

// Pre-save hook to ensure at least one admin if it's a group chat with participants
conversationSchema.pre("save", function (next) {
  if (
    this.isGroupChat &&
    this.participants.length > 0 &&
    (!this.groupAdmins || this.groupAdmins.length === 0)
  ) {
    // If no admins are set and there are participants, default the first participant to be an admin.
    // This is a fallback; group creation logic should explicitly set the initial admin.
    if (this.participants[0]) {
      // Check if participants array is not empty
      console.warn(
        `Conversation ${this._id}: No admins assigned to group chat with participants. Defaulting first participant as admin.`
      );
      this.groupAdmins = [this.participants[0]];
    } else {
      // This case (group chat with no participants) is unlikely if group creation requires participants
      const err = new Error(
        "Group chat must have at least one participant to assign an admin."
      );
      return next(err);
    }
  }
  next();
});

const Conversation = mongoose.model("Conversation", conversationSchema);
module.exports = Conversation;
