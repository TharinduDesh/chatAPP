// src/pages/ConversationViewerPage.js
import React, { useState, useEffect, useRef, useCallback } from "react";
import { useParams, Link, useNavigate } from "react-router-dom";
import {
  getConversationDetails,
  deleteMessageByAdmin,
} from "../services/moderationService";
import { API_BASE_URL } from "../config/apiConfig";
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
  IconButton,
  Breadcrumbs,
  Tooltip,
  Divider,
  useTheme,
} from "@mui/material";
import ArrowBackIcon from "@mui/icons-material/ArrowBack";
import DeleteForeverIcon from "@mui/icons-material/DeleteForever";

const MessageBubble = ({ msg, currentUserId, onDelete }) => {
  const theme = useTheme();
  const isOwn = msg.sender?._id === currentUserId;

  return (
    <ListItem
      sx={{
        display: "flex",
        justifyContent: isOwn ? "flex-end" : "flex-start",
        mb: 2,
      }}
    >
      {!isOwn && (
        <ListItemAvatar>
          <Avatar
            src={
              msg.sender?.profilePictureUrl
                ? `${API_BASE_URL}${msg.sender.profilePictureUrl}`
                : "/default-admin.png"
            }
          >
            {msg.sender ? msg.sender.fullName?.charAt(0) : "S"}
          </Avatar>
        </ListItemAvatar>
      )}

      <Box
        sx={{
          maxWidth: "70%",
          px: 2,
          py: 1.2,
          borderRadius: 3,
          bgcolor: isOwn
            ? theme.palette.primary.main
            : theme.palette.grey[200],
          color: isOwn ? "white" : "text.primary",
          boxShadow: 2,
          position: "relative",
          "&:hover .delete-btn": { opacity: 1 },
        }}
      >
        <Typography variant="body2" fontWeight="bold">
          {msg.sender?.fullName || "System"}
        </Typography>
        <Typography
          variant="body1"
          sx={{ wordBreak: "break-word", mt: 0.5 }}
        >
          {msg.content}
        </Typography>
        <Typography
          variant="caption"
          sx={{ display: "block", mt: 0.5, opacity: 0.7 }}
        >
          {new Date(msg.createdAt).toLocaleString()}
        </Typography>

        <IconButton
          className="delete-btn"
          size="small"
          sx={{
            position: "absolute",
            top: 4,
            right: 4,
            opacity: 0,
            transition: "opacity 0.2s",
            color: isOwn ? "white" : "error.main",
          }}
          onClick={() => onDelete(msg._id)}
        >
          <DeleteForeverIcon fontSize="small" />
        </IconButton>
      </Box>
    </ListItem>
  );
};

const ConversationViewerPage = () => {
  const { conversationId } = useParams();
  const [conversation, setConversation] = useState(null);
  const [messages, setMessages] = useState([]);
  const [loading, setLoading] = useState(true);
  const messagesEndRef = useRef(null);
  const navigate = useNavigate();
  const currentUserId = "admin"; // replace with real admin user id if available

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
      : conversation.participants
          ?.map((p) => p.fullName)
          .join(" & ") || "Unknown Chat";

  return (
    <Box sx={{ height: "100%", display: "flex", flexDirection: "column" }}>
      {/* Header */}
      <Box
        sx={{
          display: "flex",
          alignItems: "center",
          p: 2,
          borderBottom: "1px solid",
          borderColor: "divider",
          bgcolor: "background.paper",
          position: "sticky",
          top: 0,
          zIndex: 10,
        }}
      >
        <Tooltip title="Back to Moderation List">
          <IconButton onClick={() => navigate("/moderation")}>
            <ArrowBackIcon />
          </IconButton>
        </Tooltip>
        <Breadcrumbs aria-label="breadcrumb" sx={{ ml: 2 }}>
          <Link
            to="/moderation"
            style={{ textDecoration: "none", color: "inherit" }}
          >
            Moderation
          </Link>
          <Typography color="text.primary">{getTitle()}</Typography>
        </Breadcrumbs>
      </Box>

      {/* Conversation Body */}
      <Paper
        elevation={2}
        sx={{
          flexGrow: 1,
          display: "flex",
          flexDirection: "column",
          overflow: "hidden",
          borderRadius: 3,
          m: { xs: 1, md: 2 },
        }}
      >
        <List
          sx={{
            flexGrow: 1,
            overflowY: "auto",
            p: { xs: 1, sm: 2 },
            bgcolor: "background.default",
          }}
        >
          {messages.map((msg) => (
            <MessageBubble
              key={msg._id}
              msg={msg}
              currentUserId={currentUserId}
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
