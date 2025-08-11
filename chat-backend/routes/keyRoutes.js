// chat-backend/routes/keyRoutes.js
const express = require("express");
const router = express.Router();
const User = require("../models/User");
const protect = require("../middleware/authMiddleware"); // Use your direct import

// Route to upload a user's single public key
router.post("/upload", protect, async (req, res) => {
  try {
    const { publicKey } = req.body;
    if (typeof publicKey !== "string" || publicKey.length < 10) {
      return res
        .status(400)
        .send({ message: "A valid publicKey string is required." });
    }
    await User.findByIdAndUpdate(req.user.id, { e2eePublicKey: publicKey });
    res.status(200).send({ message: "Public key uploaded successfully" });
  } catch (error) {
    console.error("Error uploading public key:", error);
    res.status(500).send({ message: "Error uploading public key" });
  }
});

// Route to get another user's public key
router.get("/:userId/publicKey", protect, async (req, res) => {
  try {
    const user = await User.findById(req.params.userId).select("e2eePublicKey");
    if (!user || !user.e2eePublicKey) {
      return res
        .status(404)
        .send({ message: "Public key for this user not found." });
    }
    // Send back the public key
    res.status(200).json({ publicKey: user.e2eePublicKey });
  } catch (error) {
    console.error("Error fetching public key:", error);
    res.status(500).send({ message: "Error fetching public key" });
  }
});

module.exports = router;
