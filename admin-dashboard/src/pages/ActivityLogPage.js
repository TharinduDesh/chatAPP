// src/pages/ActivityLogPage.js
import React, { useState, useEffect, useCallback } from "react";
import { getActivityLogs } from "../services/activityLogService";
import {
  Box,
  Typography,
  Paper,
  List,
  ListItem,
  ListItemText,
  Divider,
  CircularProgress,
  TextField,
  InputAdornment,
  Chip,
  Pagination,
} from "@mui/material";
import SearchIcon from "@mui/icons-material/Search";

// Helper to give each action type a color for better visuals
const getActionChipColor = (action) => {
  switch (action) {
    case "CREATED_USER":
    case "RESTORED_USER":
      return "success";
    case "EDITED_USER":
    case "UNBANNED_USER":
      return "info";
    case "BANNED_USER":
      return "warning";
    case "DEACTIVATED_USER":
    case "PERMANENTLY_DELETED_USER":
      return "error";
    default:
      return "default";
  }
};

const formatActionText = (log) => {
  const actionMap = {
    CREATED_USER: "created user",
    EDITED_USER: "edited user",
    DEACTIVATED_USER: "deactivated user",
    RESTORED_USER: "restored user",
    PERMANENTLY_DELETED_USER: "permanently deleted user",
    BANNED_USER: "banned user",
    UNBANNED_USER: "unbanned user",
  };
  return (
    <span>
      <strong>{log.adminName}</strong>{" "}
      {actionMap[log.action] || "performed an action on"}{" "}
      <strong>{log.targetName}</strong>.
    </span>
  );
};

const ActivityLogPage = () => {
  const [logs, setLogs] = useState([]);
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState("");
  const [page, setPage] = useState(1);
  const [totalPages, setTotalPages] = useState(0);

  // ✅ FIX: This callback is now stable and will not be recreated on every render.
  const fetchLogs = useCallback(async (pageNum, search) => {
    setLoading(true);
    try {
      const data = await getActivityLogs(pageNum, search);
      setLogs(data.logs);
      setTotalPages(data.totalPages);
    } catch (error) {
      console.error("Failed to fetch activity logs", error);
    } finally {
      setLoading(false);
    }
  }, []); // Empty dependency array because the function doesn't depend on component state

  // ✅ FIX: This effect handles the debouncing of the search term.
  useEffect(() => {
    const handler = setTimeout(() => {
      // When the timer fires, we fetch logs for the current search term,
      // always resetting to page 1 for a new search.
      setPage(1); // Reset page on new search
      fetchLogs(1, searchTerm);
    }, 500); // 500ms delay

    // This cleanup function cancels the timer if the user keeps typing
    return () => {
      clearTimeout(handler);
    };
  }, [searchTerm, fetchLogs]); // Re-run this effect only when searchTerm or fetchLogs changes

  // ✅ FIX: This effect handles pagination changes.
  useEffect(() => {
    // We only want this to run when the page number changes,
    // and not when the search term is being debounced.
    // The previous effect already handles fetching for new search terms.
    fetchLogs(page, searchTerm);
  }, [page, searchTerm, fetchLogs]); // Re-run only when the page number changes.

  const handlePageChange = (event, value) => {
    // Prevent fetching again if the search effect is about to run
    if (value !== page) {
      setPage(value);
    }
  };

  return (
    <Box>
      <Typography variant="h4" gutterBottom>
        Admin Activity Log
      </Typography>

      <TextField
        label="Search Logs"
        variant="outlined"
        fullWidth
        margin="normal"
        value={searchTerm} // Controlled component
        onChange={(e) => setSearchTerm(e.target.value)}
        InputProps={{
          startAdornment: (
            <InputAdornment position="start">
              <SearchIcon />
            </InputAdornment>
          ),
        }}
      />

      <Paper>
        <List>
          {loading ? (
            <Box sx={{ display: "flex", justifyContent: "center", p: 4 }}>
              <CircularProgress />
            </Box>
          ) : (
            logs.map((log, index) => (
              <React.Fragment key={log._id}>
                <ListItem
                  secondaryAction={
                    <Chip
                      label={log.action.replace(/_/g, " ")}
                      color={getActionChipColor(log.action)}
                      size="small"
                    />
                  }
                >
                  <ListItemText
                    primary={formatActionText(log)}
                    secondary={
                      <>
                        <Typography
                          component="span"
                          variant="body2"
                          color="text.secondary"
                        >
                          {new Date(log.timestamp).toLocaleString()}
                        </Typography>
                        {log.details && ` — Details: ${log.details}`}
                      </>
                    }
                  />
                </ListItem>
                {index < logs.length - 1 && <Divider component="li" />}
              </React.Fragment>
            ))
          )}
        </List>
      </Paper>
      <Box sx={{ display: "flex", justifyContent: "center", p: 2, mt: 2 }}>
        <Pagination
          count={totalPages}
          page={page}
          onChange={handlePageChange}
          color="primary"
          disabled={loading} // Disable pagination while loading
        />
      </Box>
    </Box>
  );
};

export default ActivityLogPage;
