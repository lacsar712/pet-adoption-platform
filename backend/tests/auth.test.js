const request = require("supertest");
const app = require("../src/app");

describe("Testes de autenticação", () => {
  it("deve cadastrar um novo usuário", async () => {
    const response = await request(app)
      .post("/auth/register")
      .send({
        nome: "Usuário Teste",
        email: "teste@email.com",
        senha: "123456"
      });

    expect(response.statusCode).toBe(201);

    expect(response.body.nome).toBe("Usuário Teste");
    expect(response.body.email).toBe("teste@email.com");

    expect(response.body.senha).toBeUndefined();
  });
});

it("deve realizar login de um usuário", async () => {
  await request(app)
    .post("/auth/register")
    .send({
      nome: "Usuário Login",
      email: "login@email.com",
      senha: "123456"
    });

  const response = await request(app)
    .post("/auth/login")
    .send({
      email: "login@email.com",
      senha: "123456"
    });

  expect(response.statusCode).toBe(200);

  expect(response.body.mensagem).toBe(
    "Login realizado com sucesso"
  );

  expect(response.body.token).toBeDefined();

  expect(response.body.usuario.email).toBe(
    "login@email.com"
  );
});

it("não deve permitir cadastro com email já existente", async () => {
  await request(app)
    .post("/auth/register")
    .send({
      nome: "Usuário Teste",
      email: "duplicado@email.com",
      senha: "123456"
    });

  const response = await request(app)
    .post("/auth/register")
    .send({
      nome: "Outro Usuário",
      email: "duplicado@email.com",
      senha: "654321"
    });

  expect(response.statusCode).toBe(400);

  expect(response.body.mensagem).toBe(
    "Usuário já cadastrado"
  );
});

it("não deve permitir login com senha incorreta", async () => {
  await request(app)
    .post("/auth/register")
    .send({
      nome: "Usuário Senha",
      email: "senha@email.com",
      senha: "123456"
    });

  const response = await request(app)
    .post("/auth/login")
    .send({
      email: "senha@email.com",
      senha: "senhaerrada"
    });

  expect(response.statusCode).toBe(401);

  expect(response.body.mensagem).toBe(
    "E-mail ou senha inválidos"
  );

  expect(response.body.token).toBeUndefined();
});

it("deve retornar dados do usuário autenticado", async () => {
  await request(app)
    .post("/auth/register")
    .send({
      nome: "Usuário Auth",
      email: "auth@email.com",
      senha: "123456"
    });

  const loginResponse = await request(app)
    .post("/auth/login")
    .send({
      email: "auth@email.com",
      senha: "123456"
    });

  const token = loginResponse.body.token;

  const response = await request(app)
    .get("/auth/me")
    .set("Authorization", `Bearer ${token}`);

  expect(response.statusCode).toBe(200);

  expect(response.body.nome).toBe("Usuário Auth");
  expect(response.body.email).toBe("auth@email.com");

  expect(response.body.senha).toBeUndefined();
});

it("não deve acessar /auth/me sem token", async () => {
  const response = await request(app)
    .get("/auth/me");

  expect(response.statusCode).toBe(401);

  expect(response.body.mensagem).toBe(
    "Token não fornecido"
  );
});