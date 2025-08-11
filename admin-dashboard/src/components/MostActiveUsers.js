// src/components/MostActiveUsers.js
import React, { useState, useEffect } from "react";
import { getMostActiveUsers } from "../services/analyticsService";
import {
  Box,
  List,
  ListItem,
  ListItemText,
  Divider,
  CircularProgress,
  Card,
  CardContent,
  CardHeader,
  Avatar,
  ListItemAvatar,
} from "@mui/material";

const MostActiveUsers = () => {
  const [users, setUsers] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchActiveUsers = async () => {
      try {
        const data = await getMostActiveUsers();
        setUsers(data);
      } catch (error) {
        console.error("Failed to fetch most active users", error);
      } finally {
        setLoading(false);
      }
    };
    fetchActiveUsers();
  }, []);

  return (
    <Card>
      <CardHeader title="Most Active Users" />
      <CardContent>
        {loading ? (
          <Box sx={{ display: "flex", justifyContent: "center", p: 2 }}>
            <CircularProgress />
          </Box>
        ) : (
          <List sx={{ p: 0 }}>
            {users.map((user, index) => (
              <React.Fragment key={user.userId}>
                <ListItem>
                  <ListItemAvatar>
                    <Avatar
                      src={
                        user.profilePictureUrl
                          ? `http://localhost:5000${user.profilePictureUrl}`
                          : "/default-avatar.png"
                      }
                    >
                      {user.fullName.charAt(0)}
                    </Avatar>
                  </ListItemAvatar>
                  <ListItemText
                    primary={user.fullName}
                    secondary={`${user.messageCount} messages sent`}
                  />
                </ListItem>
                {index < users.length - 1 && <Divider />}
              </React.Fragment>
            ))}
          </List>
        )}
      </CardContent>
    </Card>
  );
};

export default MostActiveUsers;
