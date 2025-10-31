// src/pages/SignupPage.js
import React, { useState } from "react";
import { useNavigate, Link } from "react-router-dom";
import { signup } from "../services/authService";
import {
  TextField,
  Button,
  Container,
  Typography,
  Box,
  Paper,
  Grid,
  Alert,
  CircularProgress,
} from "@mui/material";
import PeopleIcon from "@mui/icons-material/People";
import SecurityIcon from "@mui/icons-material/Security";
import TrendingUpIcon from "@mui/icons-material/TrendingUp";
import AdminPanelSettingsIcon from "@mui/icons-material/AdminPanelSettings";
import AnimatedBackground from "./AnimatedBackground";
import logo from "../assets/logo.svg";

const SignupPage = () => {
  const [formData, setFormData] = useState({
    fullName: "",
    email: "",
    password: "",
    secretKey: "",
  });
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const navigate = useNavigate();

  const handleChange = (e) => {
    setFormData({ ...formData, [e.target.name]: e.target.value });
  };

  const handleSignup = async (e) => {
    e.preventDefault();
    setError("");
    setLoading(true);

    try {
      await signup(formData);
      navigate("/dashboard"); // Redirect to dashboard on successful signup
    } catch (error) {
      console.error("Signup failed", error);
      setError(
        error.response?.data?.message || "An error occurred during signup."
      );
    } finally {
      setLoading(false);
    }
  };

  const FeatureCard = ({ icon, title, description }) => (
    <Paper
      elevation={0}
      sx={{
        p: 3,
        backgroundColor: "rgba(255, 255, 255, 0.05)",
        border: "1px solid rgba(255, 255, 255, 0.1)",
        borderRadius: 2,
        color: "white",
        height: "100%",
        transition: "all 0.3s ease",
        "&:hover": {
          backgroundColor: "rgba(255, 255, 255, 0.08)",
          border: "1px solid rgba(64, 224, 208, 0.3)",
        },
      }}
    >
      <Box sx={{ display: "flex", alignItems: "center", mb: 2 }}>
        {icon}
        <Typography variant="h6" sx={{ ml: 2, fontWeight: 600 }}>
          {title}
        </Typography>
      </Box>
      <Typography variant="body2" sx={{ color: "rgba(255, 255, 255, 0.8)" }}>
        {description}
      </Typography>
    </Paper>
  );

  return (
    <Box
      sx={{
        minHeight: "100vh",
        background: "linear-gradient(135deg, #1e3c72 0%, #2a5298 100%)",
        display: "flex",
        alignItems: "center",
        py: 4,
      }}
    >
      <AnimatedBackground />
      <Container maxWidth="lg" sx={{ position: "relative", zIndex: 1 }}>
        <Grid container spacing={6}>
          {/* Left Column - Features */}
          <Grid item xs={12} md={7}>
            <Box sx={{ mb: 4, color: "white" }}>
              {/* Logo/Brand */}
              <Box sx={{ display: "flex", alignItems: "center", mb: 4 }}>
                <Box
                  sx={{
                    width: 80,
                    height: 80,
                    borderRadius: "50%",
                    background: "white",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    mr: 3,
                    border: "3px solid rgba(255, 255, 255, 0.2)",
                    overflow: "hidden",
                  }}
                >
                  <img
                    src={logo}
                    alt="Logo"
                    style={{
                      width: "90%",
                      height: "90%",
                      objectFit: "contain",
                    }}
                  />
                </Box>
                <Typography
                  variant="h6"
                  sx={{
                    fontWeight: 700,
                    background: "linear-gradient(45deg, #00d4aa, #ffffffff)",
                    backgroundClip: "text",
                    WebkitBackgroundClip: "text",
                    WebkitTextFillColor: "transparent",
                  }}
                >
                  SLT Connect
                </Typography>
              </Box>

              {/* Main Heading */}
              <Typography
                variant="h2"
                sx={{
                  fontWeight: 700,
                  mb: 3,
                  background: "linear-gradient(45deg, #00d4aa, #ffffff)",
                  backgroundClip: "text",
                  WebkitBackgroundClip: "text",
                  WebkitTextFillColor: "transparent",
                }}
              >
                Chatapp Admin Portal
              </Typography>

              <Typography
                variant="h6"
                sx={{
                  mb: 4,
                  color: "rgba(255, 255, 255, 0.9)",
                  fontWeight: 400,
                }}
              >
                Centralized administration hub for user management,
                <br />
                moderation, and activity monitoring
              </Typography>
            </Box>

            {/* Feature Cards - Stacked vertically */}
            <Box sx={{ display: "flex", flexDirection: "column", gap: 3 }}>
              <FeatureCard
                icon={<PeopleIcon sx={{ color: "#00d4aa", fontSize: 28 }} />}
                title="User Management"
                description="Manage user accounts, permissions, and access levels"
              />

              <FeatureCard
                icon={<SecurityIcon sx={{ color: "#00d4aa", fontSize: 28 }} />}
                title="Moderation Tools"
                description="Monitor conversations and maintain community guidelines"
              />

              <FeatureCard
                icon={
                  <TrendingUpIcon sx={{ color: "#00d4aa", fontSize: 28 }} />
                }
                title="Real-time Analytics"
                description="Track platform health and receive instant alerts"
              />
            </Box>
          </Grid>

          {/* Right Column - Signup Form */}
          <Grid item xs={12} md={5}>
            <Box
              sx={{
                display: "flex",
                justifyContent: "center",
                alignItems: "center",
                height: "100%",
              }}
            >
              <Paper
                elevation={24}
                sx={{
                  p: 4,
                  borderRadius: 3,
                  backgroundColor: "rgba(255, 255, 255, 0.95)",
                  backdropFilter: "blur(20px)",
                  border: "1px solid rgba(255, 255, 255, 0.2)",
                  width: "100%",
                  maxWidth: 400,
                }}
              >
                {/* Signup Header */}
                <Box
                  sx={{
                    background:
                      "linear-gradient(135deg, #00d4aa 0%, #4169e1 100%)",
                    color: "white",
                    p: 3,
                    borderRadius: 2,
                    textAlign: "center",
                    mb: 3,
                    mx: -4,
                    mt: -4,
                  }}
                >
                  <Typography variant="h5" sx={{ fontWeight: 600 }}>
                    Create Admin Account
                  </Typography>
                  <Typography variant="body2" sx={{ opacity: 0.9, mt: 1 }}>
                    Register for administrator access
                  </Typography>
                </Box>

                {error && (
                  <Alert severity="error" sx={{ mb: 3, borderRadius: 2 }}>
                    {error}
                  </Alert>
                )}

                <Box component="form" onSubmit={handleSignup} noValidate>
                  <TextField
                    margin="normal"
                    required
                    fullWidth
                    label="Full Name"
                    name="fullName"
                    value={formData.fullName}
                    onChange={handleChange}
                    sx={{
                      mb: 2,
                      "& .MuiOutlinedInput-root": {
                        borderRadius: 2,
                        "&:hover fieldset": {
                          borderColor: "#00d4aa",
                        },
                        "&.Mui-focused fieldset": {
                          borderColor: "#00d4aa",
                        },
                      },
                      "& .MuiInputLabel-root.Mui-focused": {
                        color: "#00d4aa",
                      },
                    }}
                  />
                  <TextField
                    margin="normal"
                    required
                    fullWidth
                    label="Email Address"
                    name="email"
                    type="email"
                    value={formData.email}
                    onChange={handleChange}
                    sx={{
                      mb: 2,
                      "& .MuiOutlinedInput-root": {
                        borderRadius: 2,
                        "&:hover fieldset": {
                          borderColor: "#00d4aa",
                        },
                        "&.Mui-focused fieldset": {
                          borderColor: "#00d4aa",
                        },
                      },
                      "& .MuiInputLabel-root.Mui-focused": {
                        color: "#00d4aa",
                      },
                    }}
                  />
                  <TextField
                    margin="normal"
                    required
                    fullWidth
                    label="Password"
                    name="password"
                    type="password"
                    value={formData.password}
                    onChange={handleChange}
                    sx={{
                      mb: 2,
                      "& .MuiOutlinedInput-root": {
                        borderRadius: 2,
                        "&:hover fieldset": {
                          borderColor: "#00d4aa",
                        },
                        "&.Mui-focused fieldset": {
                          borderColor: "#00d4aa",
                        },
                      },
                      "& .MuiInputLabel-root.Mui-focused": {
                        color: "#00d4aa",
                      },
                    }}
                  />
                  <TextField
                    margin="normal"
                    required
                    fullWidth
                    label="Invitation Code"
                    name="secretKey"
                    type="password"
                    value={formData.secretKey}
                    onChange={handleChange}
                    sx={{
                      mb: 3,
                      "& .MuiOutlinedInput-root": {
                        borderRadius: 2,
                        "&:hover fieldset": {
                          borderColor: "#00d4aa",
                        },
                        "&.Mui-focused fieldset": {
                          borderColor: "#00d4aa",
                        },
                      },
                      "& .MuiInputLabel-root.Mui-focused": {
                        color: "#00d4aa",
                      },
                    }}
                  />

                  <Button
                    type="submit"
                    fullWidth
                    variant="contained"
                    disabled={loading}
                    sx={{
                      mb: 2,
                      py: 1.5,
                      borderRadius: 2,
                      background:
                        "linear-gradient(135deg, #00d4aa 0%, #4169e1 100%)",
                      fontWeight: 600,
                      fontSize: "1rem",
                      textTransform: "none",
                      boxShadow: "0 4px 15px rgba(0, 212, 170, 0.3)",
                      "&:hover": {
                        background:
                          "linear-gradient(135deg, #00c196 0%, #365ec7 100%)",
                        boxShadow: "0 6px 20px rgba(0, 212, 170, 0.4)",
                      },
                      "&:disabled": {
                        background: "rgba(0, 0, 0, 0.12)",
                      },
                    }}
                  >
                    {loading ? (
                      <CircularProgress size={24} color="inherit" />
                    ) : (
                      "Sign Up"
                    )}
                  </Button>

                  <Box sx={{ textAlign: "center", mt: 3 }}>
                    <Typography
                      component={Link}
                      to="/login"
                      variant="body2"
                      sx={{
                        color: "#4169e1",
                        textDecoration: "none",
                        fontWeight: 500,
                        "&:hover": {
                          textDecoration: "underline",
                        },
                      }}
                    >
                      Already have an account? Sign In
                    </Typography>
                  </Box>

                  {/* Footer */}
                  <Box
                    sx={{
                      textAlign: "center",
                      mt: 4,
                      pt: 3,
                      borderTop: "1px solid rgba(0, 0, 0, 0.1)",
                    }}
                  >
                    <Box
                      sx={{
                        display: "flex",
                        justifyContent: "center",
                        gap: 2,
                        mb: 2,
                      }}
                    >
                      <AdminPanelSettingsIcon
                        sx={{ color: "#00d4aa", fontSize: 20 }}
                      />
                      <Typography
                        variant="body2"
                        sx={{ fontWeight: 600, color: "#4169e1" }}
                      >
                        Admin Registration
                      </Typography>
                    </Box>

                    <br />
                    <Typography
                      variant="caption"
                      sx={{ color: "rgba(0, 0, 0, 0.5)" }}
                    >
                      © 2025 SLT Mobitel. All rights reserved.
                    </Typography>
                  </Box>
                </Box>
              </Paper>
            </Box>
          </Grid>
        </Grid>
      </Container>
    </Box>
  );
};

export default SignupPage;
