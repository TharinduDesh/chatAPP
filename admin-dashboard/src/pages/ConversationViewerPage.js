// src/pages/ConversationViewerPage.js
import React, { useState, useEffect, useRef, useCallback } from "react"; // Import useCallback
import { useParams, Link, useNavigate } from "react-router-dom";
import {
  getConversationDetails,
  deleteMessageByAdmin,
} from "../services/moderationService";
import { API_BASE_URL } from "../config/apiConfig"; // ✅ Import the base URL
import {
  Box,
  Typography,
  Paper,
  CircularProgress,
  Avatar,
  List,
  ListItem,
  ListItemAvatar,
  ListItemText,
  Divider,
  IconButton,
  Breadcrumbs,
  Tooltip,
} from "@mui/material";
import ArrowBackIcon from "@mui/icons-material/ArrowBack";
import DeleteForeverIcon from "@mui/icons-material/DeleteForever";

const MessageBubble = ({ msg, isAdminMessage = false, onDelete }) => (
  <ListItem
    secondaryAction={
      <Tooltip title="Delete this message">
        <IconButton
          edge="end"
          aria-label="delete"
          onClick={() => onDelete(msg._id)}
        >
          <DeleteForeverIcon color="error" />
        </IconButton>
      </Tooltip>
    }
  >
    <ListItemAvatar>
      <Avatar
        // ✅ FIX: Use the live backend URL for images
        src={
          msg.sender
            ? `${API_BASE_URL}${msg.sender.profilePictureUrl}`
            : "/default-admin.png"
        }
      >
        {msg.sender ? msg.sender.fullName.charAt(0) : "S"}
      </Avatar>
    </ListItemAvatar>
    <ListItemText
      primary={
        <Typography
          variant="body1"
          color={isAdminMessage ? "secondary.main" : "text.primary"}
        >
          <strong>{msg.sender ? msg.sender.fullName : "System"}</strong>
        </Typography>
      }
      secondary={
        <>
          <Typography
            component="p"
            variant="body2"
            color="text.primary"
            sx={{ wordBreak: "break-word" }}
          >
            {msg.content}
          </Typography>
          {new Date(msg.createdAt).toLocaleString()}
        </>
      }
    />
  </ListItem>
);

const ConversationViewerPage = () => {
  const { conversationId } = useParams();
  const [conversation, setConversation] = useState(null);
  const [messages, setMessages] = useState([]);
  const [loading, setLoading] = useState(true);
  const messagesEndRef = useRef(null);
  const navigate = useNavigate();

  // ✅ FIX: fetchDetails is now wrapped in useCallback and depends on conversationId.
  // This makes the function stable unless the ID changes.
  const fetchDetails = useCallback(async () => {
    setLoading(true);
    try {
      const data = await getConversationDetails(conversationId);
      setConversation(data.conversation);
      setMessages(data.messages);
    } catch (error) {
      console.error("Failed to fetch conversation details", error);
    } finally {
      setLoading(false);
    }
  }, [conversationId]);

  // ✅ FIX: This useEffect hook now correctly depends on fetchDetails.
  // It will re-run only when conversationId changes, which is the desired behavior.
  useEffect(() => {
    fetchDetails();
  }, [fetchDetails]);

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  const handleDeleteMessage = async (messageId) => {
    if (
      window.confirm(
        "Are you sure you want to delete this message? This action cannot be undone."
      )
    ) {
      try {
        await deleteMessageByAdmin(messageId);
        // Refresh the message list to show the change
        fetchDetails();
      } catch (error) {
        console.error("Failed to delete message", error);
        alert("Could not delete the message.");
      }
    }
  };

  if (loading) {
    return (
      <Box sx={{ display: "flex", justifyContent: "center", mt: 4 }}>
        <CircularProgress />
      </Box>
    );
  }

  if (!conversation) {
    return <Typography>Conversation not found.</Typography>;
  }

  const getTitle = () =>
    conversation.isGroupChat
      ? conversation.groupName
      : conversation.participants.map((p) => p.fullName).join(" & ");

  return (
    <Box>
      <Box sx={{ display: "flex", alignItems: "center", mb: 2 }}>
        <Tooltip title="Back to Moderation List">
          <IconButton onClick={() => navigate("/moderation")}>
            <ArrowBackIcon />
          </IconButton>
        </Tooltip>
        <Divider orientation="vertical" flexItem sx={{ mx: 1 }} />
        <Breadcrumbs aria-label="breadcrumb">
          <Link
            component={Link}
            to="/moderation"
            style={{ textDecoration: "none", color: "inherit" }}
          >
            Moderation
          </Link>
          <Typography color="text.primary">{getTitle()}</Typography>
        </Breadcrumbs>
      </Box>
      <Paper
        elevation={3}
        sx={{ height: "70vh", display: "flex", flexDirection: "column" }}
      >
        <Box sx={{ p: 2, borderBottom: "1px solid #ddd" }}>
          <Typography variant="h5">{getTitle()}</Typography>
        </Box>
        <List sx={{ flexGrow: 1, overflowY: "auto", p: 2 }}>
          {messages.map((msg) => (
            <MessageBubble
              key={msg._id}
              msg={msg}
              onDelete={handleDeleteMessage}
            />
          ))}
          <div ref={messagesEndRef} />
        </List>
      </Paper>
    </Box>
  );
};

export default ConversationViewerPage;
