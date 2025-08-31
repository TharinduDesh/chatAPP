// src/layout/DashboardLayout.js
import React, { useState, useEffect } from "react";
import { Outlet, useNavigate, Link as RouterLink } from "react-router-dom";
import {
  AppBar,
  Toolbar,
  Typography,
  Drawer,
  List,
  ListItem,
  ListItemButton,
  ListItemIcon,
  ListItemText,
  CssBaseline,
  Box,
  CircularProgress,
  Divider,
} from "@mui/material";
import DashboardIcon from "@mui/icons-material/Dashboard";
import PeopleIcon from "@mui/icons-material/People";
import AccountCircleIcon from "@mui/icons-material/AccountCircle";
import HistoryIcon from "@mui/icons-material/History";
import SpeakerNotesIcon from "@mui/icons-material/SpeakerNotes";
import LogoutIcon from "@mui/icons-material/Logout";
import { logout, getCurrentAdmin } from "../services/authService";

const drawerWidth = 240;

const menuItems = [
  { text: "Dashboard", icon: <DashboardIcon />, path: "/dashboard" },
  { text: "Profile", icon: <AccountCircleIcon />, path: "/profile" },
  { text: "Manage Users", icon: <PeopleIcon />, path: "/manage-users" },
  { text: "Moderation", icon: <SpeakerNotesIcon />, path: "/moderation" },
  { text: "Activity Log", icon: <HistoryIcon />, path: "/activity-log" },
];

const DashboardLayout = () => {
  const navigate = useNavigate();
  const [admin, setAdmin] = useState(null);
  const [loading, setLoading] = useState(true);

  // This useEffect hook safely checks for the admin user on component load.
  useEffect(() => {
    try {
      const currentAdmin = getCurrentAdmin();
      if (currentAdmin) {
        setAdmin(currentAdmin);
      } else {
        // If no admin is found in storage, log out and redirect to login
        logout();
        navigate("/login");
      }
    } catch (error) {
      console.error("Failed to parse admin data from storage:", error);
      logout();
      navigate("/login");
    } finally {
      setLoading(false);
    }
  }, [navigate]);

  const handleLogout = () => {
    logout();
    navigate("/login");
  };

  // If the component is still checking for the user, show a loading spinner
  // instead of crashing. This prevents the blank white screen.
  if (loading) {
    return (
      <Box
        sx={{
          display: "flex",
          justifyContent: "center",
          alignItems: "center",
          height: "100vh",
        }}
      >
        <CircularProgress />
      </Box>
    );
  }

  const drawer = (
    <div>
      <Toolbar />
      <Box sx={{ overflow: "auto" }}>
        <List>
          {menuItems.map((item) => (
            <ListItem key={item.text} disablePadding>
              <ListItemButton component={RouterLink} to={item.path}>
                <ListItemIcon>{item.icon}</ListItemIcon>
                <ListItemText primary={item.text} />
              </ListItemButton>
            </ListItem>
          ))}
        </List>
        <Divider />
        <List>
          <ListItem disablePadding>
            <ListItemButton onClick={handleLogout}>
              <ListItemIcon>
                <LogoutIcon sx={{ color: "error.main" }} />
              </ListItemIcon>
              <ListItemText primary="Logout" sx={{ color: "error.main" }} />
            </ListItemButton>
          </ListItem>
        </List>
      </Box>
    </div>
  );

  return (
    <Box sx={{ display: "flex" }}>
      <CssBaseline />
      <AppBar
        position="fixed"
        sx={{ zIndex: (theme) => theme.zIndex.drawer + 1 }}
      >
        <Toolbar>
          <Typography variant="h6" noWrap component="div" sx={{ flexGrow: 1 }}>
            {/* Safely display the admin's name, with a fallback */}
            Welcome, {admin?.fullName || admin?.email || "Admin"}
          </Typography>
        </Toolbar>
      </AppBar>
      <Drawer
        variant="permanent"
        sx={{
          width: drawerWidth,
          flexShrink: 0,
          [`& .MuiDrawer-paper`]: {
            width: drawerWidth,
            boxSizing: "border-box",
          },
        }}
      >
        {drawer}
      </Drawer>
      <Box component="main" sx={{ flexGrow: 1, p: 3 }}>
        <Toolbar />
        {/* The Outlet renders the specific page component (e.g., DashboardPage) */}
        <Outlet />
      </Box>
    </Box>
  );
};

export default DashboardLayout;
