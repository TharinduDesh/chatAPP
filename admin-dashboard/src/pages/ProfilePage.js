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
} from "@mui/material";
import { deepOrange } from "@mui/material/colors";
import { registerBiometrics } from "../services/webauthnService";

const ProfilePage = () => {
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
      }); // Reset form
    } catch (error) {
      const message =
        error.response?.data?.message || "Failed to change password.";
      setSnackbar({ open: true, message: message, severity: "error" });
    } finally {
      setChangingPassword(false);
    }
  };

  // ------------------- NEW: Handle Biometric Registration -------------------
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
      // Use updated registerBiometrics helper
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
      <Box sx={{ display: "flex", justifyContent: "center", mt: 4 }}>
        <CircularProgress />
      </Box>
    );
  }

  if (!admin) {
    return <Typography>Could not load admin profile.</Typography>;
  }

  return (
    <Box>
      <Typography variant="h4" gutterBottom>
        My Profile
      </Typography>
      <Grid container spacing={3}>
        {/* Profile Details Card */}
        <Grid item xs={12} md={6}>
          <Card>
            <CardContent>
              <Box sx={{ display: "flex", alignItems: "center", mb: 3 }}>
                <Avatar
                  sx={{
                    bgcolor: deepOrange[500],
                    width: 64,
                    height: 64,
                    mr: 2,
                    fontSize: "2rem",
                  }}
                >
                  {admin.fullName.charAt(0)}
                </Avatar>
                <Box>
                  <Typography variant="h5">{admin.fullName}</Typography>
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
                />
                <TextField
                  label="Email Address"
                  name="email"
                  type="email"
                  value={formData.email}
                  onChange={handleChange}
                  fullWidth
                  margin="normal"
                />
                <Box sx={{ mt: 2, position: "relative" }}>
                  <Button type="submit" variant="contained" disabled={saving}>
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

        {/* Change Password & Biometrics Card */}
        <Grid item xs={12} md={6}>
          {/* Change Password Card */}
          <Card sx={{ mb: 3 }}>
            <CardContent>
              <Typography variant="h6" gutterBottom>
                Change Password
              </Typography>
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
                />
                <Box sx={{ mt: 2, position: "relative" }}>
                  <Button
                    type="submit"
                    variant="contained"
                    disabled={changingPassword}
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
          <Card>
            <CardContent>
              <Typography variant="h6" gutterBottom>
                Biometric Authentication
              </Typography>
              <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
                Register your device's fingerprint or face ID for a secure,
                passwordless login experience.
              </Typography>
              <Button onClick={handleRegisterBiometrics} variant="outlined">
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
      >
        <Alert
          onClose={handleCloseSnackbar}
          severity={snackbar.severity}
          sx={{ width: "100%" }}
        >
          {snackbar.message}
        </Alert>
      </Snackbar>
    </Box>
  );
};

export default ProfilePage;
