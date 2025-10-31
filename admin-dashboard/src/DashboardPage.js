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
  useTheme,
  alpha,
  Chip,
  LinearProgress,
} from "@mui/material";
import { DatePicker } from "@mui/x-date-pickers/DatePicker";
import { subDays, startOfYear } from "date-fns";
import PeopleAltIcon from "@mui/icons-material/PeopleAlt";
import ForumIcon from "@mui/icons-material/Forum";
import MessageIcon from "@mui/icons-material/Message";
import OnlinePredictionIcon from "@mui/icons-material/OnlinePrediction";
import TrendingUpIcon from "@mui/icons-material/TrendingUp";
import TrendingDownIcon from "@mui/icons-material/TrendingDown";
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
  LineChart,
  Line,
  Area,
  AreaChart,
} from "recharts";
import { API_BASE_URL } from "../config/apiConfig";

const StatCard = ({ title, value, icon, color, trend, trendValue }) => {
  const theme = useTheme();

  return (
    <Card
      sx={{
        height: "100%",
        // Use a semi-translucent background for a "glassmorphism" effect
        background: `linear-gradient(135deg, ${alpha(
          theme.palette.background.paper,
          0.8
        )} 0%, ${alpha(theme.palette.background.paper, 0.6)} 100%)`,
        border: `1px solid ${alpha(theme.palette[color].main, 0.2)}`,
        borderRadius: 3,
        transition: "all 0.3s ease",
        backdropFilter: "blur(5px)",
        "&:hover": {
          transform: "translateY(-4px)",
          boxShadow: `0 8px 25px ${alpha(theme.palette[color].main, 0.25)}`,
        },
      }}
    >
      <CardContent sx={{ p: 3 }}>
        <Box
          sx={{
            display: "flex",
            alignItems: "flex-start",
            justifyContent: "space-between",
          }}
        >
          <Box sx={{ flexGrow: 1 }}>
            <Typography
              variant="body2"
              sx={{
                color: "text.secondary",
                fontWeight: 500,
                mb: 1,
                textTransform: "uppercase",
                letterSpacing: "0.5px",
                fontSize: "0.75rem",
              }}
            >
              {title}
            </Typography>
            <Typography
              variant="h3"
              sx={{
                fontWeight: 700,
                color: "text.primary",
                mb: 1,
                fontSize: "2.2rem",
              }}
            >
              {typeof value === "number" ? value.toLocaleString() : value}
            </Typography>
            {trend && trendValue && (
              <Box sx={{ display: "flex", alignItems: "center", gap: 1 }}>
                <Chip
                  icon={
                    trend === "up" ? <TrendingUpIcon /> : <TrendingDownIcon />
                  }
                  label={`${trendValue}%`}
                  size="small"
                  sx={{
                    bgcolor:
                      trend === "up"
                        ? alpha(theme.palette.success.main, 0.1)
                        : alpha(theme.palette.error.main, 0.1),
                    color:
                      trend === "up"
                        ? theme.palette.success.main
                        : theme.palette.error.main,
                    fontWeight: 600,
                    height: 24,
                  }}
                />
                <Typography variant="caption" sx={{ color: "text.secondary" }}>
                  vs last period
                </Typography>
              </Box>
            )}
          </Box>
          <Box
            sx={{
              p: 2,
              bgcolor: theme.palette[color].main,
              color: "white",
              borderRadius: 2,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              minWidth: 56,
              minHeight: 56,
              boxShadow: `0 4px 12px ${alpha(theme.palette[color].main, 0.3)}`,
            }}
          >
            {icon}
          </Box>
        </Box>
      </CardContent>
    </Card>
  );
};

const DashboardPage = () => {
  const theme = useTheme();
  const [stats, setStats] = useState(null);
  const [chartData, setChartData] = useState([]);
  const [loading, setLoading] = useState(true);
  const [onlineUserCount, setOnlineUserCount] = useState(0);
  const [chartPeriod, setChartPeriod] = useState("week");
  const [adminName, setAdminName] = useState("");

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
    const admin = getCurrentAdmin();
    if (admin && admin.fullName) {
      setAdminName(admin.fullName.split(" ")[0]);
    } else {
      setAdminName("Admin");
    }
    fetchData();
  }, [fetchData]);

  useEffect(() => {
    const admin = getCurrentAdmin();
    if (!admin) return;

    const socket = io(API_BASE_URL, {
      query: { userId: admin.id, isAdmin: true },
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
          Loading dashboard data...
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
            animation: "fadeIn 1s ease-in-out",
            "@keyframes fadeIn": {
              "0%": { opacity: 0, transform: "translateY(20px)" },
              "100%": { opacity: 1, transform: "translateY(0)" },
            },
          }}
        >
          Welcome, {adminName || "Admin"}! 👋
        </Typography>
        <Typography variant="body1" color="text.secondary">
          Monitor your platform's performance and user engagement
        </Typography>
      </Box>

      {/* Date Controls */}
      <Paper
        elevation={0}
        sx={{
          p: 3,
          mb: 4,
          borderRadius: 3,
          border: "1px solid",
          borderColor: "divider",
          background:
            "linear-gradient(135deg, rgba(255, 255, 255, 0.8) 0%, rgba(255, 255, 255, 0.4) 100%)",
          backdropFilter: "blur(10px)",
        }}
      >
        <Box
          sx={{
            display: "flex",
            gap: 2,
            flexWrap: "wrap",
            alignItems: "center",
            justifyContent: "space-between",
          }}
        >
          <Box
            sx={{
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
              slotProps={{
                textField: {
                  size: "small",
                  sx: { minWidth: 150 },
                },
              }}
            />
            <DatePicker
              label="End Date"
              value={dateRange.endDate}
              onChange={(newValue) =>
                setDateRange((prev) => ({ ...prev, endDate: newValue }))
              }
              slotProps={{
                textField: {
                  size: "small",
                  sx: { minWidth: 150 },
                },
              }}
            />
          </Box>
          <ButtonGroup variant="outlined" size="small">
            <Button
              onClick={() => setDatePreset("week")}
              variant={chartPeriod === "week" ? "contained" : "outlined"}
            >
              Last 7 Days
            </Button>
            <Button
              onClick={() => setDatePreset("month")}
              variant={chartPeriod === "month" ? "contained" : "outlined"}
            >
              Last 30 Days
            </Button>
            <Button
              onClick={() => setDatePreset("year")}
              variant={chartPeriod === "year" ? "contained" : "outlined"}
            >
              This Year
            </Button>
          </ButtonGroup>
        </Box>
      </Paper>

      {/* Stats Cards */}
      <Grid container spacing={3} sx={{ mb: 4 }}>
        <Grid item xs={12} sm={6} lg={3}>
          <StatCard
            title="Total Users"
            value={stats?.totalUsers ?? 0}
            icon={<PeopleAltIcon sx={{ fontSize: 28 }} />}
            color="primary"
            trend="up"
            trendValue={12}
          />
        </Grid>
        <Grid item xs={12} sm={6} lg={3}>
          <StatCard
            title="Total Conversations"
            value={stats?.totalConversations ?? 0}
            icon={<ForumIcon sx={{ fontSize: 28 }} />}
            color="success"
            trend="up"
            trendValue={8}
          />
        </Grid>
        <Grid item xs={12} sm={6} lg={3}>
          <StatCard
            title="Total Messages"
            value={stats?.totalMessages ?? 0}
            icon={<MessageIcon sx={{ fontSize: 28 }} />}
            color="warning"
            trend="down"
            trendValue={3}
          />
        </Grid>
        <Grid item xs={12} sm={6} lg={3}>
          <StatCard
            title="Online Users"
            value={onlineUserCount}
            icon={<OnlinePredictionIcon sx={{ fontSize: 28 }} />}
            color="error"
            trend="up"
            trendValue={25}
          />
        </Grid>
      </Grid>

      {/* Charts and Analytics */}
      <Grid container spacing={3}>
        {/* New Users Chart */}
        <Grid item xs={12} xl={8}>
          <Card
            sx={{
              borderRadius: 3,
              border: "1px solid",
              borderColor: "divider",
              height: { xs: "auto", xl: 450 },
              transition: "all 0.3s ease",
              "&:hover": {
                transform: "translateY(-4px)",
                boxShadow: `0 8px 25px ${alpha(
                  theme.palette.primary.main,
                  0.1
                )}`,
              },
            }}
          >
            <CardContent sx={{ p: 3 }}>
              <Box
                sx={{
                  display: "flex",
                  justifyContent: "space-between",
                  alignItems: "center",
                  mb: 3,
                  flexWrap: "wrap",
                  gap: 2,
                }}
              >
                <Box>
                  <Typography variant="h6" sx={{ fontWeight: 600, mb: 1 }}>
                    New Users Analytics
                  </Typography>
                  <Typography variant="body2" color="text.secondary">
                    Track user registration trends over time
                  </Typography>
                </Box>
                <ButtonGroup size="small">
                  <Button
                    onClick={() => setChartPeriod("week")}
                    variant={chartPeriod === "week" ? "contained" : "outlined"}
                  >
                    7 Days
                  </Button>
                  <Button
                    onClick={() => setChartPeriod("month")}
                    variant={chartPeriod === "month" ? "contained" : "outlined"}
                  >
                    30 Days
                  </Button>
                  <Button
                    onClick={() => setChartPeriod("year")}
                    variant={chartPeriod === "year" ? "contained" : "outlined"}
                  >
                    This Year
                  </Button>
                </ButtonGroup>
              </Box>
              <ResponsiveContainer width="100%" height={300}>
                <AreaChart data={chartData}>
                  <defs>
                    <linearGradient id="colorUsers" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="5%" stopColor="#00d4aa" stopOpacity={0.3} />
                      <stop offset="95%" stopColor="#00d4aa" stopOpacity={0} />
                    </linearGradient>
                  </defs>
                  <CartesianGrid
                    strokeDasharray="3 3"
                    stroke={alpha(theme.palette.divider, 0.5)}
                  />
                  <XAxis
                    dataKey="date"
                    stroke={theme.palette.text.secondary}
                    fontSize={12}
                  />
                  <YAxis
                    allowDecimals={false}
                    stroke={theme.palette.text.secondary}
                    fontSize={12}
                  />
                  <Tooltip
                    contentStyle={{
                      backgroundColor: theme.palette.background.paper,
                      border: `1px solid ${theme.palette.divider}`,
                      borderRadius: 8,
                      boxShadow: theme.shadows[8],
                    }}
                  />
                  <Area
                    type="monotone"
                    dataKey="count"
                    name="New Users"
                    stroke="#00d4aa"
                    strokeWidth={3}
                    fill="url(#colorUsers)"
                  />
                </AreaChart>
              </ResponsiveContainer>
            </CardContent>
          </Card>
        </Grid>

        {/* Most Active Users */}
        <Grid item xs={12} xl={4}>
          <Box
            sx={{
              height: { xs: "auto", xl: 450 },
              transition: "all 0.3s ease",
              "&:hover": {
                transform: "translateY(-4px)",
                boxShadow: `0 8px 25px ${alpha(
                  theme.palette.primary.main,
                  0.1
                )}`,
              },
            }}
          >
            <MostActiveUsers />
          </Box>
        </Grid>

        {/* Recent Activity */}
        <Grid item xs={12}>
          <Box
            sx={{
              transition: "all 0.3s ease",
              "&:hover": {
                transform: "translateY(-4px)",
                boxShadow: `0 8px 25px ${alpha(
                  theme.palette.primary.main,
                  0.1
                )}`,
              },
            }}
          >
            <RecentActivity />
          </Box>
        </Grid>
      </Grid>
    </Box>
  );
};

export default DashboardPage;