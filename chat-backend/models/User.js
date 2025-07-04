// Purpose: Defines the User schema and pre-save hooks for password hashing.
const mongooseUser = require("mongoose"); // Renamed to avoid conflict if 'mongoose' is used elsewhere
const bcryptUser = require("bcryptjs"); // Renamed for clarity

const userSchema = new mongooseUser.Schema({
  fullName: {
    type: String,
    required: [true, "Full name is required"],
    trim: true,
  },
  email: {
    type: String,
    required: [true, "Email is required"],
    unique: true,
    trim: true,
    lowercase: true,
    match: [/.+\@.+\..+/, "Please fill a valid email address"],
  },
  password: {
    type: String,
    required: [true, "Password is required"],
    minlength: [6, "Password must be at least 6 characters long"],
  },
  profilePictureUrl: {
    type: String,
    default: "", // Default placeholder or empty
  },
  lastSeen: {
    type: Date,
    default: Date.now,
  },
  createdAt: {
    type: Date,
    default: Date.now,
  },
});

// Pre-save hook to hash password before saving
userSchema.pre("save", async function (next) {
  // Only hash the password if it has been modified (or is new)
  if (!this.isModified("password")) {
    return next();
  }
  try {
    const salt = await bcryptUser.genSalt(10);
    this.password = await bcryptUser.hash(this.password, salt);
    next();
  } catch (error) {
    next(error);
  }
});

// Method to compare candidate password with the stored hashed password
userSchema.methods.comparePassword = async function (candidatePassword) {
  return bcryptUser.compare(candidatePassword, this.password);
};

const User = mongooseUser.model("User", userSchema);
module.exports = User;
