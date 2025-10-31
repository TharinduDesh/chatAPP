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
  alpha,
  useTheme,
  Card,
  CardContent,
  Button,
  ButtonGroup,
} from "@mui/material";
import SearchIcon from "@mui/icons-material/Search";
import HistoryIcon from "@mui/icons-material/History";
import FilterListIcon from "@mui/icons-material/FilterList";
import { subDays, startOfMonth } from "date-fns";

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
      <span style={{ fontWeight: 600 }}>
        {actionMap[log.action] || "performed an action on"}
      </span>{" "}
      <strong>{log.targetName}</strong>.
    </span>
  );
};

const ActivityLogPage = () => {
  const theme = useTheme();
  const [logs, setLogs] = useState([]);
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState("");
  const [page, setPage] = useState(1);
  const [totalPages, setTotalPages] = useState(0);
  const [filterPeriod, setFilterPeriod] = useState("all");

  const fetchLogs = useCallback(async (pageNum, search, period) => {
    setLoading(true);
    let startDate = null;
    let endDate = new Date();

    if (period === "week") {
      startDate = subDays(endDate, 7);
    } else if (period === "month") {
      startDate = startOfMonth(endDate);
    }

    try {
      const data = await getActivityLogs(pageNum, search, startDate, endDate);
      setLogs(data.logs);
      setTotalPages(data.totalPages);
    } catch (error) {
      console.error("Failed to fetch activity logs", error);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    const handler = setTimeout(() => {
      setPage(1);
      fetchLogs(1, searchTerm, filterPeriod);
    }, 500);

    return () => clearTimeout(handler);
  }, [searchTerm, fetchLogs, filterPeriod]);

  useEffect(() => {
    fetchLogs(page, searchTerm, filterPeriod);
  }, [page, searchTerm, fetchLogs, filterPeriod]);

  const handlePageChange = (event, value) => {
    if (value !== page) {
      setPage(value);
    }
  };

  const handleFilterChange = (period) => {
    setFilterPeriod(period);
    setPage(1);
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
            animation: "fadeIn 1s ease-in-out",
            "@keyframes fadeIn": {
              "0%": { opacity: 0, transform: "translateY(20px)" },
              "100%": { opacity: 1, transform: "translateY(0)" },
            },
          }}
        >
          Activity Log
        </Typography>
        <Typography variant="body1" color="text.secondary">
          Track all administrative actions and system activities
        </Typography>
      </Box>

      <Paper
        elevation={0}
        sx={{
          p: 3,
          mb: 4,
          borderRadius: 3,
          border: "1px solid",
          borderColor: "divider",
          background:
            "linear-gradient(135deg, rgba(255, 255, 255, 0.8) 0%, rgba(255, 255, 255, 0.4) 100%)",
          backdropFilter: "blur(10px)",
        }}
      >
        <Box
          sx={{
            display: "flex",
            gap: 3,
            flexWrap: "wrap",
            alignItems: "center",
            justifyContent: "space-between",
          }}
        >
          <TextField
            label="Search activities..."
            variant="outlined"
            sx={{ minWidth: 300, flexGrow: 1 }}
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            InputProps={{
              startAdornment: (
                <InputAdornment position="start">
                  <SearchIcon />
                </InputAdornment>
              ),
            }}
          />

          <Box sx={{ display: "flex", alignItems: "center", gap: 2 }}>
            <FilterListIcon sx={{ color: "text.secondary" }} />
            <ButtonGroup variant="outlined" size="small">
              <Button
                onClick={() => handleFilterChange("all")}
                sx={{
                  ...((filterPeriod === "all" && {
                    background: "linear-gradient(135deg, #00d4aa 0%, #4169e1 100%)",
                    color: "white",
                    "&:hover": {
                      background: "linear-gradient(135deg, #00c196 0%, #365ec7 100%)",
                      boxShadow: theme.shadows[2],
                    },
                  }) || {}),
                }}
              >
                All Time
              </Button>
              <Button
                onClick={() => handleFilterChange("week")}
                sx={{
                  ...((filterPeriod === "week" && {
                    background: "linear-gradient(135deg, #00d4aa 0%, #4169e1 100%)",
                    color: "white",
                    "&:hover": {
                      background: "linear-gradient(135deg, #00c196 0%, #365ec7 100%)",
                      boxShadow: theme.shadows[2],
                    },
                  }) || {}),
                }}
              >
                This Week
              </Button>
              <Button
                onClick={() => handleFilterChange("month")}
                sx={{
                  ...((filterPeriod === "month" && {
                    background: "linear-gradient(135deg, #00d4aa 0%, #4169e1 100%)",
                    color: "white",
                    "&:hover": {
                      background: "linear-gradient(135deg, #00c196 0%, #365ec7 100%)",
                      boxShadow: theme.shadows[2],
                    },
                  }) || {}),
                }}
              >
                This Month
              </Button>
            </ButtonGroup>
          </Box>
        </Box>
      </Paper>

      <Card
        sx={{
          borderRadius: 3,
          border: "1px solid",
          borderColor: "divider",
          overflow: "hidden",
          boxShadow: theme.shadows[4],
        }}
      >
        <CardContent sx={{ p: 0 }}>
          <Box
            sx={{
              p: 3,
              bgcolor: alpha(theme.palette.primary.main, 0.03),
              borderBottom: "1px solid",
              borderColor: "divider",
              display: "flex",
              alignItems: "center",
              gap: 2,
            }}
          >
            <Box
              sx={{
                p: 1.5,
                bgcolor: theme.palette.primary.main,
                color: "white",
                borderRadius: 2,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
              }}
            >
              <HistoryIcon sx={{ fontSize: 24 }} />
            </Box>
            <Box>
              <Typography variant="h6" sx={{ fontWeight: 600 }}>
                Recent Activities
              </Typography>
              <Typography variant="body2" color="text.secondary">
                {totalPages > 0
                  ? `Page ${page} of ${totalPages} total actions`
                  : "No activities found"}
              </Typography>
            </Box>
          </Box>

          <List sx={{ p: 0 }}>
            {loading ? (
              <Box sx={{ display: "flex", justifyContent: "center", p: 6 }}>
                <CircularProgress size={40} />
              </Box>
            ) : logs.length === 0 ? (
              <Box sx={{ textAlign: "center", p: 6 }}>
                <Typography variant="body1" color="text.secondary">
                  {searchTerm
                    ? "No activities match your search"
                    : "No activities found"}
                </Typography>
              </Box>
            ) : (
              logs.map((log, index) => (
                <React.Fragment key={log._id}>
                  <ListItem
                    sx={{
                      px: 3,
                      py: 2.5,
                      transition: "all 0.3s ease",
                      "&:hover": {
                        bgcolor: alpha(theme.palette.primary.main, 0.04),
                        transform: "translateY(-2px)",
                        boxShadow: `0 4px 10px ${alpha(
                          theme.palette.primary.main,
                          0.1
                        )}`,
                      },
                    }}
                    secondaryAction={
                      <Chip
                        label={log.action.replace(/_/g, " ")}
                        color={getActionChipColor(log.action)}
                        size="small"
                        sx={{
                          fontWeight: 600,
                          minWidth: 120,
                        }}
                      />
                    }
                  >
                    <ListItemText
                      primary={formatActionText(log)}
                      secondary={
                        <Box sx={{ mt: 0.5 }}>
                          <Typography
                            component="span"
                            variant="body2"
                            color="text.secondary"
                            sx={{ display: "block", mb: 0.5 }}
                          >
                            {new Date(log.timestamp).toLocaleString()}
                          </Typography>
                          {log.details && (
                            <Typography
                              variant="caption"
                              sx={{
                                color: "text.secondary",
                                fontStyle: "italic",
                              }}
                            >
                              Details: {log.details}
                            </Typography>
                          )}
                        </Box>
                      }
                      sx={{ m: 0 }}
                    />
                  </ListItem>
                  {index < logs.length - 1 && (
                    <Divider
                      component="li"
                      sx={{
                        mx: 3,
                        borderColor: alpha(theme.palette.divider, 0.5),
                      }}
                    />
                  )}
                </React.Fragment>
              ))
            )}
          </List>
        </CardContent>
      </Card>

      {totalPages > 1 && (
        <Box
          sx={{
            display: "flex",
            justifyContent: "center",
            p: 3,
            mt: 2,
          }}
        >
          <Pagination
            count={totalPages}
            page={page}
            onChange={handlePageChange}
            color="primary"
            disabled={loading}
            sx={{
              "& .MuiPaginationItem-root": {
                borderRadius: 2,
                fontWeight: 600,
                transition: "all 0.3s ease",
                "&:hover": {
                  bgcolor: alpha(theme.palette.primary.main, 0.05),
                },
              },
              "& .Mui-selected": {
                background:
                  "linear-gradient(135deg, #00d4aa 0%, #4169e1 100%)",
                color: "white",
                "&:hover": {
                  background:
                    "linear-gradient(135deg, #00d4aa 0%, #4169e1 100%)",
                  boxShadow: theme.shadows[2],
                },
              },
            }}
          />
        </Box>
      )}
    </Box>
  );
};

export default ActivityLogPage;