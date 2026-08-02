const dotenv = require("dotenv");
dotenv.config();

const express = require("express");
const cors = require("cors");

const petsRoutes = require("./routes/petsRoutes");
const errorMiddleware = require("./middlewares/errorMiddleware");
const authRoutes = require("./routes/authRoutes");
const { uploadsDir } = require("./config/upload");

const app = express();

app.use(express.json());
app.use("/uploads", express.static(uploadsDir));

const allowedOrigins = [
  "http://localhost:5173",
  "http://localhost:3731",
  "http://localhost:8080",
  "https://pet-adoption-platform-nine.vercel.app"
];

app.use(
  cors({
    origin: function (origin, callback) {
      if (!origin || allowedOrigins.includes(origin)) {
        callback(null, true);
      } else {
        callback(new Error("Origem não permitida pelo CORS"));
      }
    }
  })
);

app.use(petsRoutes);
app.use(authRoutes);

// 轻量存活探测端点：不依赖 Mongo 连接，供容器/流水线 healthcheck 使用。
// 容器内直连 http://localhost:8731/health；经 Nginx 反代时为 /api/health。
app.get("/health", (req, res) => {
  res.json({
    status: "ok",
    uptime: process.uptime(),
    env: process.env.PET_APP_ENV || "demo"
  });
});

app.get("/", (req, res) => {
  res.send("Servidor atualizado pelo nodemon");
});

app.use(errorMiddleware);

module.exports = app;