// FILE: socket/socketHandlers.js
// Purpose: Manages Socket.IO event handling, including E2EE flags and group key sharing.
const UserSocket = require("../models/User");
const ConversationSocket = require("../models/Conversation");
const MessageSocket = require("../models/Message");

// In-memory store for active users { userId: socketId }
let activeUsers = {}; // { userId: socketId }
let userSockets = {}; // { socketId: userId }

function initializeSocketIO(io) {
  io.on("connection", (socket) => {
    console.log(`SOCKET_INFO: New client connected: ${socket.id}`);
    const currentUserId = socket.handshake.query.userId;

    if (
      currentUserId &&
      currentUserId !== "null" &&
      currentUserId !== "undefined"
    ) {
      console.log(
        `SOCKET_INFO: User ${currentUserId} connected with socket ${socket.id}`
      );
      activeUsers[currentUserId] = socket.id;
      userSockets[socket.id] = currentUserId;
      io.emit("activeUsers", Object.keys(activeUsers));
    } else {
      console.log(
        `SOCKET_INFO: Anonymous client ${socket.id} connected, no userId provided.`
      );
    }

    socket.on("joinConversation", (conversationId) => {
      socket.join(conversationId);
      console.log(
        `SOCKET_INFO: User ${
          userSockets[socket.id] || socket.id
        } joined conversation ${conversationId}`
      );
    });

    socket.on("leaveConversation", (conversationId) => {
      socket.leave(conversationId);
      console.log(
        `SOCKET_INFO: User ${
          userSockets[socket.id] || socket.id
        } left conversation ${conversationId}`
      );
    });

    socket.on("sendMessage", async (data) => {
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
      console.log(
        `SOCKET_INFO: Message received: from ${senderId} in convo ${conversationId}. Encrypted: ${isEncrypted}`
      );

      if (!conversationId || !senderId || (!content && !fileUrl)) {
        socket.emit("messageError", {
          message: "Missing data for sending message.",
        });
        return;
      }

      try {
        let newMessage = new MessageSocket({
          conversationId,
          sender: senderId,
          content,
          isEncrypted: isEncrypted || false,
          fileUrl: fileUrl || "",
          fileType: fileType || "",
          fileName: fileName || "",
          readBy: [senderId],
          replyTo: replyTo || null,
          replySnippet: replySnippet || "",
          replySenderName: replySenderName || "",
        });
        await newMessage.save();

        const conversation = await ConversationSocket.findByIdAndUpdate(
          conversationId,
          { lastMessage: newMessage._id },
          { new: true }
        ).populate("participants");

        if (!conversation) {
          socket.emit("messageError", { message: "Conversation not found." });
          return;
        }

        newMessage = await newMessage.populate(
          "sender",
          "fullName email profilePictureUrl"
        );

        io.to(conversationId).emit("receiveMessage", newMessage.toObject());

        if (
          !conversation.isGroupChat &&
          conversation.participants.length === 2
        ) {
          const recipient = conversation.participants.find(
            (p) => p._id.toString() !== senderId
          );
          if (recipient) {
            const recipientSocketId = activeUsers[recipient._id.toString()];
            if (recipientSocketId) {
              newMessage.status = "delivered";
              await newMessage.save();
              const senderSocketId = activeUsers[senderId];
              if (senderSocketId) {
                io.to(senderSocketId).emit("messageDelivered", {
                  messageId: newMessage._id,
                  conversationId: conversationId,
                });
              }
            }
          }
        }

        console.log(
          `SOCKET_INFO: Message saved and emitted: ${newMessage._id}`
        );
      } catch (error) {
        console.error("SOCKET_ERROR: Error saving or emitting message:", error);
        socket.emit("messageError", {
          message: "Error processing your message.",
          details: error.message,
        });
      }
    });

    // --- NEW: Event handler for sharing group keys ---
    socket.on("shareGroupKey", (data) => {
      const { conversationId, senderId, recipientId, encryptedKey } = data;
      console.log(
        `SOCKET_INFO: Received group key share from ${senderId} for ${recipientId} in convo ${conversationId}`
      );

      if (!recipientId || !encryptedKey || !conversationId || !senderId) {
        console.error("SOCKET_ERROR: Invalid data for shareGroupKey event.");
        return;
      }

      // Find the recipient's socket ID from the active users list
      const recipientSocketId = activeUsers[recipientId];

      if (recipientSocketId) {
        // The recipient is online, send the key directly to their socket
        io.to(recipientSocketId).emit("receiveGroupKey", {
          conversationId,
          senderId,
          encryptedKey,
        });
        console.log(
          `SOCKET_INFO: Relayed group key to recipient ${recipientId}`
        );
      } else {
        console.log(
          `SOCKET_INFO: Recipient ${recipientId} is offline. Cannot share group key.`
        );
        // In a more advanced setup, you might handle offline key distribution here
      }
    });

    socket.on("markMessagesAsRead", async (data) => {
      const { conversationId } = data;
      const readerId = userSockets[socket.id];

      if (!conversationId || !readerId) {
        console.error("SOCKET_ERROR: markMessagesAsRead event missing data.");
        return;
      }

      try {
        const conversation = await ConversationSocket.findById(conversationId);
        if (!conversation) return;

        const result = await MessageSocket.updateMany(
          {
            conversationId: conversationId,
            sender: { $ne: readerId },
            status: { $ne: "read" },
          },
          {
            $set: { status: "read" },
            $addToSet: { readBy: readerId },
          }
        );

        console.log(
          `SOCKET_INFO: User ${readerId} marked messages as read in ${conversationId}. Updated: ${result.modifiedCount}`
        );

        if (result.modifiedCount > 0) {
          const sender = conversation.participants.find(
            (p) => p._id.toString() !== readerId
          );
          if (sender) {
            const senderSocketId = activeUsers[sender._id.toString()];
            if (senderSocketId) {
              io.to(senderSocketId).emit("messagesRead", {
                conversationId: conversationId,
              });
            }
          }
        }
      } catch (error) {
        console.error("SOCKET_ERROR: Error in markMessagesAsRead:", error);
      }
    });

    socket.on("reactToMessage", async (data) => {
      const { conversationId, messageId, emoji } = data;
      const reactor = await UserSocket.findById(userSockets[socket.id]);

      if (!reactor || !messageId || !emoji) {
        socket.emit("messageError", { message: "Missing data for reaction." });
        return;
      }

      try {
        const message = await MessageSocket.findById(messageId);
        if (!message) return;

        const existingReactionIndex = message.reactions.findIndex((reaction) =>
          reaction.user.equals(reactor._id)
        );

        if (existingReactionIndex > -1) {
          if (message.reactions[existingReactionIndex].emoji === emoji) {
            message.reactions.splice(existingReactionIndex, 1);
          } else {
            message.reactions[existingReactionIndex].emoji = emoji;
          }
        } else {
          message.reactions.push({
            emoji: emoji,
            user: reactor._id,
            userName: reactor.fullName,
          });
        }

        await message.save();
        const updatedMessage = await message.populate(
          "sender",
          "fullName email profilePictureUrl"
        );

        io.to(conversationId.toString()).emit(
          "messageUpdated",
          updatedMessage.toObject()
        );
      } catch (error) {
        console.error("SOCKET_ERROR: Error reacting to message:", error);
        socket.emit("messageError", {
          message: "Error processing your reaction.",
        });
      }
    });

    socket.on("typing", (data) => {
      const { conversationId } = data;
      const typingUser = userSockets[socket.id];
      if (typingUser && conversationId) {
        socket
          .to(conversationId)
          .emit("userTyping", { ...data, isTyping: true });
      }
    });

    socket.on("stopTyping", (data) => {
      const { conversationId } = data;
      const typingUser = userSockets[socket.id];
      if (typingUser && conversationId) {
        socket
          .to(conversationId)
          .emit("userTyping", { ...data, isTyping: false });
      }
    });

    socket.on("disconnect", async () => {
      console.log(`SOCKET_INFO: Client disconnected: ${socket.id}`);
      const disconnectedUserId = userSockets[socket.id];
      if (disconnectedUserId) {
        delete activeUsers[disconnectedUserId];
        delete userSockets[socket.id];

        try {
          await UserSocket.findByIdAndUpdate(disconnectedUserId, {
            lastSeen: new Date(),
          });
          console.log(
            `SOCKET_INFO: Updated lastSeen for user ${disconnectedUserId}`
          );
        } catch (error) {
          console.error(
            `SOCKET_ERROR: Failed to update lastSeen for user ${disconnectedUserId}`,
            error
          );
        }

        io.emit("activeUsers", Object.keys(activeUsers));
        console.log(
          `SOCKET_INFO: User ${disconnectedUserId} removed from active users.`
        );
      }
    });
  });
}

module.exports = { initializeSocketIO, activeUsers };
