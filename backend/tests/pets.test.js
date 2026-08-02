const request = require("supertest");
const app = require("../src/app");

const User = require("../src/models/User");
const Pet = require("../src/models/Pet");

describe("Testes de pets", () => {
  it("deve listar todos os pets", async () => {
    const user = await User.create({
      nome: "Usuário Pet",
      email: "pet@email.com",
      senha: "123456"
    });

    await Pet.create({
      nome: "Rex",
      especie: "Cachorro",
      idade: 3,
      raca: "Labrador",
      usuario: user._id
    });

    const response = await request(app)
      .get("/pets");

    expect(response.statusCode).toBe(200);

    expect(response.body).toHaveLength(1);

    expect(response.body[0].nome).toBe("Rex");
    expect(response.body[0].especie).toBe("Cachorro");
  });
});

it("deve criar um pet para um usuário autenticado", async () => {
  await request(app)
    .post("/auth/register")
    .send({
      nome: "Usuário Criador",
      email: "criador@email.com",
      senha: "123456"
    });

    const user = await User.findOne({
    email: "criador@email.com"
    });

  const loginResponse = await request(app)
    .post("/auth/login")
    .send({
      email: "criador@email.com",
      senha: "123456"
    });

  const token = loginResponse.body.token;

  const response = await request(app)
    .post("/pets")
    .set("Authorization", `Bearer ${token}`)
    .field("nome", "Mel")
    .field("especie", "Gato")
    .field("idade", "2")
    .field("raca", "Siamês");

  expect(response.statusCode).toBe(201);

  expect(response.body.nome).toBe("Mel");
  expect(response.body.especie).toBe("Gato");

  expect(response.body.usuario.toString())
    .toBe(user._id.toString());
});

it("não deve permitir que outro usuário edite um pet", async () => {
  // Criar usuário dono
  await request(app)
    .post("/auth/register")
    .send({
      nome: "Dono do Pet",
      email: "dono@email.com",
      senha: "123456"
    });

  const loginDono = await request(app)
    .post("/auth/login")
    .send({
      email: "dono@email.com",
      senha: "123456"
    });

  const tokenDono = loginDono.body.token;

  // Criar pet pelo dono
  const petResponse = await request(app)
    .post("/pets")
    .set("Authorization", `Bearer ${tokenDono}`)
    .field("nome", "Rex")
    .field("especie", "Cachorro")
    .field("idade", "5");

  const petId = petResponse.body._id;


  // Criar segundo usuário
  await request(app)
    .post("/auth/register")
    .send({
      nome: "Outro Usuário",
      email: "outro@email.com",
      senha: "123456"
    });

  const loginOutro = await request(app)
    .post("/auth/login")
    .send({
      email: "outro@email.com",
      senha: "123456"
    });

  const tokenOutro = loginOutro.body.token;


  // Tentar editar o pet de outra pessoa
  const response = await request(app)
    .put(`/pets/${petId}`)
    .set("Authorization", `Bearer ${tokenOutro}`)
    .field("nome", "Novo Nome");


  expect(response.statusCode).toBe(403);

  expect(response.body.mensagem).toBe(
    "Você não tem permissão para editar este pet"
  );
});

it("não deve permitir que outro usuário delete um pet", async () => {
  await request(app)
    .post("/auth/register")
    .send({
      nome: "Dono Delete",
      email: "donodelete@email.com",
      senha: "123456"
    });

  const loginDono = await request(app)
    .post("/auth/login")
    .send({
      email: "donodelete@email.com",
      senha: "123456"
    });

  const tokenDono = loginDono.body.token;

  const petResponse = await request(app)
    .post("/pets")
    .set("Authorization", `Bearer ${tokenDono}`)
    .field("nome", "Bolt")
    .field("especie", "Cachorro");

  const petId = petResponse.body._id;


  await request(app)
    .post("/auth/register")
    .send({
      nome: "Outro Delete",
      email: "outrodelete@email.com",
      senha: "123456"
    });

  const loginOutro = await request(app)
    .post("/auth/login")
    .send({
      email: "outrodelete@email.com",
      senha: "123456"
    });

  const tokenOutro = loginOutro.body.token;


  const response = await request(app)
    .delete(`/pets/${petId}`)
    .set("Authorization", `Bearer ${tokenOutro}`);


  expect(response.statusCode).toBe(403);

  expect(response.body.mensagem).toBe(
    "Você não tem permissão para deletar este pet"
  );
});

it("deve permitir que o dono edite seu próprio pet", async () => {
  await request(app)
    .post("/auth/register")
    .send({
      nome: "Dono Edit",
      email: "donoedit@email.com",
      senha: "123456"
    });

  const login = await request(app)
    .post("/auth/login")
    .send({
      email: "donoedit@email.com",
      senha: "123456"
    });

  const token = login.body.token;

  const petResponse = await request(app)
    .post("/pets")
    .set("Authorization", `Bearer ${token}`)
    .field("nome", "Antes")
    .field("especie", "Gato");

  const petId = petResponse.body._id;

  const response = await request(app)
    .put(`/pets/${petId}`)
    .set("Authorization", `Bearer ${token}`)
    .field("nome", "Depois");

  expect(response.statusCode).toBe(200);

  expect(response.body.nome).toBe("Depois");
});

it("deve permitir que o dono delete seu próprio pet", async () => {
  await request(app)
    .post("/auth/register")
    .send({
      nome: "Dono Delete",
      email: "delete@email.com",
      senha: "123456"
    });

  const login = await request(app)
    .post("/auth/login")
    .send({
      email: "delete@email.com",
      senha: "123456"
    });

  const token = login.body.token;

  const petResponse = await request(app)
    .post("/pets")
    .set("Authorization", `Bearer ${token}`)
    .field("nome", "Remover")
    .field("especie", "Cachorro");

  const petId = petResponse.body._id;

  const response = await request(app)
    .delete(`/pets/${petId}`)
    .set("Authorization", `Bearer ${token}`);

  expect(response.statusCode).toBe(200);

  expect(response.body.mensagem).toBe(
    "Pet deletado com sucesso"
  );

  const petExistente = await Pet.findById(petId);

  expect(petExistente).toBeNull();
});

it("deve buscar um pet pelo ID", async () => {
  const user = await User.create({
    nome: "Usuário Busca",
    email: "busca@email.com",
    senha: "123456"
  });

  const pet = await Pet.create({
    nome: "Thor",
    especie: "Cachorro",
    usuario: user._id
  });

  const response = await request(app)
    .get(`/pets/${pet._id}`);

  expect(response.statusCode).toBe(200);

  expect(response.body.nome).toBe("Thor");
  expect(response.body.especie).toBe("Cachorro");
});

it("deve retornar erro ao buscar pet inexistente", async () => {
  const idInexistente = "507f1f77bcf86cd799439011";

  const response = await request(app)
    .get(`/pets/${idInexistente}`);

  expect(response.statusCode).toBe(404);

  expect(response.body.mensagem).toBe(
    "Pet não encontrado"
  );
});

it("deve retornar erro para ID de pet inválido", async () => {
  const response = await request(app)
    .get("/pets/id-invalido");

  expect(response.statusCode).toBe(400);

  expect(response.body.mensagem).toBe(
    "ID inválido"
  );
});

it("deve retornar erro ao criar pet sem campo obrigatório", async () => {
  await request(app)
    .post("/auth/register")
    .send({
      nome: "Usuário Validação",
      email: "validacao@email.com",
      senha: "123456"
    });

  const login = await request(app)
    .post("/auth/login")
    .send({
      email: "validacao@email.com",
      senha: "123456"
    });

  const token = login.body.token;

  const response = await request(app)
    .post("/pets")
    .set("Authorization", `Bearer ${token}`)
    .field("especie", "Cachorro");

  expect(response.statusCode).toBe(400);

  expect(response.body.mensagem).toBe(
    "Erro de validação"
  );
});

it("não deve permitir acesso com token inválido", async () => {
  const response = await request(app)
    .post("/pets")
    .set("Authorization", "Bearer token-invalido")
    .field("nome", "Rex")
    .field("especie", "Cachorro");

  expect(response.statusCode).toBe(401);

  expect(response.body.mensagem).toBe(
    "Token inválido"
  );
});

it("não deve permitir criar pet sem autenticação", async () => {
  const response = await request(app)
    .post("/pets")
    .field("nome", "Rex")
    .field("especie", "Cachorro");

  expect(response.statusCode).toBe(401);

  expect(response.body.mensagem).toBe(
    "Token não fornecido"
  );
});