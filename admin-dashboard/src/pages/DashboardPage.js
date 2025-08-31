// src/pages/DashboardPage.js
import React, { useState, useEffect, useCallback } from "react";
import {
  getDashboardStats,
  getNewUsersChartData,
} from "../services/analyticsService";
import {
  Box,
  Typography,
  Grid,
  Card,
  CardContent,
  CircularProgress,
  Paper,
  Button,
  ButtonGroup,
} from "@mui/material";
import { DatePicker } from "@mui/x-date-pickers/DatePicker";
import { subDays, startOfYear } from "date-fns";
import PeopleAltIcon from "@mui/icons-material/PeopleAlt";
import ForumIcon from "@mui/icons-material/Forum";
import MessageIcon from "@mui/icons-material/Message";
import OnlinePredictionIcon from "@mui/icons-material/OnlinePrediction";
import { io } from "socket.io-client";
import { getCurrentAdmin } from "../services/authService";
import RecentActivity from "../components/RecentActivity";
import MostActiveUsers from "../components/MostActiveUsers";
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
} from "recharts";
import { API_BASE_URL } from "../config/apiConfig";

const StatCard = ({ title, value, icon, color }) => (
  <Card sx={{ display: "flex", alignItems: "center", p: 2 }}>
    <Box sx={{ p: 2, bgcolor: color, color: "white", borderRadius: "50%" }}>
      {icon}
    </Box>
    <Box sx={{ flexGrow: 1, ml: 2 }}>
      <Typography color="text.secondary">{title}</Typography>
      <Typography variant="h4">{value}</Typography>
    </Box>
  </Card>
);

const DashboardPage = () => {
  const [stats, setStats] = useState(null);
  const [chartData, setChartData] = useState([]);
  const [loading, setLoading] = useState(true);
  const [onlineUserCount, setOnlineUserCount] = useState(0);
  const [chartPeriod, setChartPeriod] = useState("week"); // State for the chart's period

  const [dateRange, setDateRange] = useState({
    startDate: subDays(new Date(), 6),
    endDate: new Date(),
  });

  const fetchData = useCallback(async () => {
    setLoading(true);
    try {
      const [statsData, newUsersData] = await Promise.all([
        getDashboardStats(dateRange),
        getNewUsersChartData(chartPeriod),
      ]);
      setStats(statsData);
      setChartData(newUsersData);
      if (statsData.onlineUserCount !== undefined) {
        setOnlineUserCount(statsData.onlineUserCount);
      }
    } catch (error) {
      console.error("Failed to fetch dashboard data", error);
    } finally {
      setLoading(false);
    }
  }, [dateRange, chartPeriod]);

  useEffect(() => {
    fetchData();
  }, [fetchData]);

  useEffect(() => {
    const admin = getCurrentAdmin();
    if (!admin) return;

    // Use the API_URL from your config for the socket connection
    const socket = io(API_BASE_URL, {
      query: { userId: `admin_${admin.id}` }, // Safely access admin ID
    });

    socket.on("activeUsers", (activeUserIds) => {
      const chatUsersOnline = activeUserIds.filter(
        (id) => !id.startsWith("admin_")
      );
      setOnlineUserCount(chatUsersOnline.length);
    });

    return () => {
      socket.disconnect();
    };
  }, []);

  const setDatePreset = (period) => {
    const today = new Date();
    if (period === "week") {
      setDateRange({ startDate: subDays(today, 6), endDate: today });
    } else if (period === "month") {
      setDateRange({ startDate: subDays(today, 29), endDate: today });
    } else if (period === "year") {
      setDateRange({ startDate: startOfYear(today), endDate: today });
    }
  };

  return (
    <Box>
      <Typography variant="h4" gutterBottom>
        Dashboard Overview
      </Typography>

      {/* Date controls for Stat Cards */}
      <Paper
        sx={{
          p: 2,
          mb: 3,
          display: "flex",
          gap: 2,
          flexWrap: "wrap",
          alignItems: "center",
        }}
      >
        <DatePicker
          label="Start Date"
          value={dateRange.startDate}
          onChange={(newValue) =>
            setDateRange((prev) => ({ ...prev, startDate: newValue }))
          }
        />
        <DatePicker
          label="End Date"
          value={dateRange.endDate}
          onChange={(newValue) =>
            setDateRange((prev) => ({ ...prev, endDate: newValue }))
          }
        />
        <ButtonGroup variant="outlined">
          <Button onClick={() => setDatePreset("week")}>Last 7 Days</Button>
          <Button onClick={() => setDatePreset("month")}>Last 30 Days</Button>
          <Button onClick={() => setDatePreset("year")}>This Year</Button>
        </ButtonGroup>
      </Paper>

      {loading ? (
        <Box sx={{ display: "flex", justifyContent: "center", mt: 4 }}>
          <CircularProgress />
        </Box>
      ) : (
        <>
          <Grid container spacing={3} mb={3}>
            {/* Stat Cards */}
            <Grid item xs={12} sm={6} md={3}>
              <StatCard
                title="Total Users"
                value={stats?.totalUsers ?? "..."}
                icon={<PeopleAltIcon />}
                color="primary.main"
              />
            </Grid>
            <Grid item xs={12} sm={6} md={3}>
              <StatCard
                title="Total Conversations"
                value={stats?.totalConversations ?? "..."}
                icon={<ForumIcon />}
                color="success.main"
              />
            </Grid>
            <Grid item xs={12} sm={6} md={3}>
              <StatCard
                title="Total Messages"
                value={stats?.totalMessages ?? "..."}
                icon={<MessageIcon />}
                color="warning.main"
              />
            </Grid>
            <Grid item xs={12} sm={6} md={3}>
              <StatCard
                title="Online Users"
                value={onlineUserCount}
                icon={<OnlinePredictionIcon />}
                color="error.main"
              />
            </Grid>
          </Grid>

          <Grid container spacing={3}>
            <Grid item xs={12} lg={8}>
              <Card>
                <CardContent>
                  <Box
                    sx={{
                      display: "flex",
                      justifyContent: "space-between",
                      alignItems: "center",
                      mb: 2,
                    }}
                  >
                    <Typography variant="h6">New Users</Typography>
                    {/* ButtonGroup for Chart Period */}
                    <ButtonGroup size="small">
                      <Button
                        onClick={() => setChartPeriod("week")}
                        variant={
                          chartPeriod === "week" ? "contained" : "outlined"
                        }
                      >
                        7 Days
                      </Button>
                      <Button
                        onClick={() => setChartPeriod("month")}
                        variant={
                          chartPeriod === "month" ? "contained" : "outlined"
                        }
                      >
                        30 Days
                      </Button>
                      <Button
                        onClick={() => setChartPeriod("year")}
                        variant={
                          chartPeriod === "year" ? "contained" : "outlined"
                        }
                      >
                        This Year
                      </Button>
                    </ButtonGroup>
                  </Box>
                  <ResponsiveContainer width="100%" height={300}>
                    <BarChart data={chartData}>
                      <CartesianGrid strokeDasharray="3 3" />
                      <XAxis dataKey="date" />
                      <YAxis allowDecimals={false} />
                      <Tooltip />
                      <Bar dataKey="count" name="New Users" fill="#8884d8" />
                    </BarChart>
                  </ResponsiveContainer>
                </CardContent>
              </Card>
            </Grid>

            <Grid item xs={12} lg={4}>
              <Box sx={{ display: "flex", flexDirection: "column", gap: 3 }}>
                <MostActiveUsers />
                <RecentActivity />
              </Box>
            </Grid>
          </Grid>
        </>
      )}
    </Box>
  );
};

export default DashboardPage;
