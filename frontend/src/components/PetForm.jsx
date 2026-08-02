import { useState, useRef } from "react";

function PetForm(props) {
  return (
    <>
      <h2>{props.nome}</h2>
      <h3>{props.especie}</h3>

      <form className="pet-form" onSubmit={props.onSubmit}>
        <div>
          <label>Nome</label>
          <input
            type="text"
            value={props.nome}
            onChange={(event) => props.setNome(event.target.value)}
            required
          />
        </div>

        <div>
          <label>Espécie</label>
          <input
            type="text"
            value={props.especie}
            onChange={(event) => props.setEspecie(event.target.value)}
            required
          />
        </div>

        <div>
          <label>Idade</label>

          <input
            type="number"
            min="0"
            value={props.idade}
            onChange={(event) => props.setIdade(event.target.value)}
          />
        </div>

        <div>
          <label>Raça</label>

          <input
            type="text"
            value={props.raca}
            onChange={(event) => props.setRaca(event.target.value)}
          />
        </div>

        <div>
          <label>Imagem (URL)</label>

          <input
            ref={props.inputImagemRef}
            type="file"
            name="imagem" 
            onChange={(event) => {
              props.setImagem(event.target.files[0])
            }}
          />
        </div>
        
        <div>
          <label>Status</label>

          <select
            value={props.status}
            onChange={(event) => props.setStatus(event.target.value)}
          >
            <option value="Disponível">Disponível</option>
            <option value="Adotado">Adotado</option>
          </select>
        </div>
      
        <div>
          <button
            type="submit"
            disabled={props.salvando}
          >
            {props.salvando
              ? "Enviando imagem..."
              : props.petEditando
                ? "Salvar alterações"
                : "Cadastrar"}
          </button>

            {props.petEditando && (
          <button
            type="button"
            onClick={props.onCancelar}
          >
            Cancelar
          </button>
            )}
        </div>
      </form>
    </>
  )
}

export default PetForm