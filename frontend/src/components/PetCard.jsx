function PetCard(props) {
  return (
    <div className="pet-card">
      {props.imagem && (
        <img
          src={props.imagem}
          alt={props.nome}
          className="pet-image"
        />
      )}
      <h2>{props.nome}</h2>
      <p>Espécie: {props.especie}</p>
      <p>Idade: {props.idade}</p>
      <p>Raça: {props.raca}</p>
      <p>
        Status:{" "}
        <span className={`status-badge ${props.status === "Adotado" ? "adopted" : "available"}`}>
          {props.status}
        </span>
      </p>

      {props.autenticado && (
        <>
          <button onClick={props.onEditar}>
            Editar
          </button>

          <button onClick={props.onExcluir}>
            Excluir
          </button>
        </>
      )}
      
      </div>
  )
}

export default PetCard