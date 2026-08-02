const User = require("./models/User");
const bcrypt = require("bcryptjs");

const seedDemoUser = async () => {
  if (process.env.SEED_DEMO !== "true") {
    return;
  }

  const email = "demo@pet.com";
  const existing = await User.findOne({ email });

  if (existing) {
    return;
  }

  await User.create({
    nome: "Demo User",
    email,
    senha: await bcrypt.hash("123456", 10)
  });

  console.log("Demo user created: demo@pet.com / 123456");
};

module.exports = seedDemoUser;
