// models/Authenticator.js
const mongoose = require("mongoose");

const AuthenticatorSchema = new mongoose.Schema({
  userId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: "Admin",
    required: true,
  },
  credentialID: {
    type: String,
    required: true,
    unique: true,
  },
  credentialPublicKey: {
    type: String,
    required: true,
  },
  counter: {
    type: Number,
    required: true,
  },
  transports: [String],
});

module.exports = mongoose.model("Authenticator", AuthenticatorSchema);
