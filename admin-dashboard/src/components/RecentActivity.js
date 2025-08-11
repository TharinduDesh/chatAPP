// src/components/RecentActivity.js
import React, { useState, useEffect } from "react";
import { getRecentActivityLogs } from "../services/activityLogService";
import {
  Box,
  List,
  ListItem,
  ListItemText,
  Divider,
  CircularProgress,
  Button,
  Card,
  CardContent,
  CardHeader,
} from "@mui/material";
import { useNavigate } from "react-router-dom";

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

const RecentActivity = () => {
  const [logs, setLogs] = useState([]);
  const [loading, setLoading] = useState(true);
  const navigate = useNavigate();

  useEffect(() => {
    const fetchRecentLogs = async () => {
      try {
        const data = await getRecentActivityLogs();
        setLogs(data);
      } catch (error) {
        console.error("Failed to fetch recent logs", error);
      } finally {
        setLoading(false);
      }
    };
    fetchRecentLogs();
  }, []);

  return (
    <Card>
      <CardHeader title="Recent Admin Activity" />
      <CardContent>
        {loading ? (
          <Box sx={{ display: "flex", justifyContent: "center", p: 2 }}>
            <CircularProgress />
          </Box>
        ) : (
          <List sx={{ p: 0 }}>
            {logs.map((log, index) => (
              <React.Fragment key={log._id}>
                <ListItem>
                  <ListItemText
                    primary={formatActionText(log)}
                    secondary={new Date(log.timestamp).toLocaleString()}
                  />
                </ListItem>
                {index < logs.length - 1 && <Divider />}
              </React.Fragment>
            ))}
          </List>
        )}
        <Box sx={{ mt: 2, textAlign: "right" }}>
          <Button onClick={() => navigate("/activity-log")}>
            View All Logs
          </Button>
        </Box>
      </CardContent>
    </Card>
  );
};

export default RecentActivity;
