// chat-backend/routes/analyticsRoutes.js
const express = require("express");
const router = express.Router();
const { protectAdmin } = require("../middleware/adminAuthMiddleware");
const User = require("../models/User");
const Conversation = require("../models/Conversation");
const Message = require("../models/Message");
const {
  subDays,
  startOfDay,
  endOfDay,
  format,
  eachDayOfInterval,
  startOfMonth,
  endOfMonth,
  eachMonthOfInterval,
  startOfYear,
} = require("date-fns");

/**
 * @route   GET /api/analytics/stats
 * @desc    Get dashboard summary statistics
 * @access  Private (Admin only)
 */
router.get("/stats", protectAdmin, async (req, res) => {
  try {
    // ** MODIFIED: Accept startDate and endDate from query **
    const { startDate, endDate } = req.query;

    // Create a date filter if dates are provided
    const dateFilter = {};
    if (startDate && endDate) {
      dateFilter.createdAt = {
        $gte: startOfDay(new Date(startDate)),
        $lte: endOfDay(new Date(endDate)),
      };
    }

    // Apply the date filter to the queries
    const totalUsers = await User.countDocuments(dateFilter);
    const totalConversations = await Conversation.countDocuments(dateFilter);
    const totalMessages = await Message.countDocuments(dateFilter);

    const activeUsersMap = req.app.get("activeUsers") || {};
    // Get all connected IDs, filter out the admins, then get the count.
    const onlineUserCount = Object.keys(activeUsersMap).filter(
      (id) => !id.startsWith("admin_")
    ).length;

    res.json({
      totalUsers,
      totalConversations,
      totalMessages,
      onlineUserCount,
    });
  } catch (error) {
    res.status(500).json({ message: "Server error fetching stats." });
  }
});

/**
 * @route   GET /api/analytics/new-users-chart
 * @desc    Get data for new user signups for a specific period
 * @access  Private (Admin only)
 */
router.get("/new-users-chart", protectAdmin, async (req, res) => {
  try {
    const period = req.query.period || "week"; // Default to 'week'
    const today = new Date();
    let startDate, endDate, dateFormat, interval, dateLabels;

    if (period === "year") {
      startDate = startOfYear(today);
      endDate = today;
      dateFormat = "%Y-%m"; // Group by month
      interval = eachMonthOfInterval({ start: startDate, end: endDate });
      dateLabels = interval.map((d) => ({
        date: format(d, "MMM"),
        "New Users": 0,
      }));
    } else {
      startDate = period === "month" ? subDays(today, 29) : subDays(today, 6);
      endDate = today;
      dateFormat = "%Y-%m-%d"; // Group by day
      interval = eachDayOfInterval({ start: startDate, end: endDate });
      dateLabels = interval.map((d) => ({
        date: format(d, "EEE, d"),
        "New Users": 0,
      }));
    }

    const userSignups = await User.aggregate([
      { $match: { createdAt: { $gte: startDate, $lte: endOfDay(endDate) } } },
      {
        $group: {
          _id: { $dateToString: { format: dateFormat, date: "$createdAt" } },
          count: { $sum: 1 },
        },
      },
      { $sort: { _id: 1 } },
    ]);

    // Map the results to our labels
    const signupMap = new Map(
      userSignups.map((item) => [item._id, item.count])
    );

    const finalChartData = dateLabels.map((label) => {
      const dateKey =
        period === "year"
          ? format(interval[dateLabels.indexOf(label)], "yyyy-MM")
          : format(interval[dateLabels.indexOf(label)], "yyyy-MM-dd");
      return {
        ...label,
        "New Users": signupMap.get(dateKey) || 0,
      };
    });

    res.json(finalChartData);
  } catch (error) {
    console.error("Chart Data Error:", error);
    res.status(500).json({ message: "Server error fetching chart data." });
  }
});

/**
 * @route   GET /api/analytics/most-active-users
 * @desc    Get the top 5 most active users by message count
 * @access  Private (Admin only)
 */
router.get("/most-active-users", protectAdmin, async (req, res) => {
  try {
    const mostActiveUsers = await Message.aggregate([
      // Stage 1: Group messages by sender and count them
      {
        $group: {
          _id: "$sender", // Group by the sender's ObjectId
          messageCount: { $sum: 1 }, // Count the number of documents in each group
        },
      },
      // Stage 2: Sort the groups by message count in descending order
      {
        $sort: { messageCount: -1 },
      },
      // Stage 3: Limit the results to the top 5
      {
        $limit: 5,
      },
      // Stage 4: Join with the 'users' collection to get user details
      {
        $lookup: {
          from: "users", // The collection to join with
          localField: "_id", // The field from the input documents (the grouped sender ID)
          foreignField: "_id", // The field from the documents of the "from" collection
          as: "userDetails", // The name of the new array field to add
        },
      },
      // Stage 5: Deconstruct the userDetails array and merge its fields
      {
        $unwind: "$userDetails",
      },
      // Stage 6: Project the final fields we want to send to the client
      {
        $project: {
          _id: 0, // Exclude the default _id field
          userId: "$userDetails._id",
          fullName: "$userDetails.fullName",
          profilePictureUrl: "$userDetails.profilePictureUrl",
          messageCount: "$messageCount",
        },
      },
    ]);

    res.json(mostActiveUsers);
  } catch (error) {
    console.error("Most Active Users Error:", error);
    res.status(500).json({ message: "Server error fetching active users." });
  }
});

module.exports = router;
