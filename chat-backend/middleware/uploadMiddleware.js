// Purpose: Configures multer for file uploads.
const multer = require("multer");
const path = require("path");
const fs = require("fs"); // File system module

// --- Configuration for Profile Avatars ---
const profileUploadDir = path.join(
  __dirname,
  "..",
  "uploads",
  "profile_pictures"
);
if (!fs.existsSync(profileUploadDir)) {
  fs.mkdirSync(profileUploadDir, { recursive: true });
}

const profilePictureStorage = multer.diskStorage({
  destination: function (req, file, cb) {
    cb(null, profileUploadDir);
  },
  filename: function (req, file, cb) {
    const userId = req.user ? req.user._id : "anonymous";
    cb(
      null,
      `avatar-${userId}-${Date.now()}${path.extname(file.originalname)}`
    );
  },
});

const imageFileFilter = (req, file, cb) => {
  const filetypes = /jpeg|jpg|png|gif/;
  const extname = filetypes.test(path.extname(file.originalname).toLowerCase());
  const mimetype = filetypes.test(file.mimetype);
  if (mimetype && extname) {
    return cb(null, true);
  } else {
    cb(new Error("Error: Images Only! (jpeg, jpg, png, gif)"), false);
  }
};

// Original 'upload' for avatars
const upload = multer({
  storage: profilePictureStorage,
  limits: { fileSize: 2 * 1024 * 1024 },
  fileFilter: imageFileFilter,
});

// --- Configuration for Chat Files ---
const chatUploadDir = path.join(__dirname, "..", "uploads", "chat_files");
if (!fs.existsSync(chatUploadDir)) {
  fs.mkdirSync(chatUploadDir, { recursive: true });
}

const chatFileStorage = multer.diskStorage({
  destination: function (req, file, cb) {
    cb(null, chatUploadDir);
  },
  filename: function (req, file, cb) {
    const userId = req.user ? req.user._id : "anonymous";
    cb(null, `file-${userId}-${Date.now()}${path.extname(file.originalname)}`);
  },
});

const chatFileFilter = (req, file, cb) => {
  // Allow a wider range of file types for chat
  const allowedMimes = [
    "image/jpeg",
    "image/png",
    "image/gif",
    "application/pdf",
    "application/msword",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "video/mp4",
    "video/quicktime",
    "audio/mpeg", // .mp3
    "audio/mp4", // .m4a
    "audio/aac",
    "audio/wav",
  ];
  if (allowedMimes.includes(file.mimetype)) {
    cb(null, true);
  } else {
    cb(new Error("Error: Invalid file type."), false);
  }
};

// New 'uploadChatFile' for chat messages
const uploadChatFile = multer({
  storage: chatFileStorage,
  limits: { fileSize: 10 * 1024 * 1024 }, // 10MB limit
  fileFilter: chatFileFilter,
});

// --- Shared Multer Error Handler ---
const handleMulterError = (err, req, res, next) => {
  if (err instanceof multer.MulterError) {
    if (err.code === "LIMIT_FILE_SIZE") {
      return res.status(400).json({
        message: `File too large. Maximum size is ${
          err.limit / 1024 / 1024
        }MB.`,
      });
    }
    return res.status(400).json({ message: err.message });
  } else if (err) {
    return res.status(400).json({ message: err.message });
  }
  next();
};

// --- EXPORT ALL MIDDLEWARE ---
// This is the most important part. Ensure all your uploaders are exported.
module.exports = {
  upload,
  uploadChatFile, // Make sure this is exported
  handleMulterError,
};
