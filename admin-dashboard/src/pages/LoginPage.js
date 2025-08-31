// src/pages/LoginPage.js - DEBUG VERSION
import React, { useState } from "react";
import { useNavigate, Link } from "react-router-dom";
import { login, biometricLogin } from "../services/authService"; // ✅ Make sure both are imported
import {
  TextField,
  Button,
  Container,
  Typography,
  Box,
  Divider,
  Snackbar,
  Alert,
} from "@mui/material";
import { loginWithBiometrics } from "../services/webauthnService";
import Fingerprint from "@mui/icons-material/Fingerprint";

const LoginPage = () => {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [snackbar, setSnackbar] = useState({
    open: false,
    message: "",
    severity: "success",
  });
  const navigate = useNavigate();

  const handleLogin = async (e) => {
    e.preventDefault();
    try {
      await login(email, password);
      navigate("/dashboard");
    } catch (error) {
      console.error("Login failed", error);
      setSnackbar({
        open: true,
        message:
          error.response?.data?.message || "Login failed. Please try again.",
        severity: "error",
      });
    }
  };

  const handleBiometricLogin = async () => {
    console.log("🔍 DEBUG: Starting biometric login process");
    console.log("🔍 DEBUG: Email:", email);
    console.log(
      "🔍 DEBUG: biometricLogin function exists:",
      typeof biometricLogin
    );

    if (!email) {
      setSnackbar({
        open: true,
        message: "Please enter your Email Address to log in with biometrics.",
        severity: "warning",
      });
      return;
    }

    try {
      console.log("🔍 DEBUG: Step 1 - Starting WebAuthn verification");

      // Step 1: Perform WebAuthn verification
      const webauthnResult = await loginWithBiometrics(email);
      console.log("🔍 DEBUG: WebAuthn result:", webauthnResult);

      if (webauthnResult.verified) {
        console.log(
          "🔍 DEBUG: Step 2 - WebAuthn successful, calling biometricLogin"
        );

        // Step 2: If WebAuthn verification successful, create session
        const loginResult = await biometricLogin(email);
        console.log("🔍 DEBUG: Biometric login result:", loginResult);

        setSnackbar({
          open: true,
          message: "Biometric login successful!",
          severity: "success",
        });

        navigate("/dashboard");
      } else {
        console.log("🔍 DEBUG: WebAuthn verification failed");
        setSnackbar({
          open: true,
          message: "Biometric login failed. Please try again.",
          severity: "warning",
        });
      }
    } catch (error) {
      console.error("🔍 DEBUG: Biometric login error:", error);
      console.error("🔍 DEBUG: Error response:", error.response?.data);
      setSnackbar({
        open: true,
        message:
          error.response?.data?.message ||
          "An error occurred during biometric login.",
        severity: "error",
      });
    }
  };

  const handleCloseSnackbar = () => {
    setSnackbar({ ...snackbar, open: false });
  };

  return (
    <Container maxWidth="xs">
      <Box
        sx={{
          marginTop: 8,
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
        }}
      >
        <Typography component="h1" variant="h5">
          Admin Login
        </Typography>
        <Box component="form" onSubmit={handleLogin} sx={{ mt: 3 }}>
          <TextField
            margin="normal"
            required
            fullWidth
            id="email"
            label="Email Address"
            name="email"
            autoComplete="email"
            autoFocus
            value={email}
            onChange={(e) => setEmail(e.target.value)}
          />
          <TextField
            margin="normal"
            required
            fullWidth
            name="password"
            label="Password"
            type="password"
            id="password"
            autoComplete="current-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
          />
          <Button
            type="submit"
            fullWidth
            variant="contained"
            sx={{ mt: 3, mb: 2 }}
          >
            Sign In
          </Button>
        </Box>

        <Divider sx={{ width: "100%", my: 2 }}>OR</Divider>

        <Box sx={{ width: "100%", textAlign: "center" }}>
          <Typography variant="body1" sx={{ mb: 1 }}>
            Use Biometrics
          </Typography>
          <Button
            onClick={handleBiometricLogin}
            fullWidth
            variant="outlined"
            startIcon={<Fingerprint />}
          >
            Sign In with Biometrics
          </Button>
        </Box>

        <Box sx={{ mt: 3, textAlign: "center" }}>
          <Link to="/signup" style={{ textDecoration: "none" }}>
            {"Don't have an admin account? Sign Up"}
          </Link>
        </Box>
      </Box>

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
    </Container>
  );
};

export default LoginPage;
