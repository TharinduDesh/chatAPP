// src/pages/ManageUsersPage.js
import React, { useState, useEffect, useMemo, useCallback } from "react";
import {
  getAllUsers,
  addUser,
  deleteUser,
  updateUser,
  permanentDeleteUser,
  banUser,
  unbanUser,
  getBannedUsers,
  getDeletedUsers,
  revertUserDeletion,
  getUsersForExport,
} from "../services/userService";
import {
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Paper,
  Typography,
  Button,
  IconButton,
  Box,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  TextField,
  Tooltip,
  DialogContentText,
  Chip,
  Select,
  MenuItem,
  FormControl,
  InputLabel,
  Tabs,
  Tab,
  Pagination,
  Card,
  CardContent,
  alpha,
  useTheme,
  Avatar,
  InputAdornment,
} from "@mui/material";
import DeleteIcon from "@mui/icons-material/Delete";
import AddIcon from "@mui/icons-material/Add";
import EditIcon from "@mui/icons-material/Edit";
import BlockIcon from "@mui/icons-material/Block";
import RestoreFromTrashIcon from "@mui/icons-material/RestoreFromTrash";
import CheckCircleOutlineIcon from "@mui/icons-material/CheckCircleOutline";
import SearchIcon from "@mui/icons-material/Search";
import { logout } from "../services/authService";
import { useNavigate } from "react-router-dom";
import DownloadIcon from "@mui/icons-material/Download";
import Papa from "papaparse";

const UserStatus = ({ user }) => {
  const theme = useTheme();
  const getStatusChipStyle = (isBanned, isDeleted) => {
    if (isBanned)
      return {
        bgcolor: alpha(theme.palette.error.main, 0.1),
        color: theme.palette.error.main,
        fontWeight: 600,
      };
    if (isDeleted)
      return {
        bgcolor: alpha(theme.palette.grey[500], 0.1),
        color: theme.palette.grey[600],
        fontWeight: 600,
      };
    return {
      bgcolor: alpha(theme.palette.success.main, 0.1),
      color: theme.palette.success.main,
      fontWeight: 600,
    };
  };

  return (
    <Chip
      label={user.isBanned ? "Banned" : user.deletedAt ? "Deactivated" : "Active"}
      size="small"
      sx={getStatusChipStyle(user.isBanned, user.deletedAt)}
    />
  );
};

const UserTable = ({
  users,
  title,
  columns,
  onEdit,
  onBan,
  onUnban,
  onDelete,
}) => {
  const theme = useTheme();
  const [filter, setFilter] = useState("");
  const filteredUsers = useMemo(
    () =>
      users.filter(
        (user) =>
          user.fullName.toLowerCase().includes(filter.toLowerCase()) ||
          user.email.toLowerCase().includes(filter.toLowerCase())
      ),
    [users, filter]
  );

  return (
    <Box>
      <TextField
        label={`Search ${title}`}
        variant="outlined"
        fullWidth
        margin="normal"
        value={filter}
        onChange={(e) => setFilter(e.target.value)}
        sx={{ mb: 3 }}
        InputProps={{
          startAdornment: (
            <InputAdornment position="start">
              <SearchIcon color="action" />
            </InputAdornment>
          ),
        }}
      />
      <TableContainer
        component={Paper}
        sx={{
          borderRadius: 3,
          border: "1px solid",
          borderColor: "divider",
          overflow: "hidden",
        }}
      >
        <Table>
          <TableHead>
            <TableRow sx={{ bgcolor: "grey.50" }}>
              {columns.map((col) => (
                <TableCell
                  key={col.id}
                  align={col.align || "left"}
                  sx={{
                    fontWeight: 600,
                    color: "text.secondary",
                    py: 2,
                  }}
                >
                  {col.label}
                </TableCell>
              ))}
            </TableRow>
          </TableHead>
          <TableBody>
            {filteredUsers.map((user) => (
              <TableRow
                key={user._id}
                sx={{
                  "&:hover": {
                    bgcolor: alpha(theme.palette.primary.main, 0.05), // Lighter hover background
                    transform: "scale(1.005)", // Subtle scaling effect
                    boxShadow: `0 8px 16px ${alpha(theme.palette.primary.main, 0.1)}`, // More pronounced shadow
                  },
                  transition: "all 0.3s ease-in-out",
                  backgroundColor: user.isBanned
                    ? alpha(theme.palette.error.main, 0.05)
                    : "transparent",
                }}
              >
                {columns.map((col) => (
                  <TableCell
                    key={col.id}
                    align={col.align || "left"}
                    sx={{ py: 2 }}
                  >
                    {col.render(user, { onEdit, onBan, onUnban, onDelete })}
                  </TableCell>
                ))}
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </TableContainer>
    </Box>
  );
};

const ManageUsersPage = () => {
  const theme = useTheme();
  const [activeTab, setActiveTab] = useState(0);
  const [allUsers, setAllUsers] = useState({
    list: [],
    page: 1,
    totalPages: 0,
  });
  const [bannedUsers, setBannedUsers] = useState({
    list: [],
    page: 1,
    totalPages: 0,
  });
  const [deletedUsers, setDeletedUsers] = useState({
    list: [],
    page: 1,
    totalPages: 0,
  });
  const [isUserFormOpen, setIsUserFormOpen] = useState(false);
  const [isEditMode, setIsEditMode] = useState(false);
  const [currentUserData, setCurrentUserData] = useState({
    id: null,
    fullName: "",
    email: "",
    password: "",
  });
  const [isDeleteDialogOpen, setIsDeleteDialogOpen] = useState(false);
  const [userToDelete, setUserToDelete] = useState(null);
  const [isBanDialogOpen, setIsBanDialogOpen] = useState(false);
  const [userToBan, setUserToBan] = useState(null);
  const [banData, setBanData] = useState({ reason: "", durationInDays: 7 });
  const navigate = useNavigate();

  const fetchAllData = useCallback(async () => {
    try {
      const [all, banned, deleted] = await Promise.all([
        getAllUsers(allUsers.page),
        getBannedUsers(),
        getDeletedUsers(),
      ]);
      setAllUsers({
        list: all.users,
        page: all.currentPage,
        totalPages: all.totalPages,
      });
      setBannedUsers({ list: banned, page: 1, totalPages: 1 });
      setDeletedUsers({ list: deleted, page: 1, totalPages: 1 });
    } catch (error) {
      console.error("Failed to fetch user data", error);
      if (error.response && error.response.status === 401) {
        logout();
        navigate("/login");
      }
    }
  }, [allUsers.page, navigate]);

  useEffect(() => {
    fetchAllData();
  }, [fetchAllData]);

  const handlePageChange = (event, value) => {
    setAllUsers((prev) => ({ ...prev, page: value }));
  };

  const handleOpenAddDialog = () => {
    setIsEditMode(false);
    setCurrentUserData({ id: null, fullName: "", email: "", password: "" });
    setIsUserFormOpen(true);
  };

  const handleOpenEditDialog = (user) => {
    setIsEditMode(true);
    setCurrentUserData({
      id: user._id,
      fullName: user.fullName,
      email: user.email,
    });
    setIsUserFormOpen(true);
  };

  const handleCloseUserForm = () => setIsUserFormOpen(false);

  const handleInputChange = (e) => {
    const { name, value } = e.target;
    setCurrentUserData((prev) => ({ ...prev, [name]: value }));
  };

  const handleUserFormSubmit = async () => {
    if (isEditMode) {
      try {
        await updateUser(currentUserData.id, {
          fullName: currentUserData.fullName,
          email: currentUserData.email,
        });
        fetchAllData();
      } catch (error) {
        console.error("Failed to update user", error);
      }
    } else {
      try {
        await addUser(currentUserData);
        fetchAllData();
      } catch (error) {
        console.error("Failed to add user", error);
      }
    }
    handleCloseUserForm();
  };

  const handleOpenDeleteDialog = (user) => {
    setUserToDelete(user);
    setIsDeleteDialogOpen(true);
  };

  const handleCloseDeleteDialog = () => {
    setIsDeleteDialogOpen(false);
    setUserToDelete(null);
  };

  const handleSoftDelete = async () => {
    try {
      await deleteUser(userToDelete._id);
      fetchAllData();
    } catch (error) {
      console.error("Failed to deactivate user", error);
    }
    handleCloseDeleteDialog();
  };

  const handlePermanentDelete = async () => {
    try {
      await permanentDeleteUser(userToDelete._id);
      fetchAllData();
    } catch (error) {
      console.error("Failed to permanently delete user", error);
    }
    handleCloseDeleteDialog();
  };

  const handleOpenBanDialog = (user) => {
    setUserToBan(user);
    setIsBanDialogOpen(true);
  };

  const handleCloseBanDialog = () => {
    setIsBanDialogOpen(false);
    setUserToBan(null);
    setBanData({ reason: "", durationInDays: 7 });
  };

  const handleBanInputChange = (e) => {
    const { name, value } = e.target;
    setBanData((prev) => ({ ...prev, [name]: value }));
  };

  const handleBanSubmit = async () => {
    try {
      await banUser(userToBan._id, banData);
      fetchAllData();
    } catch (error) {
      console.error("Failed to ban user", error);
    }
    handleCloseBanDialog();
  };

  const handleUnbanUser = async (user) => {
    if (window.confirm(`Are you sure you want to unban ${user.fullName}?`)) {
      try {
        await unbanUser(user._id);
        fetchAllData();
      } catch (error) {
        console.error("Failed to unban user", error);
      }
    }
  };

  const handleTabChange = (event, newValue) => {
    setActiveTab(newValue);
  };

  const handleRevertUser = async (user) => {
    if (
      window.confirm(
        `Are you sure you want to restore the account for ${user.fullName}?`
      )
    ) {
      try {
        await revertUserDeletion(user._id);
        fetchAllData();
      } catch (error) {
        console.error("Failed to restore user", error);
      }
    }
  };

  const handleExportCSV = async () => {
    try {
      const usersToExport = await getUsersForExport();
      const formattedData = usersToExport.map((user) => ({
        "User ID": user._id,
        "Full Name": user.fullName,
        Email: user.email,
        Status: user.isBanned
          ? "Banned"
          : user.deletedAt
          ? "Deactivated"
          : "Active",
        "Created At": new Date(user.createdAt).toISOString(),
        "Deactivated At": user.deletedAt
          ? new Date(user.deletedAt).toISOString()
          : "N/A",
        "Deactivated By": user.deletedBy?.fullName || "N/A",
        "Is Banned": user.isBanned,
        "Ban Reason": user.banDetails?.reason || "N/A",
        "Banned At": user.banDetails?.bannedAt
          ? new Date(user.banDetails.bannedAt).toISOString()
          : "N/A",
        "Ban Expires At": user.banDetails?.expiresAt
          ? new Date(user.banDetails.expiresAt).toISOString()
          : "N/A",
        "Banned By": user.banDetails?.bannedBy?.fullName || "N/A",
      }));
      const csv = Papa.unparse(formattedData);
      const blob = new Blob([csv], { type: "text/csv;charset=utf-8;" });
      const link = document.createElement("a");
      const url = URL.createObjectURL(blob);
      link.setAttribute("href", url);
      link.setAttribute("download", "user_export.csv");
      link.style.visibility = "hidden";
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
    } catch (error) {
      console.error("Failed to export users:", error);
      alert("Could not export user data.");
    }
  };

  const allUsersColumns = [
    {
      id: "name",
      label: "Full Name",
      render: (user) => (
        <Box sx={{ display: "flex", alignItems: "center", gap: 2 }}>
          <Avatar
            sx={{ width: 32, height: 32, bgcolor: theme.palette.primary.main }}
          >
            {user.fullName.charAt(0)}
          </Avatar>
          {user.fullName}
        </Box>
      ),
    },
    { id: "email", label: "Email", render: (user) => user.email },
    {
      id: "status",
      label: "Status",
      render: (user) => <UserStatus user={user} />,
    },
    {
      id: "createdAt",
      label: "Created At",
      render: (user) => new Date(user.createdAt).toLocaleDateString(),
    },
    {
      id: "actions",
      label: "Actions",
      align: "right",
      render: (user, actions) => (
        <Box sx={{ display: "flex", gap: 1, justifyContent: "flex-end" }}>
          <Tooltip title="Edit User">
            <IconButton
              onClick={() => actions.onEdit(user)}
              disabled={user.isBanned || user.deletedAt}
              size="small"
            >
              <EditIcon fontSize="small" />
            </IconButton>
          </Tooltip>
          {user.isBanned ? (
            <Tooltip title="Unban User">
              <IconButton
                onClick={() => actions.onUnban(user)}
                color="success"
                size="small"
              >
                <CheckCircleOutlineIcon fontSize="small" />
              </IconButton>
            </Tooltip>
          ) : (
            <Tooltip title="Ban User">
              <IconButton
                onClick={() => actions.onBan(user)}
                color="warning"
                disabled={user.deletedAt}
                size="small"
              >
                <BlockIcon fontSize="small" />
              </IconButton>
            </Tooltip>
          )}
          <Tooltip title="Delete Options">
            <IconButton
              onClick={() => actions.onDelete(user)}
              color="error"
              disabled={user.deletedAt}
              size="small"
            >
              <DeleteIcon fontSize="small" />
            </IconButton>
          </Tooltip>
        </Box>
      ),
    },
  ];

  const bannedUsersColumns = [
    { id: "name", label: "Full Name", render: (user) => user.fullName },
    { id: "email", label: "Email", render: (user) => user.email },
    {
      id: "banDate",
      label: "Ban Date",
      render: (user) => new Date(user.banDetails.bannedAt).toLocaleDateString(),
    },
    {
      id: "banPeriod",
      label: "Ban Period",
      render: (user) =>
        user.banDetails.expiresAt
          ? `${Math.ceil(
              (new Date(user.banDetails.expiresAt) - new Date()) /
                (1000 * 60 * 60 * 24)
            )} days left`
          : "Permanent",
    },
    { id: "reason", label: "Reason", render: (user) => user.banDetails.reason },
    {
      id: "bannedBy",
      label: "Banned By",
      render: (user) => user.banDetails.bannedBy?.fullName || "N/A",
    },
    {
      id: "actions",
      label: "Actions",
      align: "right",
      render: (user, actions) => (
        <Button
          variant="contained"
          color="success"
          size="small"
          onClick={() => actions.onUnban(user)}
        >
          Unban
        </Button>
      ),
    },
  ];

  const deletedUsersColumns = [
    { id: "name", label: "Full Name", render: (user) => user.fullName },
    { id: "email", label: "Email", render: (user) => user.email },
    {
      id: "deletedDate",
      label: "Deactivated Date",
      render: (user) => new Date(user.deletedAt).toLocaleDateString(),
    },
    {
      id: "deletedBy",
      label: "Deactivated By",
      render: (user) => user.deletedBy?.fullName || "N/A",
    },
    {
      id: "actions",
      label: "Actions",
      align: "right",
      render: (user) => (
        <Tooltip title="Restore User Account">
          <Button
            variant="contained"
            color="success"
            size="small"
            startIcon={<RestoreFromTrashIcon />}
            onClick={() => handleRevertUser(user)}
          >
            Revert
          </Button>
        </Tooltip>
      ),
    },
  ];

  return (
    <Box>
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
            // Added animation for more dynamic title
            animation: "fadeIn 1s ease-in-out",
            "@keyframes fadeIn": {
              "0%": { opacity: 0, transform: "translateY(20px)" },
              "100%": { opacity: 1, transform: "translateY(0)" },
            },
          }}
        >
          User Management
        </Typography>
        <Typography variant="body1" color="text.secondary">
          Manage all user accounts, permissions, and access levels
        </Typography>
      </Box>

      <Card
        sx={{
          mb: 3,
          borderRadius: 3,
          border: "1px solid",
          borderColor: "divider",
          boxShadow: theme.shadows[4],
          transition: "box-shadow 0.3s ease-in-out", // Added transition for smooth shadow change
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
            <Tabs
              value={activeTab}
              onChange={handleTabChange}
              sx={{ minHeight: "auto" }}
            >
              <Tab
                label={`All Users (${allUsers.list.length})`}
                sx={{ py: 1, minHeight: "auto" }}
              />
              <Tab
                label={`Banned (${bannedUsers.list.length})`}
                sx={{ py: 1, minHeight: "auto" }}
              />
              <Tab
                label={`Deleted (${deletedUsers.list.length})`}
                sx={{ py: 1, minHeight: "auto" }}
              />
            </Tabs>
            <Box sx={{ display: "flex", gap: 2 }}>
              <Button
                variant="outlined"
                startIcon={<DownloadIcon />}
                onClick={handleExportCSV}
                sx={{
                  borderColor: alpha(theme.palette.primary.main, 0.5),
                  color: theme.palette.primary.main,
                  "&:hover": {
                    borderColor: theme.palette.primary.main,
                    bgcolor: alpha(theme.palette.primary.main, 0.04),
                  },
                }}
              >
                Export CSV
              </Button>
              <Button
                variant="contained"
                startIcon={<AddIcon />}
                onClick={handleOpenAddDialog}
                sx={{
                  background:
                    "linear-gradient(135deg, #00d4aa 0%, #4169e1 100%)",
                  color: "white",
                  fontWeight: 600,
                  boxShadow: `0 4px 15px ${alpha(
                    theme.palette.primary.main,
                    0.3
                  )}`,
                  "&:hover": {
                    background:
                      "linear-gradient(135deg, #00c196 0%, #365ec7 100%)",
                    boxShadow: `0 6px 20px ${alpha(
                      theme.palette.primary.main,
                      0.4
                    )}`,
                  },
                }}
              >
                Add User
              </Button>
            </Box>
          </Box>

          <Box sx={{ pt: 2 }}>
            {activeTab === 0 && (
              <>
                <UserTable
                  title="All Users"
                  users={allUsers.list}
                  columns={allUsersColumns}
                  onEdit={handleOpenEditDialog}
                  onBan={handleOpenBanDialog}
                  onUnban={handleUnbanUser}
                  onDelete={handleOpenDeleteDialog}
                />
                <Box
                  sx={{
                    display: "flex",
                    justifyContent: "center",
                    p: 2,
                    mt: 2,
                  }}
                >
                  <Pagination
                    count={allUsers.totalPages}
                    page={allUsers.page}
                    onChange={handlePageChange}
                    color="primary"
                    showFirstButton
                    showLastButton
                    sx={{
                      "& .MuiPaginationItem-root": {
                        borderRadius: 2,
                        fontWeight: 600,
                        transition: "all 0.3s ease",
                        "&:hover": {
                          bgcolor: alpha(theme.palette.primary.main, 0.05),
                        },
                      },
                      "& .Mui-selected": {
                        background:
                          "linear-gradient(135deg, #00d4aa 0%, #4169e1 100%)",
                        color: "white",
                        "&:hover": {
                          background:
                            "linear-gradient(135deg, #00d4aa 0%, #4169e1 100%)",
                          boxShadow: theme.shadows[2],
                        },
                      },
                    }}
                  />
                </Box>
              </>
            )}
            {activeTab === 1 && (
              <UserTable
                title="Banned Users"
                users={bannedUsers.list}
                columns={bannedUsersColumns}
                onUnban={handleUnbanUser}
              />
            )}
            {activeTab === 2 && (
              <UserTable
                title="Deleted Users"
                users={deletedUsers.list}
                columns={deletedUsersColumns}
                onRevert={handleRevertUser}
              />
            )}
          </Box>
        </CardContent>
      </Card>

      {/* Dialogs with updated button styles */}
      <Dialog
        open={isUserFormOpen}
        onClose={handleCloseUserForm}
        PaperProps={{ sx: { borderRadius: 3 } }}
      >
        <DialogTitle sx={{ fontWeight: 600 }}>
          {isEditMode ? "Edit User" : "Add New User"}
        </DialogTitle>
        <DialogContent>
          <TextField
            autoFocus
            margin="dense"
            name="fullName"
            label="Full Name"
            type="text"
            fullWidth
            variant="outlined"
            value={currentUserData.fullName}
            onChange={handleInputChange}
            sx={{ mb: 2 }}
          />
          <TextField
            margin="dense"
            name="email"
            label="Email Address"
            type="email"
            fullWidth
            variant="outlined"
            value={currentUserData.email}
            onChange={handleInputChange}
            sx={{ mb: 2 }}
          />
          {!isEditMode && (
            <TextField
              margin="dense"
              name="password"
              label="Password"
              type="password"
              fullWidth
              variant="outlined"
              value={currentUserData.password}
              onChange={handleInputChange}
            />
          )}
        </DialogContent>
        <DialogActions sx={{ p: 3, pt: 0 }}>
          <Button onClick={handleCloseUserForm}>Cancel</Button>
          <Button
            onClick={handleUserFormSubmit}
            variant="contained"
            sx={{
              background:
                "linear-gradient(135deg, #00d4aa 0%, #4169e1 100%)",
              "&:hover": {
                background:
                  "linear-gradient(135deg, #00c196 0%, #365ec7 100%)",
                boxShadow: theme.shadows[4],
              },
            }}
          >
            {isEditMode ? "Save Changes" : "Add User"}
          </Button>
        </DialogActions>
      </Dialog>

      <Dialog
        open={isDeleteDialogOpen}
        onClose={handleCloseDeleteDialog}
        PaperProps={{ sx: { borderRadius: 3 } }}
      >
        <DialogTitle sx={{ fontWeight: 600 }}>
          Delete User: {userToDelete?.fullName}
        </DialogTitle>
        <DialogContent>
          <DialogContentText>
            Choose a deletion method. Deactivating is reversible, but permanent
            deletion is not.
          </DialogContentText>
        </DialogContent>
        <DialogActions sx={{ justifyContent: "space-between", p: 3, pt: 0 }}>
          <Button onClick={handleCloseDeleteDialog}>Cancel</Button>
          <Box sx={{ display: "flex", gap: 2 }}>
            <Button onClick={handleSoftDelete}>Deactivate</Button>
            <Button
              onClick={handlePermanentDelete}
              color="error"
              variant="contained"
            >
              Permanently Delete
            </Button>
          </Box>
        </DialogActions>
      </Dialog>

      <Dialog
        open={isBanDialogOpen}
        onClose={handleCloseBanDialog}
        PaperProps={{ sx: { borderRadius: 3 } }}
      >
        <DialogTitle sx={{ fontWeight: 600 }}>
          Ban User: {userToBan?.fullName}
        </DialogTitle>
        <DialogContent>
          <TextField
            autoFocus
            margin="dense"
            name="reason"
            label="Reason for Ban"
            type="text"
            fullWidth
            multiline
            rows={3}
            variant="outlined"
            value={banData.reason}
            onChange={handleBanInputChange}
            required
            sx={{ mb: 2 }}
          />
          <FormControl fullWidth>
            <InputLabel>Duration</InputLabel>
            <Select
              name="durationInDays"
              value={banData.durationInDays}
              label="Duration"
              onChange={handleBanInputChange}
            >
              <MenuItem value={1}>1 Day</MenuItem>
              <MenuItem value={7}>7 Days</MenuItem>
              <MenuItem value={30}>30 Days</MenuItem>
              <MenuItem value={0}>Permanent</MenuItem>
            </Select>
          </FormControl>
        </DialogContent>
        <DialogActions sx={{ p: 3, pt: 0 }}>
          <Button onClick={handleCloseBanDialog}>Cancel</Button>
          <Button
            onClick={handleBanSubmit}
            color="error"
            variant="contained"
            disabled={!banData.reason.trim()}
          >
            Confirm Ban
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
};

export default ManageUsersPage;