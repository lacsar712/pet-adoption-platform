const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const User = require("../models/User");

const registerUser = async (req, res, next) => {
  try {
    const { nome, email, senha } = req.body;

    const userExists = await User.findOne({ email });

    if (userExists) {
      return res.status(400).json({ mensagem: "Usuário já cadastrado" });
    }

    const hashedPassword = await bcrypt.hash(senha, 10);

    const user = await User.create({
      nome,
      email,
      senha: hashedPassword
    });

    res.status(201).json({
      id: user._id,
      nome: user.nome,
      email: user.email
    });
  } catch (error) {
    next(error);
  }
};

const loginUser = async (req, res, next) => {
  try {
    const { email, senha } = req.body;

    const user = await User.findOne({ email });

    if (!user) {
      return res.status(401).json({
        mensagem: "E-mail ou senha inválidos"
      });
    }

    const senhaCorreta = await bcrypt.compare(senha, user.senha);

    if (!senhaCorreta) {
      return res.status(401).json({
        mensagem: "E-mail ou senha inválidos"
      });
    }

    const token = jwt.sign(
      { id: user._id },
      process.env.JWT_SECRET,
      { expiresIn: "1d" }
    );

    res.status(200).json({
      mensagem: "Login realizado com sucesso",
      token,
      usuario: {
        id: user._id,
        nome: user.nome,
        email: user.email
      }
    });
  } catch (error) {
    next(error);
  }
};

const getMe = async (req, res) => {
  const usuario = await User.findById(req.userId).select("-senha");

  res.json(usuario);
};

module.exports = {
  registerUser,
  loginUser,
  getMe
};