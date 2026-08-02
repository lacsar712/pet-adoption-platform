const { 
    getPets,
    getPetById,
    createPet,
    updatePet,
    deletePet
} = require("../controllers/petController");

const upload = require("../config/multer")
const authMiddleware = require("../middlewares/authMiddleware");

const express = require("express");

const router = express.Router();

router.get("/pets", getPets);

router.get("/pets/:id", getPetById);

router.post(
  "/pets",
  authMiddleware,
  upload.single("imagem"),
  createPet
);

router.put("/pets/:id", authMiddleware, upload.single("imagem"), updatePet);

router.delete("/pets/:id", authMiddleware, deletePet);

module.exports = router;  

