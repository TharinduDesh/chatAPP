// FILE: routes/conversationRoutes.js
// Purpose: API endpoints for managing conversations with multiple admin support.
const expressConvRoutes = require("express");
const routerConvRoutes = expressConvRoutes.Router();
const { protect: protectConvRoutes } = require("../middleware/authMiddleware");
const ConversationModelConvRoutes = require("../models/Conversation"); // Uses new model with groupAdmins
const UserModelConvRoutes = require("../models/User");
const MessageModelConvRoutes = require("../models/Message");
const mongoose = require("mongoose");
const {
  upload: uploadMiddleware,
  handleMulterError: handleMulterErrorMiddleware,
} = require("../middleware/uploadMiddleware");
const path = require("path");
const fs = require("fs");

// Helper function to populate conversation details
const populateConversation = (conversation) => {
  if (!conversation) return null;
  return conversation.populate([
    { path: "participants", select: "fullName email profilePictureUrl" },
    { path: "groupAdmins", select: "fullName email profilePictureUrl" }, // Populate new groupAdmins field
    {
      path: "lastMessage",
      populate: { path: "sender", select: "fullName email profilePictureUrl" },
    },
  ]);
};

// @desc    Get all conversations for the logged-in user
// @route   GET /api/conversations
// @access  Private
// <<< MODIFIED to calculate and include unreadCount >>>
routerConvRoutes.get("/", protectConvRoutes, async (req, res) => {
  try {
    let conversations = await ConversationModelConvRoutes.find({
      participants: req.user._id,
    })
      .populate("participants", "-password")
      .populate("groupAdmins", "-password")
      .populate({
        path: "lastMessage",
        populate: {
          path: "sender",
          select: "fullName email profilePictureUrl",
        },
      })
      .sort({ updatedAt: -1 })
      .lean(); // Use .lean() for plain JS objects, faster for modification

    // For each conversation, calculate the unread count for the current user
    const conversationsWithUnreadCount = await Promise.all(
      conversations.map(async (convo) => {
        const unreadCount = await MessageModelConvRoutes.countDocuments({
          conversationId: convo._id,
          // Count messages where the readBy array does NOT contain the current user's ID
          readBy: { $nin: [req.user._id] },
          // And the message was not sent by the current user
          sender: { $ne: req.user._id },
        });
        return { ...convo, unreadCount }; // Append unreadCount to the conversation object
      })
    );

    res.json(conversationsWithUnreadCount);
  } catch (error) {
    console.error("Get Conversations Error:", error);
    res.status(500).json({
      message: "Server error fetching conversations.",
      error: error.message,
    });
  }
});

// <<< NEW ROUTE: Mark all messages in a conversation as read >>>
// @desc    Mark messages in a conversation as read by the current user
// @route   PUT /api/conversations/:conversationId/read
// @access  Private
routerConvRoutes.put(
  "/:conversationId/read",
  protectConvRoutes,
  async (req, res) => {
    const { conversationId } = req.params;
    const currentUserId = req.user._id;

    try {
      if (!mongoose.Types.ObjectId.isValid(conversationId)) {
        return res
          .status(400)
          .json({ message: "Invalid conversation ID format." });
      }

      // Add the current user's ID to the 'readBy' array of all messages
      // in this conversation where they are not already present.
      const result = await MessageModelConvRoutes.updateMany(
        {
          conversationId: conversationId,
          readBy: { $nin: [currentUserId] }, // Find messages not read by this user
        },
        {
          $addToSet: { readBy: currentUserId }, // Add user's ID to the readBy array
        },
        { new: true }
      );

      console.log(
        `Marked as read for user ${currentUserId} in convo ${conversationId}. Messages updated: ${result.modifiedCount}`
      );

      res.status(200).json({
        message: "Messages marked as read successfully.",
        modifiedCount: result.modifiedCount,
      });
    } catch (error) {
      console.error("Mark as Read Error:", error);
      res
        .status(500)
        .json({ message: "Server error marking messages as read." });
    }
  }
);

// @desc    Create or get a one-to-one conversation
// @route   POST /api/conversations/one-to-one
// @access  Private
routerConvRoutes.post("/one-to-one", protectConvRoutes, async (req, res) => {
  const { userId: otherUserIdString } = req.body;
  const currentUserId = req.user._id;

  if (!otherUserIdString)
    return res.status(400).json({ message: "Other user ID is required." });
  if (otherUserIdString.toString() === currentUserId.toString())
    return res
      .status(400)
      .json({ message: "Cannot create a conversation with yourself." });

  let otherUserObjectId;
  try {
    if (!mongoose.Types.ObjectId.isValid(otherUserIdString))
      return res
        .status(400)
        .json({ message: "Invalid format for other user ID." });
    otherUserObjectId = new mongoose.Types.ObjectId(otherUserIdString);
    const otherUser = await UserModelConvRoutes.findById(otherUserObjectId);
    if (!otherUser)
      return res.status(404).json({ message: "The other user was not found." });
  } catch (e) {
    return res.status(500).json({ message: "Error verifying other user." });
  }

  const participants = [currentUserId, otherUserObjectId].sort((a, b) =>
    a.toString().localeCompare(b.toString())
  );

  try {
    let conversation = await ConversationModelConvRoutes.findOne({
      isGroupChat: false,
      participants: { $all: participants, $size: 2 },
    });
    if (conversation) {
      conversation = await populateConversation(conversation);
      return res.status(200).json(conversation);
    }

    conversation = new ConversationModelConvRoutes({
      participants: [currentUserId, otherUserObjectId],
      isGroupChat: false,
      // groupAdmins will be empty for 1-to-1 chats
    });
    await conversation.save();
    conversation = await populateConversation(conversation);
    return res.status(201).json(conversation);
  } catch (error) {
    res
      .status(500)
      .json({ message: "Server error processing one-to-one conversation." });
  }
});

// @desc    Create a new group chat
// @route   POST /api/conversations/group
// @access  Private
routerConvRoutes.post("/group", protectConvRoutes, async (req, res) => {
  const { name, participants: participantIdStrings } = req.body;
  const currentUserId = req.user._id; // This is an ObjectId

  if (!name || name.trim() === "")
    return res.status(400).json({ message: "Group name is required." });
  // For group creation, participantIdStrings are the *other* members to add. Creator is added automatically.
  if (!participantIdStrings || !Array.isArray(participantIdStrings)) {
    // Allow empty initially if only creator
    // return res.status(400).json({ message: "Participants array is required." });
  }

  let participantObjectIds = [];
  try {
    for (const idStr of participantIdStrings) {
      // participantIdStrings could be empty
      if (!mongoose.Types.ObjectId.isValid(idStr))
        return res
          .status(400)
          .json({ message: `Participant ID '${idStr}' is invalid.` });
      participantObjectIds.push(new mongoose.Types.ObjectId(idStr));
    }
  } catch (e) {
    return res
      .status(400)
      .json({ message: "Error processing participant IDs." });
  }

  // Add current user and ensure uniqueness for participants
  const allParticipantObjectIdsIncludingCurrentUser = [
    currentUserId,
    ...participantObjectIds,
  ];
  const uniqueParticipantStringIds = [
    ...new Set(
      allParticipantObjectIdsIncludingCurrentUser.map((id) => id.toString())
    ),
  ];
  const finalParticipantObjectIds = uniqueParticipantStringIds.map(
    (idStr) => new mongoose.Types.ObjectId(idStr)
  );

  if (finalParticipantObjectIds.length < 2 && participantIdStrings.length > 0) {
    // If trying to add members but final count is < 2
    return res.status(400).json({
      message:
        "A group chat needs at least two unique participants when adding others.",
    });
  }
  if (finalParticipantObjectIds.length < 1) {
    // Should not happen if currentUserId is always added
    return res.status(400).json({
      message: "Group must have at least one participant (the creator).",
    });
  }

  try {
    const usersExist = await UserModelConvRoutes.find({
      _id: { $in: finalParticipantObjectIds },
    }).select("_id");
    if (usersExist.length !== finalParticipantObjectIds.length) {
      const foundIds = usersExist.map((u) => u._id.toString());
      const notFoundIds = finalParticipantObjectIds
        .map((id) => id.toString())
        .filter((idStr) => !foundIds.includes(idStr));
      return res.status(404).json({
        message: `Users not found for IDs: ${notFoundIds.join(", ")}`,
      });
    }
  } catch (userCheckError) {
    return res.status(500).json({ message: "Error verifying participants." });
  }

  try {
    const newGroupConversation = new ConversationModelConvRoutes({
      groupName: name.trim(),
      participants: finalParticipantObjectIds,
      isGroupChat: true,
      groupAdmins: [currentUserId], // <<< Creator is the initial admin
    });
    let savedGroup = await newGroupConversation.save();
    savedGroup = await populateConversation(savedGroup);
    res.status(201).json(savedGroup);
  } catch (error) {
    res.status(500).json({ message: "Server error creating group chat." });
  }
});

// @desc    Upload or update a group's profile picture
// @route   PUT /api/conversations/group/:conversationId/picture
routerConvRoutes.put(
  "/group/:conversationId/picture",
  protectConvRoutes,
  uploadMiddleware.single("groupPicture"),
  handleMulterErrorMiddleware,
  async (req, res) => {
    const { conversationId } = req.params;
    const currentUserId = req.user._id;

    if (!req.file)
      return res.status(400).json({ message: "No file uploaded." });

    let conversation;
    try {
      if (!mongoose.Types.ObjectId.isValid(conversationId)) {
        if (fs.existsSync(req.file.path)) fs.unlinkSync(req.file.path);
        return res
          .status(400)
          .json({ message: "Invalid conversation ID format." });
      }
      conversation = await ConversationModelConvRoutes.findById(conversationId);
    } catch (e) {
      if (fs.existsSync(req.file.path)) fs.unlinkSync(req.file.path);
      return res.status(500).json({ message: "Error finding conversation." });
    }

    if (!conversation) {
      if (fs.existsSync(req.file.path)) fs.unlinkSync(req.file.path);
      return res.status(404).json({ message: "Group conversation not found." });
    }
    if (!conversation.isGroupChat) {
      if (fs.existsSync(req.file.path)) fs.unlinkSync(req.file.path);
      return res.status(400).json({ message: "Not a group conversation." });
    }

    // <<< MODIFIED: Check if current user is in groupAdmins array >>>
    if (
      !conversation.groupAdmins.some((adminId) => adminId.equals(currentUserId))
    ) {
      if (fs.existsSync(req.file.path)) fs.unlinkSync(req.file.path);
      return res
        .status(403)
        .json({ message: "Only group admins can change the group picture." });
    }

    if (
      conversation.groupPictureUrl &&
      conversation.groupPictureUrl.startsWith("/uploads/")
    ) {
      const oldPicPath = path.join(
        __dirname,
        "..",
        "uploads",
        "profile_pictures",
        path.basename(conversation.groupPictureUrl)
      );
      if (fs.existsSync(oldPicPath)) {
        try {
          fs.unlinkSync(oldPicPath);
        } catch (e) {
          console.error("Error deleting old group pic:", e);
        }
      }
    }
    conversation.groupPictureUrl = `/uploads/profile_pictures/${req.file.filename}`;
    try {
      await conversation.save();
      const updatedConversation = await populateConversation(conversation);
      res.json({
        message: "Group picture updated!",
        conversation: updatedConversation,
      });
      // TODO: Emit 'conversationUpdated' to group members via socket
    } catch (saveError) {
      if (fs.existsSync(req.file.path)) fs.unlinkSync(req.file.path);
      res.status(500).json({ message: "Error updating group picture info." });
    }
  }
);

// @desc    Update a group's name
// @route   PUT /api/conversations/group/:conversationId/name
routerConvRoutes.put(
  "/group/:conversationId/name",
  protectConvRoutes,
  async (req, res) => {
    const { conversationId } = req.params;
    const { name: newGroupName } = req.body;
    const currentUserId = req.user._id;

    if (!newGroupName || newGroupName.trim() === "")
      return res.status(400).json({ message: "New group name is required." });

    try {
      if (!mongoose.Types.ObjectId.isValid(conversationId))
        return res
          .status(400)
          .json({ message: "Invalid conversation ID format." });
      const conversation = await ConversationModelConvRoutes.findById(
        conversationId
      );
      if (!conversation)
        return res
          .status(404)
          .json({ message: "Group conversation not found." });
      if (!conversation.isGroupChat)
        return res
          .status(400)
          .json({ message: "This is not a group conversation." });

      // <<< MODIFIED: Check if current user is in groupAdmins array >>>
      if (
        !conversation.groupAdmins.some((adminId) =>
          adminId.equals(currentUserId)
        )
      ) {
        return res
          .status(403)
          .json({ message: "Only group admins can change the group name." });
      }

      conversation.groupName = newGroupName.trim();
      await conversation.save();
      const updatedConversation = await populateConversation(conversation);
      // TODO: Emit 'conversationUpdated'
      res.status(200).json({
        message: "Group name updated successfully.",
        conversation: updatedConversation,
      });
    } catch (error) {
      res.status(500).json({ message: "Server error updating group name." });
    }
  }
);

// @desc    Leave a group conversation
// @route   PUT /api/conversations/group/:conversationId/leave
routerConvRoutes.put(
  "/group/:conversationId/leave",
  protectConvRoutes,
  async (req, res) => {
    const { conversationId } = req.params;
    const currentUserId = req.user._id;

    try {
      if (!mongoose.Types.ObjectId.isValid(conversationId))
        return res
          .status(400)
          .json({ message: "Invalid conversation ID format." });
      const conversation = await ConversationModelConvRoutes.findById(
        conversationId
      );
      if (!conversation)
        return res.status(404).json({ message: "Conversation not found." });
      if (!conversation.isGroupChat)
        return res
          .status(400)
          .json({ message: "This is not a group conversation." });

      const participantIndex = conversation.participants.findIndex((pId) =>
        pId.equals(currentUserId)
      );
      if (participantIndex === -1)
        return res
          .status(403)
          .json({ message: "You are not a member of this group." });

      conversation.participants.splice(participantIndex, 1);

      let adminUpdatedOrRemoved = false;
      let groupDeleted = false;

      // Remove from admins list if they were an admin
      const adminIndex = conversation.groupAdmins.findIndex((adminId) =>
        adminId.equals(currentUserId)
      );
      if (adminIndex !== -1) {
        conversation.groupAdmins.splice(adminIndex, 1);
        adminUpdatedOrRemoved = true;
        // If no admins left and participants exist, assign a new admin
        if (
          conversation.groupAdmins.length === 0 &&
          conversation.participants.length > 0
        ) {
          conversation.groupAdmins.push(conversation.participants[0]); // Assign first remaining participant as admin
          console.log(
            `Admin ${currentUserId.toString()} left. New admin assigned: ${conversation.participants[0].toString()}`
          );
        }
      }

      if (conversation.participants.length === 0) {
        // If group becomes empty
        await ConversationModelConvRoutes.findByIdAndDelete(conversationId);
        groupDeleted = true;
        // TODO: Delete associated messages if group is deleted
        return res
          .status(200)
          .json({ message: "Group left and deleted (empty).", deleted: true });
      }

      if (!groupDeleted) await conversation.save();

      const finalConversationState = groupDeleted
        ? null
        : await populateConversation(
            await ConversationModelConvRoutes.findById(conversation._id)
          );

      // TODO: Emit 'conversationUpdated' or specific events
      res.status(200).json({
        message:
          "Successfully left group." +
          (adminUpdatedOrRemoved &&
          conversation.groupAdmins.length > 0 &&
          !groupDeleted
            ? " Admin roles updated."
            : ""),
        conversation: finalConversationState,
        deleted: groupDeleted,
      });
    } catch (error) {
      res.status(500).json({ message: "Server error leaving group." });
    }
  }
);

// @desc    Add Member to Group
// @route   PUT /api/conversations/group/:conversationId/add-member
routerConvRoutes.put(
  "/group/:conversationId/add-member",
  protectConvRoutes,
  async (req, res) => {
    const { conversationId } = req.params;
    const { userId: userIdToAddString } = req.body;
    const currentUserId = req.user._id;

    if (!userIdToAddString)
      return res.status(400).json({ message: "User ID to add is required." });

    try {
      if (!mongoose.Types.ObjectId.isValid(conversationId))
        return res
          .status(400)
          .json({ message: "Invalid conversation ID format." });
      if (!mongoose.Types.ObjectId.isValid(userIdToAddString))
        return res
          .status(400)
          .json({ message: "Invalid user ID format for member to add." });

      const conversation = await ConversationModelConvRoutes.findById(
        conversationId
      );
      if (!conversation)
        return res
          .status(404)
          .json({ message: "Group conversation not found." });
      if (!conversation.isGroupChat)
        return res
          .status(400)
          .json({ message: "This is not a group conversation." });

      // <<< MODIFIED: Check if current user is in groupAdmins array >>>
      if (
        !conversation.groupAdmins.some((adminId) =>
          adminId.equals(currentUserId)
        )
      ) {
        return res
          .status(403)
          .json({ message: "Only group admins can add members." });
      }

      const userObjectIdToAdd = new mongoose.Types.ObjectId(userIdToAddString);
      const userToAddExists = await UserModelConvRoutes.findById(
        userObjectIdToAdd
      );
      if (!userToAddExists)
        return res.status(404).json({ message: "User to add not found." });
      if (
        conversation.participants.some((pId) => pId.equals(userObjectIdToAdd))
      )
        return res
          .status(400)
          .json({ message: "User is already a member of this group." });

      conversation.participants.push(userObjectIdToAdd);
      await conversation.save();
      const updatedConversation = await populateConversation(conversation);
      // TODO: Emit 'conversationUpdated'
      res.status(200).json({
        message: `${userToAddExists.fullName} added successfully.`,
        conversation: updatedConversation,
      });
    } catch (error) {
      res.status(500).json({ message: "Server error adding member to group." });
    }
  }
);

// @desc    Remove Member from Group
// @route   PUT /api/conversations/group/:conversationId/remove-member
routerConvRoutes.put(
  "/group/:conversationId/remove-member",
  protectConvRoutes,
  async (req, res) => {
    const { conversationId } = req.params;
    const { userId: userIdToRemoveString } = req.body;
    const currentUserId = req.user._id;

    if (!userIdToRemoveString)
      return res
        .status(400)
        .json({ message: "User ID to remove is required." });

    try {
      if (!mongoose.Types.ObjectId.isValid(conversationId))
        return res
          .status(400)
          .json({ message: "Invalid conversation ID format." });
      if (!mongoose.Types.ObjectId.isValid(userIdToRemoveString))
        return res
          .status(400)
          .json({ message: "Invalid user ID format for member to remove." });

      const conversation = await ConversationModelConvRoutes.findById(
        conversationId
      );
      if (!conversation)
        return res
          .status(404)
          .json({ message: "Group conversation not found." });
      if (!conversation.isGroupChat)
        return res
          .status(400)
          .json({ message: "This is not a group conversation." });

      // <<< MODIFIED: Check if current user is in groupAdmins array >>>
      if (
        !conversation.groupAdmins.some((adminId) =>
          adminId.equals(currentUserId)
        )
      ) {
        return res
          .status(403)
          .json({ message: "Only group admins can remove members." });
      }

      const userObjectIdToRemove = new mongoose.Types.ObjectId(
        userIdToRemoveString
      );

      // An admin cannot remove another admin using this route (use demote/transfer admin routes for that)
      // unless they are removing a non-admin member.
      const isTargetAdmin = conversation.groupAdmins.some((adminId) =>
        adminId.equals(userObjectIdToRemove)
      );
      if (isTargetAdmin && !userObjectIdToRemove.equals(currentUserId)) {
        // Admin trying to remove another admin
        return res.status(400).json({
          message:
            "Cannot remove another admin using this action. Use 'Demote Admin' or 'Transfer Admin'.",
        });
      }
      // Admin cannot remove themselves using this route if they are an admin.
      if (
        isTargetAdmin &&
        userObjectIdToRemove.equals(currentUserId) &&
        conversation.groupAdmins.length === 1
      ) {
        return res.status(400).json({
          message:
            "You are the only admin. To leave, use 'Leave Group'. To remove yourself as admin, first make someone else an admin.",
        });
      }

      const participantIndex = conversation.participants.findIndex((pId) =>
        pId.equals(userObjectIdToRemove)
      );
      if (participantIndex === -1)
        return res
          .status(404)
          .json({ message: "User is not a member of this group." });

      conversation.participants.splice(participantIndex, 1);
      // Also remove from admins if they were an admin (and not the one performing action, and not last admin)
      const adminIndexToRemove = conversation.groupAdmins.findIndex((adminId) =>
        adminId.equals(userObjectIdToRemove)
      );
      if (adminIndexToRemove !== -1) {
        // Only allow removal from admin list if they are not the last admin,
        // or if the one performing action is removing themselves (which is covered by "Leave Group").
        // This simple "remove member" shouldn't leave a group admin-less.
        if (conversation.groupAdmins.length > 1) {
          conversation.groupAdmins.splice(adminIndexToRemove, 1);
        } else if (!userObjectIdToRemove.equals(conversation.groupAdmins[0])) {
          // If target is not the only admin, it's fine. If target IS the only admin, this removal won't proceed due to above checks.
          // This logic is a bit complex. The main idea is: if you remove a member who HAPPENS to be an admin,
          // they are also removed from admin list ONLY IF they are not the last admin.
        }
      }

      // If group becomes empty, delete it
      if (conversation.participants.length === 0) {
        await ConversationModelConvRoutes.findByIdAndDelete(conversationId);
        return res.status(200).json({
          message: "Member removed and group deleted as it became empty.",
          deleted: true,
        });
      }

      await conversation.save();
      const updatedConversation = await populateConversation(conversation);
      // TODO: Emit 'conversationUpdated'
      res.status(200).json({
        message: "Member removed successfully.",
        conversation: updatedConversation,
      });
    } catch (error) {
      res
        .status(500)
        .json({ message: "Server error removing member from group." });
    }
  }
);

// <<< NEW ROUTE: Promote a member to admin >>>
// @desc    Make another member an admin of the group
// @route   PUT /api/conversations/group/:conversationId/promote-admin
// @access  Private (Only Current Group Admins)
// @body    { userIdToPromote: "ID of the member to make admin" }
routerConvRoutes.put(
  "/group/:conversationId/promote-admin",
  protectConvRoutes,
  async (req, res) => {
    const { conversationId } = req.params;
    const { userIdToPromote } = req.body;
    const currentUserId = req.user._id;

    if (!userIdToPromote)
      return res
        .status(400)
        .json({ message: "User ID to promote is required." });

    try {
      if (!mongoose.Types.ObjectId.isValid(conversationId))
        return res
          .status(400)
          .json({ message: "Invalid conversation ID format." });
      if (!mongoose.Types.ObjectId.isValid(userIdToPromote))
        return res
          .status(400)
          .json({ message: "Invalid user ID format for promotion." });

      const conversation = await ConversationModelConvRoutes.findById(
        conversationId
      );
      if (!conversation)
        return res
          .status(404)
          .json({ message: "Group conversation not found." });
      if (!conversation.isGroupChat)
        return res
          .status(400)
          .json({ message: "This is not a group conversation." });

      if (
        !conversation.groupAdmins.some((adminId) =>
          adminId.equals(currentUserId)
        )
      ) {
        return res.status(403).json({
          message: "Only current group admins can promote other members.",
        });
      }

      const userToPromoteObjectId = new mongoose.Types.ObjectId(
        userIdToPromote
      );

      if (
        !conversation.participants.some((pId) =>
          pId.equals(userToPromoteObjectId)
        )
      ) {
        return res.status(400).json({
          message: "The selected user is not a member of this group.",
        });
      }
      if (
        conversation.groupAdmins.some((adminId) =>
          adminId.equals(userToPromoteObjectId)
        )
      ) {
        return res
          .status(400)
          .json({ message: "This user is already an admin." });
      }

      conversation.groupAdmins.push(userToPromoteObjectId);
      await conversation.save();
      const updatedConversation = await populateConversation(conversation);
      // TODO: Emit 'conversationUpdated'
      res.status(200).json({
        message: "User promoted to admin successfully.",
        conversation: updatedConversation,
      });
    } catch (error) {
      res.status(500).json({ message: "Server error promoting admin." });
    }
  }
);

// <<< NEW ROUTE: Demote an admin (remove from admin list, not from group) >>>
// @desc    Demote an admin (they remain a participant)
// @route   PUT /api/conversations/group/:conversationId/demote-admin
// @access  Private (Only Current Group Admins)
// @body    { userIdToDemote: "ID of the admin to demote" }
routerConvRoutes.put(
  "/group/:conversationId/demote-admin",
  protectConvRoutes,
  async (req, res) => {
    const { conversationId } = req.params;
    const { userIdToDemote } = req.body;
    const currentUserId = req.user._id;

    if (!userIdToDemote)
      return res
        .status(400)
        .json({ message: "User ID to demote is required." });

    try {
      if (!mongoose.Types.ObjectId.isValid(conversationId))
        return res
          .status(400)
          .json({ message: "Invalid conversation ID format." });
      if (!mongoose.Types.ObjectId.isValid(userIdToDemote))
        return res
          .status(400)
          .json({ message: "Invalid user ID format for demotion." });

      const conversation = await ConversationModelConvRoutes.findById(
        conversationId
      );
      if (!conversation)
        return res
          .status(404)
          .json({ message: "Group conversation not found." });
      if (!conversation.isGroupChat)
        return res
          .status(400)
          .json({ message: "This is not a group conversation." });

      if (
        !conversation.groupAdmins.some((adminId) =>
          adminId.equals(currentUserId)
        )
      ) {
        return res.status(403).json({
          message: "Only current group admins can demote other admins.",
        });
      }

      const userToDemoteObjectId = new mongoose.Types.ObjectId(userIdToDemote);

      if (
        userToDemoteObjectId.equals(currentUserId) &&
        conversation.groupAdmins.length === 1
      ) {
        return res.status(400).json({
          message:
            "You cannot demote yourself as the only admin. Promote another member first or leave the group.",
        });
      }

      const adminIndex = conversation.groupAdmins.findIndex((adminId) =>
        adminId.equals(userToDemoteObjectId)
      );
      if (adminIndex === -1) {
        return res
          .status(400)
          .json({ message: "This user is not currently an admin." });
      }

      conversation.groupAdmins.splice(adminIndex, 1);

      // Ensure there's at least one admin left (covered by pre-save hook as a fallback, but good to check here)
      if (
        conversation.groupAdmins.length === 0 &&
        conversation.participants.length > 0
      ) {
        // This should ideally not be reached if the self-demotion as last admin is caught.
        // If it is, make the current operator (who is demoting someone else) the admin if they are a participant.
        // Or, more simply, the pre-save hook will assign the first participant.
        // For safety, we re-ensure the current operator (who must be an admin to reach here) remains if they are the one.
        // This logic becomes complex; the pre-save is a good safety net.
        // If the admin demoted the *last other admin*, and they themselves are not in list (shouldn't happen),
        // the pre-save hook on Conversation model will assign an admin.
        console.warn(
          "Demotion resulted in no admins. The pre-save hook should assign one."
        );
      }

      await conversation.save();
      const updatedConversation = await populateConversation(conversation);
      // TODO: Emit 'conversationUpdated'
      res.status(200).json({
        message: "Admin demoted successfully.",
        conversation: updatedConversation,
      });
    } catch (error) {
      res.status(500).json({ message: "Server error demoting admin." });
    }
  }
);

module.exports = routerConvRoutes;
