const dotenv = require("dotenv");

const connectDB = require("./config/db");
const seedDemoUser = require("./seed");
const app = require("./app");

dotenv.config();

const startServer = async () => {
  await connectDB();
  await seedDemoUser();

  const PORT = process.env.PORT || 3000;

  app.listen(PORT, () => {
    console.log(`Servidor rodando na porta ${PORT}`);
  });
};

startServer();
