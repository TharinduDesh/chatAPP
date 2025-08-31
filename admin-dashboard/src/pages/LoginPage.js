// src/pages/LoginPage.js
import React, { useState, useEffect } from "react";
import {
  Container,
  TextField,
  Button,
  Typography,
  Box,
  Alert,
  CircularProgress,
  Paper,
} from "@mui/material";
import FingerprintIcon from "@mui/icons-material/Fingerprint";
import { Link, useNavigate } from "react-router-dom";
import { login, getCurrentAdmin } from "../services/authService";
import {
  getAuthenticationOptions,
  verifyAuthentication,
} from "../services/webauthnService";
import { startAuthentication } from "@simplewebauthn/browser";

const LoginPage = () => {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const [biometricLoading, setBiometricLoading] = useState(false);
  const navigate = useNavigate();

  useEffect(() => {
    // If user is already logged in, redirect to dashboard
    if (getCurrentAdmin()) {
      navigate("/dashboard");
    }
  }, [navigate]);

  const handleLogin = async (e) => {
    e.preventDefault();
    setError("");
    setLoading(true);

    if (!email || !password) {
      setError("Please provide both email and password.");
      setLoading(false);
      return;
    }

    try {
      await login(email, password);
      navigate("/dashboard");
    } catch (err) {
      setError(
        err.response?.data?.message || "Login failed. Please try again."
      );
    } finally {
      setLoading(false);
    }
  };

  const handleBiometricLogin = async () => {
    setError("");
    setBiometricLoading(true);
    try {
      // 1. Get options from server
      const options = await getAuthenticationOptions();

      // 2. Prompt user for biometric authentication
      const cred = await startAuthentication(options);

      // --- START: MODIFIED LOGIC ---
      // 3. Verify the credential with the server
      const data = await verifyAuthentication(cred);

      // 4. On successful verification, the backend now sends a token.
      // We must handle it here to complete the login.
      if (data.token && data.admin) {
        // Manually log the user in by saving the token and admin data
        localStorage.setItem("admin", JSON.stringify(data.admin));
        localStorage.setItem("token", data.token);

        // Navigate to the dashboard
        navigate("/dashboard");
      } else {
        // This 'else' block handles cases where verification fails on the backend
        setError(data.message || "Biometric login failed. Please try again.");
      }
      // --- END: MODIFIED LOGIC ---
    } catch (err) {
      const errorMessage =
        err.response?.data?.message ||
        "Biometric login failed or was cancelled. Please try again.";
      console.error("Biometric Login Error:", err);
      setError(errorMessage);
    } finally {
      setBiometricLoading(false);
    }
  };

  return (
    <Container component="main" maxWidth="xs">
      <Paper
        elevation={3}
        sx={{
          marginTop: 8,
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          padding: 4,
          borderRadius: 2,
        }}
      >
        <Typography component="h1" variant="h5" sx={{ mb: 3 }}>
          Admin Sign In
        </Typography>
        {error && (
          <Alert severity="error" sx={{ width: "100%", mb: 2 }}>
            {error}
          </Alert>
        )}
        <Box component="form" onSubmit={handleLogin} noValidate sx={{ mt: 1 }}>
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
            disabled={loading}
            sx={{ mt: 3, mb: 1, py: 1.5 }}
          >
            {loading ? <CircularProgress size={24} /> : "Sign In"}
          </Button>
          <Button
            type="button"
            fullWidth
            variant="outlined"
            onClick={handleBiometricLogin}
            disabled={biometricLoading}
            startIcon={<FingerprintIcon />}
            sx={{ mb: 2, py: 1.5 }}
          >
            {biometricLoading ? (
              <CircularProgress size={24} />
            ) : (
              "Sign In with Biometrics"
            )}
          </Button>
          <Link to="/signup" variant="body2">
            {"Don't have an account? Sign Up"}
          </Link>
        </Box>
      </Paper>
    </Container>
  );
};

export default LoginPage;
