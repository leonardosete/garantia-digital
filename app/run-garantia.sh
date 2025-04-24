#!/bin/bash
## Remove env anterior - garante que eu possa rodar em qualquer diretório
#rm -rf venv

# Caminho para o diretório do ambiente virtual
VENV_DIR="venv"

# Verificar se o diretório do venv existe, caso contrário, criar o ambiente virtual e instalar as dependências
if [ ! -d "$VENV_DIR" ]; then
    echo "Criando ambiente virtual em $VENV_DIR..."
    python3 -m venv "$VENV_DIR"
    source "$VENV_DIR/bin/activate"
    echo "Instalando dependências..."
    pip install --upgrade pip
    pip install reportlab requests
else
    echo "Ativando ambiente virtual existente..."
    source "$VENV_DIR/bin/activate"
    
    # Verificar se as dependências necessárias estão instaladas
    pip show reportlab requests &> /dev/null
    if [ $? -ne 0 ]; then
        echo "Instalando dependências faltantes..."
        pip install reportlab requests
    fi
fi

# Função para executar o script Python usando o Google Sheets como fonte de dados
generate_garantia(){
    python3 create-garantia.py
}

# Executar a função desejada
generate_garantia

# Desativar o ambiente virtual (opcional)
# deactivate
