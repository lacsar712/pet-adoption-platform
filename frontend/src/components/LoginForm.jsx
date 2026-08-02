import { useState } from "react";
import { login } from "../services/authService";

function LoginForm({ onLogin }) {
  console.log("Renderizou LoginForm");
  const [email, setEmail] = useState("");
  const [senha, setSenha] = useState("");
  const [mensagem, setMensagem] = useState("");
  const [carregandoLogin, setCarregandoLogin] = useState(false);

  const handleSubmit = (event) => {
    event.preventDefault();
    setMensagem("");

    setCarregandoLogin(true);

    login({ email, senha })
      .then((response) => response.json())
      .then((data) => {
        if (data.token) {
          localStorage.setItem(
            "usuario",
            JSON.stringify(data.usuario)
          );
          onLogin(data.token, data.usuario, "Login realizado com sucesso!");
        } else {
          setMensagem(data.mensagem || "Erro ao fazer login.");
        }

        setCarregandoLogin(false);
      })
      .catch((error) => {
        console.error("Erro ao fazer login:", error);
        setMensagem("Erro ao conectar com o servidor.");
        setCarregandoLogin(false);
      });
  };

  return (
    <form className="login-form" onSubmit={handleSubmit}>
      <h2>Login</h2>

      {mensagem && <p className="login-message">{mensagem}</p>}

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
        autoComplete="current-password"
        onChange={(event) => setSenha(event.target.value)}
      />

      <button className="login-button" type="submit" disabled={carregandoLogin}>
        {carregandoLogin ? "Entrando..." : "Entrar"}
      </button>
    </form>
  );
}

export default LoginForm;