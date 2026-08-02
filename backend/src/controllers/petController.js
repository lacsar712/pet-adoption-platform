const Pet = require("../models/Pet");
const { uploadImagem } = require("../config/upload");

const getPets = async (req, res, next) => {
    try {
        const pets = await Pet.find();

        res.json(pets);

    } catch (error) {
        next(error);
    }
};

const getPetById = async (req, res, next) => {
    try {
        const pet = await Pet.findById(req.params.id);

        if (!pet) {
            return res.status(404).json({
                mensagem: "Pet não encontrado"
            });
        }

        res.json(pet);

    } catch (error) {
        next(error);
    }
};

const createPet = async (req, res, next) => {
  try {
    const petData = {
      ...req.body,
      usuario: req.userId
    }

    if (req.file) {
      const resultadoUpload = await uploadImagem(
        req.file.buffer,
        req.file.originalname
      );

      petData.imagem = resultadoUpload.secure_url;
    }

    const pet = await Pet.create(petData)

    res.status(201).json(pet)

  } catch (error) {
    console.error("Erro ao criar pet:", error)
    next(error)
  }
}

const updatePet = async (req, res, next) => {
  try {
    const pet = await Pet.findById(req.params.id);

    if (!pet) {
      return res.status(404).json({
        mensagem: "Pet não encontrado"
      });
    }

    if (pet.usuario.toString() !== req.userId) {
      return res.status(403).json({
        mensagem: "Você não tem permissão para editar este pet"
      });
    }

    const petData = {
      ...req.body
    }

    if (req.file) {
      const resultadoUpload = await uploadImagem(
        req.file.buffer,
        req.file.originalname
      );

      petData.imagem = resultadoUpload.secure_url;
    }

    const petAtualizado = await Pet.findByIdAndUpdate(
      req.params.id,
      petData,
      { new: true }
    );

    res.json(petAtualizado);

  } catch (error) {
    next(error);
  }
};

const deletePet = async (req, res, next) => {
  try {
    const pet = await Pet.findById(req.params.id);

    if (!pet) {
      return res.status(404).json({
        mensagem: "Pet não encontrado"
      });
    }

    if (pet.usuario.toString() !== req.userId) {
      return res.status(403).json({
        mensagem: "Você não tem permissão para deletar este pet"
      });
    }

    await Pet.findByIdAndDelete(req.params.id);

    res.json({
      mensagem: "Pet deletado com sucesso",
      pet
    });

  } catch (error) {
    next(error);
  }
};

module.exports = {
    getPets,
    getPetById,
    createPet,
    updatePet,
    deletePet
};