// src/pages/ProfilePage.js
import React, { useState, useEffect } from "react";
import {
  getAdminProfile,
  updateAdminProfile,
  changeAdminPassword,
} from "../services/authService";
import {
  Box,
  Typography,
  Grid,
  Card,
  CardContent,
  TextField,
  Button,
  Avatar,
  CircularProgress,
  Snackbar,
  Alert,
  alpha,
  useTheme,
} from "@mui/material";
import { deepOrange } from "@mui/material/colors";
import { registerBiometrics } from "../services/webauthnService";
import AccountCircleIcon from "@mui/icons-material/AccountCircle";
import SecurityIcon from "@mui/icons-material/Security";
import FingerprintIcon from "@mui/icons-material/Fingerprint";

const ProfilePage = () => {
  const theme = useTheme();
  const [admin, setAdmin] = useState(null);
  const [formData, setFormData] = useState({ fullName: "", email: "" });
  const [passwordData, setPasswordData] = useState({
    currentPassword: "",
    newPassword: "",
    confirmPassword: "",
  });
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [changingPassword, setChangingPassword] = useState(false);
  const [snackbar, setSnackbar] = useState({
    open: false,
    message: "",
    severity: "success",
  });

  useEffect(() => {
    const fetchAdminProfile = async () => {
      try {
        const data = await getAdminProfile();
        setAdmin(data);
        setFormData({ fullName: data.fullName, email: data.email });
      } catch (error) {
        console.error("Failed to fetch admin profile", error);
        setSnackbar({
          open: true,
          message: "Failed to load profile.",
          severity: "error",
        });
      } finally {
        setLoading(false);
      }
    };
    fetchAdminProfile();
  }, []);

  const handleChange = (e) => {
    setFormData({ ...formData, [e.target.name]: e.target.value });
  };

  const handlePasswordChange = (e) => {
    setPasswordData({ ...passwordData, [e.target.name]: e.target.value });
  };

  const handleSaveChanges = async (e) => {
    e.preventDefault();
    setSaving(true);
    try {
      const updatedAdmin = await updateAdminProfile(formData);
      setAdmin(updatedAdmin);
      setSnackbar({
        open: true,
        message: "Profile updated successfully!",
        severity: "success",
      });
    } catch (error) {
      console.error("Failed to update profile", error);
      setSnackbar({
        open: true,
        message: "Failed to update profile.",
        severity: "error",
      });
    } finally {
      setSaving(false);
    }
  };

  const handleChangePasswordSubmit = async (e) => {
    e.preventDefault();
    if (passwordData.newPassword !== passwordData.confirmPassword) {
      setSnackbar({
        open: true,
        message: "New passwords do not match.",
        severity: "error",
      });
      return;
    }
    setChangingPassword(true);
    try {
      const result = await changeAdminPassword({
        currentPassword: passwordData.currentPassword,
        newPassword: passwordData.newPassword,
      });
      setSnackbar({ open: true, message: result.message, severity: "success" });
      setPasswordData({
        currentPassword: "",
        newPassword: "",
        confirmPassword: "",
      });
    } catch (error) {
      const message =
        error.response?.data?.message || "Failed to change password.";
      setSnackbar({ open: true, message: message, severity: "error" });
    } finally {
      setChangingPassword(false);
    }
  };

  const handleRegisterBiometrics = async () => {
    if (!admin || !admin.email || !admin._id) {
      setSnackbar({
        open: true,
        message: "Admin data not available. Please refresh the page.",
        severity: "error",
      });
      return;
    }

    try {
      const { verified } = await registerBiometrics(admin.email, admin._id);
      if (verified) {
        setSnackbar({
          open: true,
          message: "Biometrics registered successfully!",
          severity: "success",
        });
      } else {
        setSnackbar({
          open: true,
          message:
            "Biometric registration failed. The request was denied or timed out.",
          severity: "warning",
        });
      }
    } catch (error) {
      console.error("Biometric registration error:", error);
      setSnackbar({
        open: true,
        message:
          error.response?.data?.message ||
          "An error occurred during biometric registration.",
        severity: "error",
      });
    }
  };

  const handleCloseSnackbar = () => {
    setSnackbar({ ...snackbar, open: false });
  };

  if (loading) {
    return (
      <Box
        sx={{
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          minHeight: "60vh",
          gap: 2,
        }}
      >
        <CircularProgress size={60} />
        <Typography variant="h6" color="text.secondary">
          Loading profile...
        </Typography>
      </Box>
    );
  }

  if (!admin) {
    return (
      <Box sx={{ textAlign: "center", p: 4 }}>
        <Typography variant="h6" color="error">
          Could not load admin profile.
        </Typography>
      </Box>
    );
  }

  return (
    <Box>
      {/* Header Section */}
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
          }}
        >
          My Profile
        </Typography>
        <Typography variant="body1" color="text.secondary">
          Manage your account settings and security preferences
        </Typography>
      </Box>

      <Grid container spacing={3}>
        {/* Profile Details Card */}
        <Grid item xs={12} lg={6}>
          <Card
            sx={{
              borderRadius: 3,
              border: "1px solid",
              borderColor: "divider",
              height: "100%",
            }}
          >
            <CardContent sx={{ p: 3 }}>
              <Box
                sx={{
                  display: "flex",
                  alignItems: "center",
                  mb: 4,
                  p: 2,
                  bgcolor: alpha(theme.palette.primary.main, 0.03),
                  borderRadius: 2,
                }}
              >
                <Box
                  sx={{
                    p: 2,
                    bgcolor: theme.palette.primary.main,
                    color: "white",
                    borderRadius: 2,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    mr: 2,
                  }}
                >
                  <AccountCircleIcon sx={{ fontSize: 28 }} />
                </Box>
                <Box>
                  <Typography variant="h6" sx={{ fontWeight: 600 }}>
                    Profile Information
                  </Typography>
                  <Typography variant="body2" color="text.secondary">
                    Update your personal details
                  </Typography>
                </Box>
              </Box>

              <Box sx={{ display: "flex", alignItems: "center", mb: 3 }}>
                <Avatar
                  sx={{
                    bgcolor: deepOrange[500],
                    width: 64,
                    height: 64,
                    mr: 2,
                    fontSize: "2rem",
                    fontWeight: 600,
                  }}
                >
                  {admin.fullName.charAt(0).toUpperCase()}
                </Avatar>
                <Box>
                  <Typography variant="h5" sx={{ fontWeight: 600 }}>
                    {admin.fullName}
                  </Typography>
                  <Typography variant="body2" color="text.secondary">
                    {admin.email}
                  </Typography>
                </Box>
              </Box>

              <form onSubmit={handleSaveChanges}>
                <TextField
                  label="Full Name"
                  name="fullName"
                  value={formData.fullName}
                  onChange={handleChange}
                  fullWidth
                  margin="normal"
                  sx={{ mb: 2 }}
                />
                <TextField
                  label="Email Address"
                  name="email"
                  type="email"
                  value={formData.email}
                  onChange={handleChange}
                  fullWidth
                  margin="normal"
                  sx={{ mb: 3 }}
                />
                <Box sx={{ position: "relative" }}>
                  <Button
                    type="submit"
                    variant="contained"
                    disabled={saving}
                    sx={{
                      background:
                        "linear-gradient(135deg, #00d4aa 0%, #4169e1 100%)",
                      "&:hover": {
                        background:
                          "linear-gradient(135deg, #00c4a0 0%, #3159d1 100%)",
                      },
                      minWidth: 140,
                    }}
                  >
                    {saving ? "Saving..." : "Save Changes"}
                  </Button>
                  {saving && (
                    <CircularProgress
                      size={24}
                      sx={{
                        position: "absolute",
                        top: "50%",
                        left: "50%",
                        marginTop: "-12px",
                        marginLeft: "-12px",
                      }}
                    />
                  )}
                </Box>
              </form>
            </CardContent>
          </Card>
        </Grid>

        {/* Security Section */}
        <Grid item xs={12} lg={6}>
          {/* Change Password Card */}
          <Card
            sx={{
              borderRadius: 3,
              border: "1px solid",
              borderColor: "divider",
              mb: 3,
            }}
          >
            <CardContent sx={{ p: 3 }}>
              <Box
                sx={{
                  display: "flex",
                  alignItems: "center",
                  mb: 3,
                  p: 2,
                  bgcolor: alpha(theme.palette.warning.main, 0.03),
                  borderRadius: 2,
                }}
              >
                <Box
                  sx={{
                    p: 2,
                    bgcolor: theme.palette.warning.main,
                    color: "white",
                    borderRadius: 2,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    mr: 2,
                  }}
                >
                  <SecurityIcon sx={{ fontSize: 28 }} />
                </Box>
                <Box>
                  <Typography variant="h6" sx={{ fontWeight: 600 }}>
                    Change Password
                  </Typography>
                  <Typography variant="body2" color="text.secondary">
                    Update your login credentials
                  </Typography>
                </Box>
              </Box>

              <form onSubmit={handleChangePasswordSubmit}>
                <TextField
                  label="Current Password"
                  name="currentPassword"
                  type="password"
                  value={passwordData.currentPassword}
                  onChange={handlePasswordChange}
                  fullWidth
                  margin="normal"
                  required
                  sx={{ mb: 2 }}
                />
                <TextField
                  label="New Password"
                  name="newPassword"
                  type="password"
                  value={passwordData.newPassword}
                  onChange={handlePasswordChange}
                  fullWidth
                  margin="normal"
                  required
                  sx={{ mb: 2 }}
                />
                <TextField
                  label="Confirm New Password"
                  name="confirmPassword"
                  type="password"
                  value={passwordData.confirmPassword}
                  onChange={handlePasswordChange}
                  fullWidth
                  margin="normal"
                  required
                  sx={{ mb: 3 }}
                />
                <Box sx={{ position: "relative" }}>
                  <Button
                    type="submit"
                    variant="contained"
                    disabled={changingPassword}
                    sx={{
                      background:
                        "linear-gradient(135deg, #ff9500 0%, #ff5e3a 100%)",
                      "&:hover": {
                        background:
                          "linear-gradient(135deg, #e08500 0%, #e04e2a 100%)",
                      },
                      minWidth: 160,
                    }}
                  >
                    {changingPassword ? "Updating..." : "Change Password"}
                  </Button>
                  {changingPassword && (
                    <CircularProgress
                      size={24}
                      sx={{
                        position: "absolute",
                        top: "50%",
                        left: "50%",
                        marginTop: "-12px",
                        marginLeft: "-12px",
                      }}
                    />
                  )}
                </Box>
              </form>
            </CardContent>
          </Card>

          {/* Biometrics Card */}
          <Card
            sx={{
              borderRadius: 3,
              border: "1px solid",
              borderColor: "divider",
            }}
          >
            <CardContent sx={{ p: 3 }}>
              <Box
                sx={{
                  display: "flex",
                  alignItems: "center",
                  mb: 3,
                  p: 2,
                  bgcolor: alpha(theme.palette.success.main, 0.03),
                  borderRadius: 2,
                }}
              >
                <Box
                  sx={{
                    p: 2,
                    bgcolor: theme.palette.success.main,
                    color: "white",
                    borderRadius: 2,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    mr: 2,
                  }}
                >
                  <FingerprintIcon sx={{ fontSize: 28 }} />
                </Box>
                <Box>
                  <Typography variant="h6" sx={{ fontWeight: 600 }}>
                    Biometric Authentication
                  </Typography>
                  <Typography variant="body2" color="text.secondary">
                    Secure, passwordless login experience
                  </Typography>
                </Box>
              </Box>

              <Typography variant="body2" color="text.secondary" sx={{ mb: 3 }}>
                Register your device's fingerprint or face ID for a secure,
                passwordless login experience.
              </Typography>

              <Button
                onClick={handleRegisterBiometrics}
                variant="outlined"
                sx={{
                  borderColor: theme.palette.success.main,
                  color: theme.palette.success.main,
                  "&:hover": {
                    borderColor: theme.palette.success.dark,
                    backgroundColor: alpha(theme.palette.success.main, 0.04),
                  },
                }}
              >
                Register This Device
              </Button>
            </CardContent>
          </Card>
        </Grid>
      </Grid>

      <Snackbar
        open={snackbar.open}
        autoHideDuration={6000}
        onClose={handleCloseSnackbar}
        anchorOrigin={{ vertical: "bottom", horizontal: "right" }}
      >
        <Alert
          onClose={handleCloseSnackbar}
          severity={snackbar.severity}
          sx={{
            width: "100%",
            borderRadius: 2,
            boxShadow: theme.shadows[8],
          }}
        >
          {snackbar.message}
        </Alert>
      </Snackbar>
    </Box>
  );
};

export default ProfilePage;
