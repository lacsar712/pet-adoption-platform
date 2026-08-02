const express = require("express");

const {
  registerUser,
  loginUser,
  getMe
} = require("../controllers/authController");

const authMiddleware = require("../middlewares/authMiddleware");

const router = express.Router();

router.post("/auth/register", registerUser);
router.post("/auth/login", loginUser);
router.get("/auth/me", authMiddleware, getMe);

module.exports = router;