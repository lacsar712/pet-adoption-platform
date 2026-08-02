const request = require("supertest");
const express = require("express");

const app = require("../src/app");
const errorMiddleware = require("../src/middlewares/errorMiddleware");

const testApp = express();

testApp.get("/teste-erro", (req, res, next) => {
  next(new Error("Erro de teste"));
});

testApp.use(errorMiddleware);


describe("Teste da rota inicial", () => {
  it("deve retornar mensagem do servidor", async () => {
    const response = await request(app).get("/");

    expect(response.statusCode).toBe(200);
    expect(response.text).toBe("Servidor atualizado pelo nodemon");
  });
});


describe("Teste do error middleware", () => {
  it("deve retornar erro interno do servidor", async () => {
    const response = await request(testApp)
      .get("/teste-erro");

    expect(response.statusCode).toBe(500);

    expect(response.body.mensagem).toBe(
      "Erro interno do servidor"
    );
  });
});