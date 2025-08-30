// chat-backend/models/Challenge.js
const mongoose = require("mongoose");

const ChallengeSchema = new mongoose.Schema({
  challenge: {
    type: String,
    required: true,
    unique: true,
  },
  // This field will be used by MongoDB's TTL index to automatically delete the document
  createdAt: {
    type: Date,
    default: Date.now,
    expires: "5m", // The challenge will be automatically deleted after 5 minutes
  },
});

module.exports = mongoose.model("Challenge", ChallengeSchema);
