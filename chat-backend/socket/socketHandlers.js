// FILE: socket/socketHandlers.js
// Purpose: Manages Socket.IO event handling, now including logic for read receipts.
const UserSocket = require("../models/User");
const ConversationSocket = require("../models/Conversation");
const MessageSocket = require("../models/Message");

// In-memory store for active users { userId: socketId }
// For a multi-server setup, you'd use Redis or another shared store.
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

    // <<< MODIFIED: sendMessage to handle 'delivered' status >>>
    socket.on("sendMessage", async (data) => {
      // <<< MODIFIED: Destructure new file-related fields >>>
      const {
        conversationId,
        senderId,
        content,
        fileUrl,
        fileType,
        fileName,
        replyTo,
        replySnippet,
        replySenderName,
      } = data;
      console.log(
        `SOCKET_INFO: Message received: from ${senderId} in convo ${conversationId}`
      );

      // A message must have content OR a file
      if (!conversationId || !senderId || (!content && !fileUrl)) {
        socket.emit("messageError", {
          message: "Missing data for sending message.",
        });
        return;
      }

      try {
        // 1. Save the message to the database
        let newMessage = new MessageSocket({
          conversationId,
          sender: senderId,
          content,
          fileUrl: fileUrl || "",
          fileType: fileType || "",
          fileName: fileName || "",
          readBy: [senderId],
          replyTo: replyTo || null,
          replySnippet: replySnippet || "",
          replySenderName: replySenderName || "",
        });
        await newMessage.save();

        // 2. Update the lastMessage in the conversation
        const conversation = await ConversationSocket.findByIdAndUpdate(
          conversationId,
          { lastMessage: newMessage._id },
          { new: true }
        ).populate("participants"); // Populate participants to find recipients

        if (!conversation) {
          socket.emit("messageError", { message: "Conversation not found." });
          return;
        }

        // 3. Populate sender details for the message to be broadcast
        newMessage = await newMessage.populate(
          "sender",
          "fullName email profilePictureUrl"
        );

        // 4. Broadcast the new message to all clients in that conversation room
        io.to(conversationId).emit("receiveMessage", newMessage.toObject());

        // 5. Handle 'delivered' status for one-to-one chats
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
              // If the recipient is online
              // Update the message status to 'delivered' in the DB
              newMessage.status = "delivered";
              await newMessage.save();

              // Notify the sender that the message was delivered
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

    // <<< NEW: Listener for when a user reads messages >>>
    socket.on("markMessagesAsRead", async (data) => {
      const { conversationId } = data;
      const readerId = userSockets[socket.id]; // The user who is reading

      if (!conversationId || !readerId) {
        console.error("SOCKET_ERROR: markMessagesAsRead event missing data.");
        return;
      }

      try {
        const conversation = await ConversationSocket.findById(conversationId);
        if (!conversation) return;

        // Find all messages in this convo not sent by the reader, and update their status to 'read'
        const result = await MessageSocket.updateMany(
          {
            conversationId: conversationId,
            sender: { $ne: readerId }, // Not sent by me
            status: { $ne: "read" }, // Not already read
          },
          {
            $set: { status: "read" },
            $addToSet: { readBy: readerId }, // Also update readBy for unread counts
          }
        );

        console.log(
          `SOCKET_INFO: User ${readerId} marked messages as read in ${conversationId}. Updated: ${result.modifiedCount}`
        );

        // If any messages were updated, notify the original sender that their messages were read
        if (result.modifiedCount > 0) {
          // Find the other user in the 1-to-1 chat
          const sender = conversation.participants.find(
            (p) => p._id.toString() !== readerId
          );
          if (sender) {
            const senderSocketId = activeUsers[sender._id.toString()];
            if (senderSocketId) {
              // Notify the sender that all their messages in this chat have been read
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

    socket.on("disconnect", () => {
      console.log(`SOCKET_INFO: Client disconnected: ${socket.id}`);
      const disconnectedUserId = userSockets[socket.id];
      if (disconnectedUserId) {
        delete activeUsers[disconnectedUserId];
        delete userSockets[socket.id];
        io.emit("activeUsers", Object.keys(activeUsers));
        console.log(
          `SOCKET_INFO: User ${disconnectedUserId} removed from active users.`
        );
      }
    });
  });
}

module.exports = { initializeSocketIO, activeUsers };
