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
} from "@mui/material";
import DeleteIcon from "@mui/icons-material/Delete";
import AddIcon from "@mui/icons-material/Add";
import EditIcon from "@mui/icons-material/Edit";
import BlockIcon from "@mui/icons-material/Block";
import RestoreFromTrashIcon from "@mui/icons-material/RestoreFromTrash";
import CheckCircleOutlineIcon from "@mui/icons-material/CheckCircleOutline";
import { logout } from "../services/authService";
import { useNavigate } from "react-router-dom";
import DownloadIcon from "@mui/icons-material/Download";
import Papa from "papaparse";

// --- Reusable Components ---

// ** NEW: Handler for the Export button **
const handleExportCSV = async () => {
  try {
    const usersToExport = await getUsersForExport();

    // Prepare the data for CSV conversion
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

const UserStatus = ({ user }) => {
  if (user.isBanned) return <Chip label="Banned" color="error" size="small" />;
  if (user.deletedAt)
    return <Chip label="Deactivated" color="default" size="small" />;
  return <Chip label="Active" color="success" size="small" />;
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
      />
      <TableContainer component={Paper}>
        <Table>
          <TableHead>
            <TableRow>
              {columns.map((col) => (
                <TableCell key={col.id} align={col.align || "left"}>
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
                  backgroundColor: user.isBanned
                    ? "rgba(255, 0, 0, 0.05)"
                    : "transparent",
                }}
              >
                {columns.map((col) => (
                  <TableCell key={col.id} align={col.align || "left"}>
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
  const [activeTab, setActiveTab] = useState(0);

  // ** MODIFIED: State management for each user list **
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

  // Dialog states remain the same
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

  // ** MODIFIED: Use useCallback for performance **
  const fetchAllData = useCallback(async () => {
    try {
      // Fetch all data in parallel
      const [all, banned, deleted] = await Promise.all([
        getAllUsers(allUsers.page),
        getBannedUsers(),
        getDeletedUsers(),
      ]);
      // Set the data for each list
      setAllUsers({
        list: all.users,
        page: all.currentPage,
        totalPages: all.totalPages,
      });
      setBannedUsers({ list: banned, page: 1, totalPages: 1 }); // Assuming no pagination for these yet
      setDeletedUsers({ list: deleted, page: 1, totalPages: 1 });
    } catch (error) {
      console.error("Failed to fetch user data", error);
      if (error.response && error.response.status === 401) {
        logout();
        navigate("/login");
      }
    }
  }, [allUsers.page, navigate]); // Dependency array

  useEffect(() => {
    fetchAllData();
  }, [fetchAllData]);

  // ** NEW: Handler for changing the page **
  const handlePageChange = (event, value) => {
    setAllUsers((prev) => ({ ...prev, page: value }));
  };

  // --- Handlers for Dialogs ---
  // These handlers call fetchAllData() to refresh all lists after an action
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

  // ** NEW: Handler for the Revert action **
  const handleRevertUser = async (user) => {
    if (
      window.confirm(
        `Are you sure you want to restore the account for ${user.fullName}?`
      )
    ) {
      try {
        await revertUserDeletion(user._id);
        fetchAllData(); // Refresh all lists
      } catch (error) {
        console.error("Failed to restore user", error);
      }
    }
  };

  const allUsersColumns = [
    { id: "name", label: "Full Name", render: (user) => user.fullName },
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
        <>
          <Tooltip title="Edit User">
            <span>
              <IconButton
                onClick={() => actions.onEdit(user)}
                disabled={user.isBanned || user.deletedAt}
              >
                <EditIcon />
              </IconButton>
            </span>
          </Tooltip>
          {user.isBanned ? (
            <Tooltip title="Unban User">
              <IconButton onClick={() => actions.onUnban(user)} color="success">
                <CheckCircleOutlineIcon />
              </IconButton>
            </Tooltip>
          ) : (
            <Tooltip title="Ban User">
              <span>
                <IconButton
                  onClick={() => actions.onBan(user)}
                  color="warning"
                  disabled={user.deletedAt}
                >
                  <BlockIcon />
                </IconButton>
              </span>
            </Tooltip>
          )}
          <Tooltip title="Delete Options">
            <span>
              <IconButton
                onClick={() => actions.onDelete(user)}
                color="error"
                disabled={user.deletedAt}
              >
                <DeleteIcon />
              </IconButton>
            </span>
          </Tooltip>
        </>
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
      <Box
        sx={{
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
          mb: 2,
        }}
      >
        <Typography variant="h5">Manage Users</Typography>
        <Box>
          <Button
            variant="outlined"
            startIcon={<DownloadIcon />}
            onClick={handleExportCSV}
            sx={{ mr: 2 }}
          >
            Export All as CSV
          </Button>
          <Button
            variant="contained"
            startIcon={<AddIcon />}
            onClick={handleOpenAddDialog}
          >
            Add User
          </Button>
        </Box>
      </Box>

      <Box sx={{ borderBottom: 1, borderColor: "divider" }}>
        <Tabs value={activeTab} onChange={handleTabChange}>
          <Tab label={`All Users (${allUsers.list.length})`} />
          <Tab label={`Banned (${bannedUsers.list.length})`} />
          <Tab label={`Deleted (${deletedUsers.list.length})`} />
        </Tabs>
      </Box>

      <Box sx={{ pt: 2 }}>
        {activeTab === 0 && (
          <>
            <UserTable
              title="All Users"
              users={allUsers.list} // Pass the list property
              columns={allUsersColumns}
              onEdit={handleOpenEditDialog}
              onBan={handleOpenBanDialog}
              onUnban={handleUnbanUser}
              onDelete={handleOpenDeleteDialog}
            />
            {/* ** ADDED: The Pagination Component ** */}
            <Box
              sx={{ display: "flex", justifyContent: "center", p: 2, mt: 2 }}
            >
              <Pagination
                count={allUsers.totalPages}
                page={allUsers.page}
                onChange={handlePageChange}
                color="primary"
                showFirstButton
                showLastButton
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

      {/* ... (All dialog components remain the same) ... */}
      <Dialog open={isUserFormOpen} onClose={handleCloseUserForm}>
        <DialogTitle>{isEditMode ? "Edit User" : "Add New User"}</DialogTitle>
        <DialogContent>
          <TextField
            autoFocus
            margin="dense"
            name="fullName"
            label="Full Name"
            type="text"
            fullWidth
            variant="standard"
            value={currentUserData.fullName}
            onChange={handleInputChange}
          />
          <TextField
            margin="dense"
            name="email"
            label="Email Address"
            type="email"
            fullWidth
            variant="standard"
            value={currentUserData.email}
            onChange={handleInputChange}
          />
          {!isEditMode && (
            <TextField
              margin="dense"
              name="password"
              label="Password"
              type="password"
              fullWidth
              variant="standard"
              value={currentUserData.password}
              onChange={handleInputChange}
            />
          )}
        </DialogContent>
        <DialogActions>
          <Button onClick={handleCloseUserForm}>Cancel</Button>
          <Button onClick={handleUserFormSubmit}>
            {isEditMode ? "Save Changes" : "Add User"}
          </Button>
        </DialogActions>
      </Dialog>
      <Dialog open={isDeleteDialogOpen} onClose={handleCloseDeleteDialog}>
        <DialogTitle>Delete User: {userToDelete?.fullName}</DialogTitle>
        <DialogContent>
          <DialogContentText>
            Choose a deletion method. Deactivating is reversible, but permanent
            deletion is not.
          </DialogContentText>
        </DialogContent>
        <DialogActions
          sx={{ justifyContent: "space-between", padding: "16px 24px" }}
        >
          <Button onClick={handleCloseDeleteDialog}>Cancel</Button>
          <div>
            <Button onClick={handleSoftDelete}>Deactivate (Soft Delete)</Button>
            <Button
              onClick={handlePermanentDelete}
              color="error"
              variant="contained"
            >
              Permanently Delete
            </Button>
          </div>
        </DialogActions>
      </Dialog>
      <Dialog open={isBanDialogOpen} onClose={handleCloseBanDialog}>
        <DialogTitle>Ban User: {userToBan?.fullName}</DialogTitle>
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
            variant="standard"
            value={banData.reason}
            onChange={handleBanInputChange}
            required
          />
          <FormControl fullWidth margin="normal">
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
        <DialogActions>
          <Button onClick={handleCloseBanDialog}>Cancel</Button>
          <Button
            onClick={handleBanSubmit}
            color="error"
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
