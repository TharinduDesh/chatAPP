// chat-backend/server.js

const express = require("express");
const mongoose = require("mongoose");
const cors = require("cors");
const dotenv = require("dotenv");
const path = require("path");
const http = require("http");
const { Server } = require("socket.io");
const { initializeSocketIO } = require("./socket/socketHandlers");
const cron = require("node-cron");
const User = require("./models/User");

dotenv.config();

const app = express();
const httpServer = http.createServer(app);
const io = new Server(httpServer, { cors: { origin: "*" } });

// --- Global Middleware ---
// This section is now corrected and simplified.
app.use(cors());
app.use(express.json()); // This is the crucial line that parses JSON bodies.

app.set("socketio", io);
initializeSocketIO(io);

// --- MongoDB Connection ---
mongoose
  .connect(process.env.MONGO_URI)
  .then(() => console.log("MongoDB Connected Successfully!"))
  .catch((err) => console.error("MongoDB Connection Error:", err.message));

// --- Static File Serving ---
app.use("/uploads", express.static(path.join(__dirname, "uploads")));

// --- Cron Job ---
cron.schedule("5 1 * * *", async () => {
  /* ... your cron job logic ... */
});

// --- Import & Use API Routes ---
const authRoutes = require("./routes/authRoutes");
const userRoutes = require("./routes/userRoutes");
const conversationRoutes = require("./routes/conversationRoutes");
const messageRoutes = require("./routes/messageRoutes");
const keyRoutes = require("./routes/keyRoutes"); // E2EE
// Import your admin routes...
const adminAuthRoutes = require("./routes/adminAuthRoutes");
const adminUserRoutes = require("./routes/adminUserRoutes");
const activityLogRoutes = require("./routes/activityLogRoutes");
const analyticsRoutes = require("./routes/analyticsRoutes");
const adminConversationRoutes = require("./routes/adminConversationRoutes");
const adminMessageRoutes = require("./routes/adminMessageRoutes");

const webauthnRoutes = require("./routes/webauthnRoutes");

app.use("/api/auth", authRoutes);
app.use("/api/users", userRoutes);
app.use("/api/conversations", conversationRoutes);
app.use("/api/messages", messageRoutes);
app.use("/api/keys", keyRoutes); // E2EE
// Use your admin routes...
app.use("/api/admin/auth", adminAuthRoutes);
app.use("/api/admin/users", adminUserRoutes);
app.use("/api/logs", activityLogRoutes);
app.use("/api/analytics", analyticsRoutes);
app.use("/api/admin/conversations", adminConversationRoutes);
app.use("/api/admin/messages", adminMessageRoutes);

app.use("/api/webauthn", webauthnRoutes);

// --- Welcome Route & Server Listening ---
app.get("/", (req, res) => res.send("Chat App Backend is Running!"));
const PORT = process.env.PORT || 5000;
httpServer.listen(PORT, () => console.log(`Server running on port ${PORT}`));
