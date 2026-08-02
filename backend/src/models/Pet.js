const mongoose = require("mongoose");

const petSchema = new mongoose.Schema({
    nome: {
        type: String,
        required: true
    },
    especie: {
        type: String,
        required: true
    },
    status: {
        type: String,
        default: "Disponível"
    },
    idade: {
        type: Number
    },
    raca: {
        type: String
    },
    imagem: {
    type: String
    },
    usuario: {
    type: mongoose.Schema.Types.ObjectId,
    ref: "User",
    required: true
    }
}); 

const Pet = mongoose.model("Pet", petSchema);

module.exports = Pet;   

