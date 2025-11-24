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

    // --- SOCKET EVENT HANDLERS ---

    // 1. Join/Leave Conversation Rooms
    socket.on("joinConversation", (conversationId) => {
      socket.join(conversationId);
      console.log(`Socket ${socket.id} joined conversation: ${conversationId}`);
    });

    socket.on("leaveConversation", (conversationId) => {
      socket.leave(conversationId);
    });

    // 2. Send Message (The Missing Logic)
    socket.on("sendMessage", async (data) => {
      try {
        const {
          conversationId,
          senderId,
          content,
          isEncrypted,
          fileUrl,
          fileType,
          fileName,
          replyTo,
          replySnippet,
          replySenderName,
        } = data;

        // A. Create and Save the Message
        const newMessage = new Message({
          conversationId,
          sender: senderId,
          content,
          isEncrypted: isEncrypted || false,
          fileUrl: fileUrl || "",
          fileType: fileType || "",
          fileName: fileName || "",
          replyTo,
          replySnippet,
          replySenderName,
          status: "sent",
        });

        const savedMessage = await newMessage.save();

        const populatedMessage = await savedMessage.populate(
          "sender",
          "fullName email profilePictureUrl"
        );

        // B. Update the Conversation
        const updatedConversation = await mongoose
          .model("Conversation")
          .findByIdAndUpdate(
            conversationId,
            {
              lastMessage: savedMessage._id, // Point to the new message
              updatedAt: new Date(), // Update timestamp so it moves to top
            },
            { new: true } // Return the updated document
          )
          .populate("participants", "fullName email profilePictureUrl")
          .populate({
            path: "lastMessage",
            populate: { path: "sender", select: "fullName" },
          });

        // C. Emit 'receiveMessage' to the chat room (for users currently INSIDE the chat)
        io.to(conversationId).emit("receiveMessage", populatedMessage);

        // D. Emit 'conversationUpdated' to ALL participants (for their Home Screen)
        if (updatedConversation) {
          updatedConversation.participants.forEach((participant) => {
            const participantId = participant._id.toString();

            // 1. Check if this user is online (in activeUsers map)
            const participantSocketId = activeUsers.get(participantId);

            // 2. If they are online, send the update directly to their socket
            if (participantSocketId) {
              io.to(participantSocketId).emit(
                "conversationUpdated",
                updatedConversation
              );
            }
          });
        }

        console.log(`Message sent & Conversation updated: ${conversationId}`);
      } catch (error) {
        console.error("Error in sendMessage socket handler:", error);
      }
    });

    // 3. Typing Indicators
    socket.on("typing", (data) => {
      socket.to(data.conversationId).emit("userTyping", {
        conversationId: data.conversationId,
        userId: data.userId,
        userName: data.userName,
        isTyping: true,
      });
    });

    socket.on("stopTyping", (data) => {
      socket.to(data.conversationId).emit("userTyping", {
        conversationId: data.conversationId,
        userId: data.userId,
        isTyping: false,
      });
    });

    // 4. Disconnect Logic (Preserving your modified logic)
    socket.on("disconnect", async () => {
      console.log(`SOCKET_INFO: Client disconnected: ${socket.id}`);

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
    });
  });
};

module.exports = { initializeSocketIO };
