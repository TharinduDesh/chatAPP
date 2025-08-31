// chat-backend/socket/socketHandlers.js
const User = require("../models/User");
const Admin = require("../models/Admin"); // Import the Admin model
const Message = require("../models/Message");
const mongoose = require("mongoose");

// Use a Map for better performance and to avoid object prototype issues.
const activeUsers = new Map();

const initializeSocketIO = (io) => {
  io.on("connection", (socket) => {
    console.log(`SOCKET_INFO: New client connected: ${socket.id}`);

    // --- START: MODIFIED CONNECTION LOGIC ---
    // Get the raw userId and the isAdmin flag from the connection query.
    const userId = socket.handshake.query.userId;
    const isAdmin = socket.handshake.query.isAdmin === "true";

    if (userId && userId !== "null" && userId !== "undefined") {
      let socketRoomId;

      if (isAdmin) {
        // If it's an admin, create a unique ID for the active users list
        // This is what the dashboard page filters against.
        socketRoomId = `admin_${userId}`;
        console.log(
          `SOCKET_INFO: Admin ${userId} connected with socket ${socket.id}`
        );
      } else {
        // If it's a regular user, use their raw ID.
        socketRoomId = userId;
        console.log(
          `SOCKET_INFO: User ${userId} connected with socket ${socket.id}`
        );
      }

      activeUsers.set(socketRoomId, socket.id);

      // Let all clients know about the updated list of active users.
      io.emit("activeUsers", Array.from(activeUsers.keys()));
    } else {
      console.log(`SOCKET_INFO: Anonymous client ${socket.id} connected.`);
    }
    // --- END: MODIFIED CONNECTION LOGIC ---

    // --- (All other socket event handlers like 'sendMessage', 'typing', etc., remain unchanged) ---
    // ... your existing code for sendMessage, reactToMessage, etc. ...
    socket.on("sendMessage", async (data) => {
      const { conversationId, senderId, content } = data;
      // Your existing implementation...
    });

    socket.on("disconnect", async () => {
      console.log(`SOCKET_INFO: Client disconnected: ${socket.id}`);

      // --- START: MODIFIED DISCONNECT LOGIC ---
      let disconnectedUserKey;
      // Find the user key (e.g., 'admin_...' or a regular userId) associated with the disconnected socket.
      for (const [key, value] of activeUsers.entries()) {
        if (value === socket.id) {
          disconnectedUserKey = key;
          break;
        }
      }

      if (disconnectedUserKey) {
        // Remove the user from the active list.
        activeUsers.delete(disconnectedUserKey);

        // Inform all clients about the updated active user list.
        io.emit("activeUsers", Array.from(activeUsers.keys()));
        console.log(
          `SOCKET_INFO: User ${disconnectedUserKey} removed from active users.`
        );

        // Determine if the disconnected user was an admin or a regular user.
        const isDisconnectedAdmin = disconnectedUserKey.startsWith("admin_");
        const finalUserId = isDisconnectedAdmin
          ? disconnectedUserKey.substring(6)
          : disconnectedUserKey;
        const modelToUpdate = isDisconnectedAdmin ? Admin : User; // Select the correct Mongoose model.

        try {
          // Check if the ID is a valid MongoDB ObjectId before trying to query the database.
          if (mongoose.Types.ObjectId.isValid(finalUserId)) {
            await modelToUpdate.findByIdAndUpdate(finalUserId, {
              lastSeen: new Date(),
            });
            console.log(
              `SOCKET_INFO: Updated lastSeen for user ${finalUserId}`
            );
          } else {
            console.warn(
              `SOCKET_WARNING: Invalid ObjectId for lastSeen update: ${finalUserId}`
            );
          }
        } catch (error) {
          console.error(
            `SOCKET_ERROR: Failed to update lastSeen for user ${finalUserId}`,
            error
          );
        }
      }
      // --- END: MODIFIED DISCONNECT LOGIC ---
    });
  });
};

module.exports = { initializeSocketIO };
