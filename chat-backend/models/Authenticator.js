// models/Authenticator.js
const mongoose = require("mongoose");

const AuthenticatorSchema = new mongoose.Schema({
  userId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: "Admin",
    required: true,
  },
  credentialID: {
    type: Buffer, // ✅ store as Buffer
    required: true,
    unique: true,
  },
  credentialPublicKey: {
    type: Buffer, // ✅ store as Buffer
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
