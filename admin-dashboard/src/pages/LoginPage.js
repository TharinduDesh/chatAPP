// src/pages/LoginPage.js
import React, { useState } from "react";
import { useNavigate, Link } from "react-router-dom";
import { login } from "../services/authService";
import {
  TextField,
  Button,
  Container,
  Typography,
  Box,
  Divider,
} from "@mui/material";
import { loginWithBiometrics } from "../services/webauthnService";
import Fingerprint from "@mui/icons-material/Fingerprint";

const LoginPage = () => {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const navigate = useNavigate();

  const handleLogin = async (e) => {
    e.preventDefault();
    try {
      await login(email, password);
      navigate("/dashboard"); // Redirect to dashboard on successful login
    } catch (error) {
      console.error("Login failed", error);
      // You can add error handling here (e.g., show a snackbar)
    }
  };

  const handleBiometricLogin = async () => {
    if (!email) {
      alert("Please enter your Email Address to log in with biometrics.");
      return;
    }
    try {
      // We now pass the email as the username
      const { verified } = await loginWithBiometrics(email);
      if (verified) {
        // After successful verification, we need a way to get the auth token.
        // For simplicity, we'll call the regular login endpoint again,
        // but in a real app, you might have a dedicated endpoint for this.
        await login(email, null, true); // Pass a flag indicating biometric login
        alert("Biometric login successful!");
        navigate("/dashboard");
      } else {
        alert("Biometric login failed. Please try again.");
      }
    } catch (error) {
      alert(
        error.response?.data?.message ||
          "An error occurred during biometric login."
      );
    }
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
          {/* The email field above will be used for biometric login */}
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
    </Container>
  );
};

export default LoginPage;
