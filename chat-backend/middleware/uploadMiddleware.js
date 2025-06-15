// Purpose: Configures multer for file uploads.
const multer = require("multer");
const path = require("path");
const fs = require("fs"); // File system module

// Ensure the upload directory exists
const uploadDir = path.join(__dirname, "..", "uploads", "profile_pictures"); // Adjust path to be relative to project root
if (!fs.existsSync(uploadDir)) {
  fs.mkdirSync(uploadDir, { recursive: true }); // recursive: true creates parent directories if they don't exist
  console.log(`Created directory: ${uploadDir}`);
} else {
  console.log(`Upload directory already exists: ${uploadDir}`);
}

// Set up storage engine for multer
const storage = multer.diskStorage({
  destination: function (req, file, cb) {
    // The destination path should be correct and accessible
    cb(null, uploadDir);
  },
  filename: function (req, file, cb) {
    // Create a unique filename: fieldname-timestamp.extension
    // req.user should be populated by the authMiddleware if this route is protected
    const userId = req.user ? req.user._id : "anonymous";
    cb(
      null,
      `avatar-${userId}-${Date.now()}${path.extname(file.originalname)}`
    );
  },
});

// File filter to accept only images
const fileFilter = (req, file, cb) => {
  // Allowed ext
  const filetypes = /jpeg|jpg|png|gif/;
  // Check ext
  const extname = filetypes.test(path.extname(file.originalname).toLowerCase());
  // Check mime
  const mimetype = filetypes.test(file.mimetype);

  if (mimetype && extname) {
    return cb(null, true);
  } else {
    cb(new Error("Error: Images Only! (jpeg, jpg, png, gif)"), false);
  }
};

// Initialize upload variable
const upload = multer({
  storage: storage,
  limits: { fileSize: 2 * 1024 * 1024 }, // Limit file size to 2MB
  fileFilter: fileFilter,
});

// Middleware to handle multer errors, especially from fileFilter
const handleMulterError = (err, req, res, next) => {
  if (err instanceof multer.MulterError) {
    // A Multer error occurred when uploading.
    if (err.code === "LIMIT_FILE_SIZE") {
      return res
        .status(400)
        .json({ message: "File too large. Maximum size is 2MB." });
    }
    return res.status(400).json({ message: err.message });
  } else if (err) {
    // An unknown error occurred when uploading.
    if (err.message === "Error: Images Only! (jpeg, jpg, png, gif)") {
      return res.status(400).json({ message: err.message });
    }
    console.error("Unknown upload error:", err);
    return res
      .status(500)
      .json({ message: "An unknown error occurred during file upload." });
  }
  // Everything went fine.
  next();
};

module.exports = { upload, handleMulterError };
