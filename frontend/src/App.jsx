import { useState, useEffect, useRef } from 'react'

import {
  getPets,
  createPet,
  deletePet,
  updatePet
} from "./services/petService"
import './App.css'
import PetForm from "./components/PetForm.jsx"
import PetCard from "./components/PetCard"
import LoginForm from "./components/LoginForm";
import { getMe } from "./services/authService";
import RegisterForm from "./components/RegisterForm";

function App() {
  const [pets, setPets] = useState([])
  const [nome, setNome] = useState("")
  const [especie, setEspecie] = useState("")
  const [idade, setIdade] = useState("")
  const [raca, setRaca] = useState("")
  const [imagem, setImagem] = useState("")
  const [status, setStatus] = useState("Disponível")
  const [busca, setBusca] = useState("")
  const [filtroStatus, setFiltroStatus] = useState("Todos")
  const [filtroEspecie, setFiltroEspecie] = useState("Todas")
  const [salvando, setSalvando] = useState(false)
  const [petEditando, setPetEditando] = useState(null)
  const [mensagem, setMensagem] = useState("")
  const [carregando, setCarregando] = useState(true)
  const [modoCadastro, setModoCadastro] = useState(false);
  const [usuario, setUsuario] = useState(
    JSON.parse(localStorage.getItem("usuario"))
  );
  const [token, setToken] = useState(
    localStorage.getItem("token")
  );
  const inputImagemRef = useRef(null);

  const buscarPets = () => {
    setCarregando(true)

    getPets()
      .then((response) => response.json())
      .then((data) => {
        if (Array.isArray(data)) {
          setPets(data)
        } else {
          console.error("Resposta inesperada ao buscar pets:", data)
          setPets([])
        }

        setCarregando(false)
      })
      .catch((error) => {
        console.error("Erro ao buscar pets:", error)
        setPets([])
        setCarregando(false)
      })
  }

  useEffect(() => {
    buscarPets()

    if (token) {
      getMe(token)
        .then((response) => {
          if (response.status === 401) {
            logout()
            return
          }

          return response.json()
        })
        .then((data) => {
          if (data) {
            setUsuario(data)
          }
        })
        .catch((error) => {
          console.error("Erro ao validar token:", error)
        })
    }
  }, [])

  const excluirPet = (id) => {
    const confirmarExclusao = window.confirm(
      "Tem certeza que deseja excluir este pet?"
    )

    if (!confirmarExclusao) {
      return
    }

    deletePet(id)
      .then((response) => {
        if (response.status === 401) {
          logout()
          setMensagem("Sessão expirada. Faça login novamente.")
          throw new Error("Token inválido ou expirado")
        }

        return response.json()
      })
      .then(() => {
        buscarPets()
        setMensagem("Pet excluído com sucesso!")

        setTimeout(() => {
          setMensagem("")
        }, 3000)
      })
      .catch((error) => {
        console.error("Erro ao excluir pet:", error)

        if (error.message !== "Token inválido ou expirado") {
          setMensagem("Erro ao excluir pet.")
        }

        setTimeout(() => {
          setMensagem("")
        }, 3000)
      })
  }

  const salvarPet = (event) => {
    event.preventDefault()

    if (!nome.trim()) {
      alert("O nome do pet é obrigatório.")
      return
    }

    if (!especie.trim()) {
      alert("A espécie do pet é obrigatória.")
      return
    }

    setSalvando(true)
    
    const novoPet = new FormData()

    novoPet.append("nome", nome)
    novoPet.append("especie", especie)
    novoPet.append("idade", idade)
    novoPet.append("raca", raca)
    novoPet.append("status", status)
    if (imagem) {
      novoPet.append("imagem", imagem)
    }

    if (petEditando) {
      updatePet(petEditando._id, novoPet)
        .then((response) => {
          if (response.status === 401) {
            logout()
            setMensagem("Sessão expirada. Faça login novamente.")
            throw new Error("Token inválido ou expirado")
          }

          return response.json()
        })
        .then(() => {
          buscarPets()
          setMensagem("Pet atualizado com sucesso!")

          setTimeout(() => {
            setMensagem("")
          }, 3000)

          setNome("")
          setEspecie("")
          setIdade("")
          setRaca("")
          setImagem("")
          setStatus("Disponível")
          setPetEditando(null)
          setSalvando(false)
        })
        .catch((error) => {
          console.error("Erro ao editar pet:", error)

          if (error.message !== "Token inválido ou expirado") {
            setMensagem("Erro ao atualizar pet.")
          }

          setTimeout(() => {
            setMensagem("")
          }, 3000)

          setSalvando(false)
        })
    } else {
      createPet(novoPet)
        .then((response) => {
          if (response.status === 401) {
            logout()
            setMensagem("Sessão expirada. Faça login novamente.")
            throw new Error("Token inválido ou expirado")
          }

          return response.json()
        })
        .then(() => {
          buscarPets()
          setMensagem("Pet cadastrado com sucesso!")

          setTimeout(() => {
            setMensagem("")
          }, 3000)

          setNome("")
          setEspecie("")
          setIdade("")
          setRaca("")
          setImagem("")

          if (inputImagemRef.current) {
            inputImagemRef.current.value = ""
          }
          
          setStatus("Disponível")
          setSalvando(false)
        })
        .catch((error) => {
          console.error("Erro ao cadastrar pet:", error)

          if (error.message !== "Token inválido ou expirado") {
            setMensagem("Erro ao cadastrar pet.")
          }

          setTimeout(() => {
            setMensagem("")
          }, 3000)

          setSalvando(false)
        })
    }
  }

  const petsFiltrados = pets.filter((pet) => {
    const nomeCorresponde = pet.nome
      .toLowerCase()
      .includes(busca.toLowerCase())

    const statusCorresponde =
      filtroStatus === "Todos" ||
      pet.status === filtroStatus

    const especieCorresponde =
      filtroEspecie === "Todas" ||
      pet.especie === filtroEspecie

    return (
      nomeCorresponde &&
      statusCorresponde &&
      especieCorresponde
)
  })

  const cancelarEdicao = () => {
    setNome("")
    setEspecie("")
    setIdade("")
    setRaca("")
    setImagem("")
    setStatus("Disponível")
    setPetEditando(null)
  }

  const logout = () => {
    localStorage.removeItem("token");
    localStorage.removeItem("usuario");
    setToken(null);
    setUsuario(null);
  };

  const handleLogin = (novoToken, novoUsuario, mensagemLogin) => {
    localStorage.setItem("token", novoToken);
    localStorage.setItem("usuario", JSON.stringify(novoUsuario));

    setToken(novoToken);
    setUsuario(novoUsuario);
    setMensagem(mensagemLogin);

    setTimeout(() => {
      setMensagem("");
    }, 3000);
  };

  return (
    <div className="container">
      <h1>Pet Adoption Platform</h1>

      {token && (
        <div className="user-area">
          <span className="user-name">
            Olá, {usuario?.nome}
          </span>

          <button className="logout-button" onClick={logout}>
            Sair
          </button>
        </div>
      )}

      {mensagem && <p className="message">{mensagem}</p>}

      {!token && (
        <>
          {modoCadastro ? (
            <RegisterForm
              onRegisterSuccess={() => setModoCadastro(false)}
            />
          ) : (
            <LoginForm onLogin={handleLogin} />
          )}

          <button
            className="login-button"
            onClick={() => setModoCadastro(!modoCadastro)}
          >
            {modoCadastro
              ? "Já tenho conta"
              : "Criar uma conta"}
          </button>
        </>
      )}

      {token && (
        <PetForm 
          nome={nome} 
          especie={especie}
          idade={idade}
          raca={raca}
          imagem={imagem}
          status={status}                
          setNome={setNome}
          setEspecie={setEspecie}  
          setIdade={setIdade}
          setRaca={setRaca}
          setImagem={setImagem}
          setStatus={setStatus}        
          onSubmit={salvarPet}
          petEditando={petEditando}
          onCancelar={cancelarEdicao}
          salvando={salvando}
          inputImagemRef={inputImagemRef}
        />
      )}

    <div className="filters">
      <input
        type="text"
        placeholder="Buscar pet pelo nome..."
        value={busca}
        onChange={(event) => setBusca(event.target.value)}
      />

      <select
        value={filtroStatus}
        onChange={(event) => setFiltroStatus(event.target.value)}
      >
        <option value="Todos">Todos</option>
        <option value="Disponível">Disponível</option>
        <option value="Adotado">Adotado</option>
      </select>

      <select
        value={filtroEspecie}
        onChange={(event) => setFiltroEspecie(event.target.value)}
      >
        <option value="Todas">Todas</option>
        <option value="Cachorro">Cachorro</option>
        <option value="Gato">Gato</option>
      </select>

      <button
        onClick={() => {
          setBusca("")
          setFiltroStatus("Todos")
          setFiltroEspecie("Todas")
        }}
      >
        Limpar filtros
      </button>
    </div>
    
      <p>
        Mostrando {petsFiltrados.length}{" "}
        {petsFiltrados.length === 1 ? "pet" : "pets"}
      </p>  

      <div className="pets-grid">
      {carregando ? (
        <p className="no-results">Carregando pets...</p>
      ) : petsFiltrados.length > 0 ? (
        petsFiltrados.map((pet) => (
          <PetCard
            key={pet._id}
            nome={pet.nome}
            especie={pet.especie}
            idade={pet.idade}
            raca={pet.raca}
            imagem={pet.imagem}
            status={pet.status}
            autenticado={!!token}  
            onEditar={() => {
              setPetEditando(pet)
              setNome(pet.nome)
              setEspecie(pet.especie)
              setIdade(pet.idade)
              setRaca(pet.raca)
              setImagem(pet.imagem)
              setStatus(pet.status)
            }}
            onExcluir={() => excluirPet(pet._id)}
          />
        ))
      ) : (
        <p className="no-results">Nenhum pet encontrado.</p>
      )}
      </div>
    </div>
  )
}

export default App