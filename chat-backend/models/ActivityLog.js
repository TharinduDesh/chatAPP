const mongoose = require("mongoose");
const Schema = mongoose.Schema;

const activityLogSchema = new Schema({
  adminId: {
    type: Schema.Types.ObjectId,
    ref: "Admin",
    required: true,
  },
  adminName: {
    type: String,
    required: true,
  },
  action: {
    type: String,
    required: true,
    enum: [
      "CREATED_USER",
      "EDITED_USER",
      "DEACTIVATED_USER",
      "RESTORED_USER",
      "PERMANENTLY_DELETED_USER",
      "BANNED_USER",
      "UNBANNED_USER",
      "DELETED_MESSAGE",
    ],
  },
  targetType: {
    type: String,
    default: "USER",
  },
  targetId: {
    type: Schema.Types.ObjectId,
    required: true,
  },
  targetName: {
    type: String,
  },
  details: {
    type: String,
  },
  timestamp: {
    type: Date,
    default: Date.now,
  },
});

activityLogSchema.index({ timestamp: -1 });

const ActivityLog = mongoose.model("ActivityLog", activityLogSchema);
module.exports = ActivityLog;
