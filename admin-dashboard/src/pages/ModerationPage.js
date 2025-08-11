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
  CircularProgress, // Import CircularProgress
} from "@mui/material";

const ModerationPage = () => {
  const [conversations, setConversations] = useState([]);
  // ✅ FIX: Correctly destructure both `loading` and `setLoading` from useState
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
    // ✅ FIX: Add setLoading to the dependency array to remove the warning
  }, [setLoading]);

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
    return convo.participants.map((p) => p.fullName).join(" & ");
  };

  return (
    <Box>
      <Typography variant="h4" gutterBottom>
        Conversation Moderation
      </Typography>
      <TextField
        label="Search by Group Name or Participant"
        variant="outlined"
        fullWidth
        margin="normal"
        value={filter}
        onChange={(e) => setFilter(e.target.value)}
      />
      {loading ? (
        <Box sx={{ display: "flex", justifyContent: "center", mt: 4 }}>
          <CircularProgress />
        </Box>
      ) : (
        <TableContainer component={Paper}>
          <Table>
            <TableHead>
              <TableRow>
                <TableCell>Conversation</TableCell>
                <TableCell>Participants</TableCell>
                <TableCell>Type</TableCell>
                <TableCell>Last Activity</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {filteredConversations.map((convo) => (
                <TableRow
                  key={convo._id}
                  hover
                  sx={{ cursor: "pointer" }}
                  onClick={() => navigate(`/moderation/${convo._id}`)}
                >
                  <TableCell>{getConversationTitle(convo)}</TableCell>
                  <TableCell>
                    <AvatarGroup max={4}>
                      {convo.participants.map((p) => (
                        <Avatar key={p._id} alt={p.fullName}>
                          {p.fullName.charAt(0)}
                        </Avatar>
                      ))}
                    </AvatarGroup>
                  </TableCell>
                  <TableCell>
                    <Chip
                      label={convo.isGroupChat ? "Group" : "One-on-One"}
                      size="small"
                    />
                  </TableCell>
                  <TableCell>
                    {new Date(convo.updatedAt).toLocaleString()}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </TableContainer>
      )}
    </Box>
  );
};

export default ModerationPage;
