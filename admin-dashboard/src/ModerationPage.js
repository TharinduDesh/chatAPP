// src/pages/ModerationPage.js
import React, { useState, useEffect, useMemo } from "react";
import { getAllConversations } from "../services/moderationService";
import { useNavigate } from "react-router-dom";
import {
  Box,
  Typography,
  Paper,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  TextField,
  Chip,
  Avatar,
  AvatarGroup,
  CircularProgress,
  Card,
  CardContent,
  alpha,
  useTheme,
  InputAdornment, // ✅ Import for the search icon
} from "@mui/material";
import SearchIcon from "@mui/icons-material/Search";

const ModerationPage = () => {
  const theme = useTheme();
  const [conversations, setConversations] = useState([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState("");
  const navigate = useNavigate();

  useEffect(() => {
    const fetchConversations = async () => {
      try {
        const data = await getAllConversations();
        setConversations(data);
      } catch (error) {
        console.error("Failed to fetch conversations", error);
      } finally {
        setLoading(false);
      }
    };
    fetchConversations();
  }, []);

  const filteredConversations = useMemo(
    () =>
      conversations.filter(
        (convo) =>
          (convo.groupName &&
            convo.groupName.toLowerCase().includes(filter.toLowerCase())) ||
          convo.participants.some((p) =>
            p.fullName.toLowerCase().includes(filter.toLowerCase())
          )
      ),
    [conversations, filter]
  );

  const getConversationTitle = (convo) => {
    if (convo.isGroupChat) {
      return convo.groupName || "Unnamed Group";
    }
    // Safely access participant names
    const participantNames = convo.participants
      .map((p) => p.fullName)
      .filter(Boolean);
    return participantNames.length > 0 ? participantNames.join(" & ") : "Unknown Conversation";
  };

  return (
    <Box>
      <Box sx={{ mb: 4 }}>
        <Typography
          variant="h4"
          sx={{
            fontWeight: 700,
            background: "linear-gradient(135deg, #00d4aa 0%, #4169e1 100%)",
            backgroundClip: "text",
            WebkitBackgroundClip: "text",
            WebkitTextFillColor: "transparent",
            mb: 1,
            // ✅ Enhancement: Add a subtle fade-in animation
            animation: "fadeIn 1s ease-in-out",
            "@keyframes fadeIn": {
              "0%": { opacity: 0, transform: "translateY(20px)" },
              "100%": { opacity: 1, transform: "translateY(0)" },
            },
          }}
        >
          Conversation Moderation
        </Typography>
        <Typography variant="body1" color="text.secondary">
          Monitor and manage all conversations and user interactions
        </Typography>
      </Box>

      <Card
        sx={{
          borderRadius: 3,
          border: "1px solid",
          borderColor: "divider",
          // ✅ Enhancement: Add a subtle hover effect to the entire card
          transition: "all 0.3s ease",
          "&:hover": {
            transform: "translateY(-4px)",
            boxShadow: `0 8px 25px ${alpha(theme.palette.primary.main, 0.1)}`,
          },
        }}
      >
        <CardContent sx={{ p: 3 }}>
          <TextField
            label="Search by Group Name or Participant"
            variant="outlined"
            fullWidth
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
            // ✅ Enhancement: Add a search icon to the input field
            InputProps={{
              startAdornment: (
                <InputAdornment position="start">
                  <SearchIcon sx={{ color: "text.secondary" }} />
                </InputAdornment>
              ),
            }}
            sx={{ mb: 3 }}
          />

          {loading ? (
            <Box sx={{ display: "flex", justifyContent: "center", p: 4 }}>
              <CircularProgress />
            </Box>
          ) : (
            <TableContainer
              component={Paper}
              sx={{ borderRadius: 2, overflow: "hidden" }}
            >
              <Table>
                <TableHead>
                  <TableRow sx={{ bgcolor: "grey.50" }}>
                    <TableCell
                      sx={{ fontWeight: 600, color: "text.secondary", py: 2 }}
                    >
                      Conversation
                    </TableCell>
                    <TableCell
                      sx={{ fontWeight: 600, color: "text.secondary", py: 2 }}
                    >
                      Participants
                    </TableCell>
                    <TableCell
                      sx={{ fontWeight: 600, color: "text.secondary", py: 2 }}
                    >
                      Type
                    </TableCell>
                    <TableCell
                      sx={{ fontWeight: 600, color: "text.secondary", py: 2 }}
                    >
                      Last Activity
                    </TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {filteredConversations.map((convo) => (
                    <TableRow
                      key={convo._id}
                      hover
                      sx={{
                        cursor: "pointer",
                        // ✅ Enhancement: Add a more dynamic hover effect
                        transition: "all 0.3s ease-in-out",
                        "&:hover": {
                          bgcolor: alpha(theme.palette.primary.main, 0.05),
                          transform: "scale(1.01)",
                          boxShadow: `0 4px 10px ${alpha(
                            theme.palette.primary.main,
                            0.1
                          )}`,
                        },
                      }}
                      onClick={() => navigate(`/moderation/${convo._id}`)}
                    >
                      <TableCell sx={{ py: 2, fontWeight: 500 }}>
                        {getConversationTitle(convo)}
                      </TableCell>
                      <TableCell sx={{ py: 2 }}>
                        <AvatarGroup max={4}>
                          {convo.participants.map((p) => (
                            <Avatar
                              key={p._id}
                              alt={p.fullName}
                              sx={{
                                width: 32,
                                height: 32,
                                bgcolor: theme.palette.primary.main,
                              }}
                            >
                              {p.fullName?.charAt(0) || ""}
                            </Avatar>
                          ))}
                        </AvatarGroup>
                      </TableCell>
                      <TableCell sx={{ py: 2 }}>
                        <Chip
                          label={convo.isGroupChat ? "Group" : "One-on-One"}
                          size="small"
                          sx={{
                            bgcolor: convo.isGroupChat
                              ? alpha(theme.palette.primary.main, 0.1)
                              : alpha(theme.palette.success.main, 0.1),
                            color: convo.isGroupChat
                              ? theme.palette.primary.main
                              : theme.palette.success.main,
                            fontWeight: 600,
                          }}
                        />
                      </TableCell>
                      <TableCell sx={{ py: 2, color: "text.secondary" }}>
                        {new Date(convo.updatedAt).toLocaleString()}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </TableContainer>
          )}
        </CardContent>
      </Card>
    </Box>
  );
};

export default ModerationPage;