// src/pages/LoginPage.js
import React, { useState } from "react";
import { useNavigate, Link } from "react-router-dom";
import { login, biometricLogin } from "../services/authService"; // ✅ Import biometricLogin
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
    if (!email) {
      setSnackbar({
        open: true,
        message: "Please enter your Email Address to log in with biometrics.",
        severity: "warning",
      });
      return;
    }

    try {
      // Step 1: Perform WebAuthn verification
      const { verified } = await loginWithBiometrics(email);

      if (verified) {
        // Step 2: If WebAuthn verification successful, create session
        await biometricLogin(email); // ✅ Use the new biometricLogin function

        setSnackbar({
          open: true,
          message: "Biometric login successful!",
          severity: "success",
        });

        navigate("/dashboard");
      } else {
        setSnackbar({
          open: true,
          message: "Biometric login failed. Please try again.",
          severity: "warning",
        });
      }
    } catch (error) {
      console.error("Biometric login error:", error);
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
