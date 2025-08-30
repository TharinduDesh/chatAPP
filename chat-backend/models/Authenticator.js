// models/Authenticator.js
const mongoose = require("mongoose");

const AuthenticatorSchema = new mongoose.Schema({
  userId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: "Admin",
    required: true,
  },
  credentialID: {
    type: String, // ✅ Change from Buffer to String
    required: true,
    unique: true,
  },
  credentialPublicKey: {
    type: Buffer, // Keep this as Buffer
    required: true,
  },
  counter: {
    type: Number,
    required: true,
    default: 0,
  },
  transports: {
    type: [String],
    default: [],
  },
});

module.exports = mongoose.model("Authenticator", AuthenticatorSchema);
