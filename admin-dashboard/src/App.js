// src/App.js
import React from "react";
import {
  BrowserRouter as Router,
  Routes,
  Route,
  Navigate,
} from "react-router-dom";
import LoginPage from "./pages/LoginPage";
import SignupPage from "./pages/SignupPage";
import DashboardLayout from "./layout/DashboardLayout";
import DashboardPage from "./pages/DashboardPage";
import ManageUsersPage from "./pages/ManageUsersPage";
import ProfilePage from "./pages/ProfilePage";
import ActivityLogPage from "./pages/ActivityLogPage";
import ModerationPage from "./pages/ModerationPage";
import ConversationViewerPage from "./pages/ConversationViewerPage";
import { getCurrentAdmin } from "./services/authService";

import { LocalizationProvider } from "@mui/x-date-pickers/LocalizationProvider";
import { AdapterDateFns } from "@mui/x-date-pickers/AdapterDateFns";

// This component protects routes that require authentication
const ProtectedRoute = ({ children }) => {
  const admin = getCurrentAdmin();
  return admin ? children : <Navigate to="/login" />;
};

function App() {
  return (
    <LocalizationProvider dateAdapter={AdapterDateFns}>
      <Router>
        <Routes>
          <Route path="/login" element={<LoginPage />} />
          <Route path="/signup" element={<SignupPage />} />

          {/* All dashboard routes are children of the DashboardLayout */}
          <Route
            path="/"
            element={
              <ProtectedRoute>
                <DashboardLayout />
              </ProtectedRoute>
            }
          >
            {/* Default route is /dashboard */}
            <Route index element={<Navigate to="/dashboard" replace />} />
            <Route path="dashboard" element={<DashboardPage />} />
            <Route path="profile" element={<ProfilePage />} />
            <Route path="manage-users" element={<ManageUsersPage />} />
            <Route path="moderation" element={<ModerationPage />} />
            <Route
              path="moderation/:conversationId"
              element={<ConversationViewerPage />}
            />
            <Route path="activity-log" element={<ActivityLogPage />} />
          </Route>
        </Routes>
      </Router>
    </LocalizationProvider>
  );
}

export default App;
