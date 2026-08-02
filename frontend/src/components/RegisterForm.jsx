import { useState } from "react";
import { register } from "../services/authService";

function RegisterForm({ onRegisterSuccess }) {
  const [nome, setNome] = useState("");
  const [email, setEmail] = useState("");
  const [senha, setSenha] = useState("");
  const [mensagem, setMensagem] = useState("");
  const [carregandoCadastro, setCarregandoCadastro] = useState(false);

  const handleSubmit = (event) => {
    event.preventDefault();

    setMensagem("");
    setCarregandoCadastro(true);

    register({ nome, email, senha })
      .then((response) => response.json())
      .then((data) => {
        if (data.id) {
          setMensagem("Cadastro realizado com sucesso!");
          setNome("");
          setEmail("");
          setSenha("");

          setTimeout(() => {
            onRegisterSuccess();
          }, 1500);
        } else {
          setMensagem(data.mensagem || "Erro ao cadastrar usuário.");
        }

        setCarregandoCadastro(false);
      })
      .catch((error) => {
        console.error("Erro ao cadastrar usuário:", error);
        setMensagem("Erro ao conectar com o servidor.");
        setCarregandoCadastro(false);
      });
  };

  return (
    <form className="login-form" onSubmit={handleSubmit}>
      <h2>Criar conta</h2>

      {mensagem && <p className="login-message">{mensagem}</p>}

      <input
        className="login-input"
        type="text"
        placeholder="Nome"
        value={nome}
        onChange={(event) => setNome(event.target.value)}
      />

      <input
        className="login-input"
        type="email"
        placeholder="E-mail"
        value={email}
        autoComplete="email"
        onChange={(event) => setEmail(event.target.value)}
      />

      <input
        className="login-input"
        type="password"
        placeholder="Senha"
        value={senha}
        autoComplete="new-password"
        onChange={(event) => setSenha(event.target.value)}
      />

      <button
        className="login-button"
        type="submit"
        disabled={carregandoCadastro}
      >
        {carregandoCadastro ? "Cadastrando..." : "Criar conta"}
      </button>
    </form>
  );
}

export default RegisterForm;