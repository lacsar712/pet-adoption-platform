const errorMiddleware = (error, req, res, _next) => {
    if (error.name === "ValidationError") {
        return res.status(400).json({
            mensagem: "Erro de validação",
            erro: error.message
        });
    }

    if (error.name === "CastError") {
        return res.status(400).json({
            mensagem: "ID inválido"
        });
    }

    res.status(500).json({
        mensagem: "Erro interno do servidor",
        erro: error.message
    });
};

module.exports = errorMiddleware;