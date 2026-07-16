#!/bin/bash
# ==============================================================================
# Script de Atualização para Contêineres LXC - IPED Digital Forensic Tool
# ==============================================================================
# Este script atualiza o IPED para uma nova versão dentro do contêiner LXC,
# mantendo backup das configurações anteriores e reaplicando as customizações.
# ==============================================================================

set -e

# --- Configurações de Ambiente (Não Interativo) ---
export DEBIAN_FRONTEND=noninteractive
export TZ="Brazil/East"
export LANG="C.UTF-8"
export LC_ALL="C.UTF-8"
export JAVA_HOME="/usr/lib/jvm/bellsoft-java11-full-amd64/"
export LD_LIBRARY_PATH="/usr/lib/:/usr/local/lib/python3.9/dist-packages/jep/"

# --- Funções Auxiliares de Log ---
log_info() {
    echo -e "\e[32m[INFO]\e[0m $1"
}

log_warn() {
    echo -e "\e[33m[WARN]\e[0m $1"
}

log_error() {
    echo -e "\e[31m[ERROR]\e[0m $1" >&2
}

# --- Configurações do repositório/release ---
export IPED_REPO_OWNER="${IPED_REPO_OWNER:-filipesimoes}"

# Determina a versão a ser instalada
if [ -z "$1" ]; then
    log_info "Nenhuma versão especificada. Buscando a última versão do repositório ${IPED_REPO_OWNER}/IPED no GitHub..."
    
    # Tenta buscar a última tag/release do GitHub usando curl e jq
    LATEST_RELEASE=$(curl -s "https://api.github.com/repos/${IPED_REPO_OWNER}/IPED/releases/latest" | jq -r '.tag_name' 2>/dev/null | sed 's/^v//')
    
    if [ -n "$LATEST_RELEASE" ] && [ "$LATEST_RELEASE" != "null" ]; then
        export IPED_RELEASE_VERSION="$LATEST_RELEASE"
        log_info "Última versão identificada: ${IPED_RELEASE_VERSION}"
    else
        log_warn "Não foi possível obter a última versão automaticamente via API do GitHub."
        log_error "Uso: $0 <versão_do_iped> (exemplo: $0 4.3.1)"
        exit 1
    fi
else
    export IPED_RELEASE_VERSION="$1"
fi

export IPED_RELEASE_FILE="${IPED_RELEASE_FILE:-iped-${IPED_RELEASE_VERSION}.tar.gz}"

log_info "Iniciando processo de atualização para o IPED versão ${IPED_RELEASE_VERSION}..."

# Diretório temporário para download
PKGTMPDIR=$(mktemp -d -t iped-update-XXXXXX)
log_info "Diretório temporário criado em: ${PKGTMPDIR}"

# Garantir limpeza do diretório temporário ao finalizar o script
cleanup() {
    log_info "Limpando arquivos temporários..."
    rm -rf "$PKGTMPDIR"
}
trap cleanup EXIT

# ==============================================================================
# FASE 1: Backup da Instalação Existente
# ==============================================================================
IPED_BASE_DIR="/opt/IPED"
ACTIVE_SYMLINK="${IPED_BASE_DIR}/iped"

if [ -L "$ACTIVE_SYMLINK" ] || [ -d "$ACTIVE_SYMLINK" ]; then
    BACKUP_DIR="${IPED_BASE_DIR}/backup_$(date +%Y%m%d_%H%M%S)"
    log_info "Instalação anterior detectada. Criando backup das configurações em ${BACKUP_DIR}..."
    mkdir -p "$BACKUP_DIR"
    
    # Resolve o caminho real do link simbólico
    REAL_PATH=$(readlink -f "$ACTIVE_SYMLINK" || true)
    if [ -n "$REAL_PATH" ]; then
        log_info "A instalação ativa atual está em: ${REAL_PATH}"
    fi

    # Backup do LocalConfig.txt
    if [ -f "${ACTIVE_SYMLINK}/LocalConfig.txt" ]; then
        cp "${ACTIVE_SYMLINK}/LocalConfig.txt" "$BACKUP_DIR/"
        log_info "-> LocalConfig.txt copiado para o backup."
    fi
    
    # Backup das configurações do gráfico
    if [ -f "${ACTIVE_SYMLINK}/conf/GraphConfig.json" ]; then
        mkdir -p "${BACKUP_DIR}/conf"
        cp "${ACTIVE_SYMLINK}/conf/GraphConfig.json" "${BACKUP_DIR}/conf/"
        log_info "-> GraphConfig.json copiado para o backup."
    fi

    # Backup dos perfis customizados
    if [ -d "${ACTIVE_SYMLINK}/profiles" ]; then
        cp -r "${ACTIVE_SYMLINK}/profiles" "${BACKUP_DIR}/"
        log_info "-> Diretório profiles/ copiado para o backup."
    fi
    
    log_info "Backup das configurações anteriores concluído com sucesso."
else
    log_warn "Nenhuma instalação anterior ativa do IPED foi localizada em ${ACTIVE_SYMLINK}."
fi

# ==============================================================================
# FASE 2: Download e Extração da Nova Versão
# ==============================================================================
mkdir -p "$IPED_BASE_DIR"
cd "$IPED_BASE_DIR"

log_info "Baixando release do IPED de ${IPED_REPO_OWNER}/${IPED_RELEASE_VERSION}..."
DOWNLOAD_URL="https://github.com/${IPED_REPO_OWNER}/IPED/releases/download/${IPED_RELEASE_VERSION}/${IPED_RELEASE_FILE}"

if ! curl -L -f "$DOWNLOAD_URL" --output "$PKGTMPDIR/iped_release"; then
    log_error "Erro ao baixar o IPED da URL: ${DOWNLOAD_URL}"
    log_error "Verifique se a versão ${IPED_RELEASE_VERSION} realmente existe no repositório."
    exit 1
fi

TARGET_VERSION_DIR="${IPED_BASE_DIR}/iped-${IPED_RELEASE_VERSION}"
if [ -d "$TARGET_VERSION_DIR" ]; then
    log_warn "O diretório de destino ${TARGET_VERSION_DIR} já existe. Removendo para instalação limpa..."
    rm -rf "$TARGET_VERSION_DIR"
fi

log_info "Extraindo o pacote do IPED..."
if [[ "$IPED_RELEASE_FILE" == *.zip ]]; then
    unzip "$PKGTMPDIR/iped_release"
elif [[ "$IPED_RELEASE_FILE" == *.tar.gz ]]; then
    tar -zxvf "$PKGTMPDIR/iped_release"
else
    log_error "Erro: Formato de arquivo desconhecido para $IPED_RELEASE_FILE"
    exit 1
fi

# ==============================================================================
# FASE 3: Configuração e Atualização do Link Simbólico
# ==============================================================================
log_info "Atualizando o link simbólico para a nova versão..."
rm -f "$ACTIVE_SYMLINK"
ln -sf "iped-${IPED_RELEASE_VERSION}" "$ACTIVE_SYMLINK"

cd "$ACTIVE_SYMLINK"

# --- Reaplicação das Configurações Padrão de setup_container.sh ---
log_info "Aplicando configurações locais padrão no LocalConfig.txt..."
sed -i -e "s/locale =.*/locale = pt-BR/" LocalConfig.txt
sed -i -e "s/indexTemp =.*/indexTemp = \/mnt\/ipedtmp/" LocalConfig.txt
sed -i -e "s/indexTempOnSSD =.*/indexTempOnSSD = true/" LocalConfig.txt
sed -i -e "s/outputOnSSD =.*/outputOnSSD = false/" LocalConfig.txt
sed -i -e "s/numThreads =.*/numThreads = 8/" LocalConfig.txt
sed -i -e "s/#hashesDB =.*/hashesDB = \/mnt\/hashesdb\/iped-hashes.db/" LocalConfig.txt
sed -i -e "s/#tskJarPath =.*/tskJarPath = \/usr\/share\/java\/sleuthkit-4.12.0.jar/" LocalConfig.txt
sed -i -e "s/mplayerPath =.*/mplayerPath = \/usr\/bin\/mplayer/" LocalConfig.txt

# --- Configurações Regionais do Gráfico ---
sed -i -e "s/\"phone-region\":.*/\"phone-region\":\"BR\",/" conf/GraphConfig.json

# --- Configuração dos Perfis Customizados (fastrobust, pedorobust, ocr) ---
log_info "Recriando perfis customizados baseados nos novos templates..."

# fastrobust
cp -r profiles/forensic profiles/fastrobust
echo "parseUnknown = false" >> profiles/fastrobust/conf/ParsingTaskConfig.txt
echo "excludeKnown = true" >> profiles/fastrobust/conf/HashDBLookupConfig.txt
echo "robustImageReading = true" >> profiles/fastrobust/conf/FileSystemConfig.txt
echo "enableExternalParsing = true" >> profiles/fastrobust/conf/ParsingTaskConfig.txt
sed -i -e "s/enableCarving = true/enableCarving = false/" profiles/fastrobust/IPEDConfig.txt

# pedorobust
cp -r profiles/pedo profiles/pedorobust
echo "excludeKnown = true" >> profiles/pedorobust/conf/HashDBLookupConfig.txt
echo "robustImageReading = true" >> profiles/pedorobust/conf/FileSystemConfig.txt
echo "enableExternalParsing = true" >> profiles/pedorobust/conf/ParsingTaskConfig.txt

# ocr
cp -r profiles/pedo profiles/ocr
echo "excludeKnown = true" >> profiles/ocr/conf/HashDBLookupConfig.txt
echo "enableOCR = true" >> profiles/ocr/conf/OCRConfig.txt

# --- Restauração Opcional de Perfis Customizados Não-Padrão ou Arquivos Modificados ---
if [ -d "$BACKUP_DIR" ]; then
    log_info "Você pode encontrar suas configurações anteriores copiadas em: ${BACKUP_DIR}"
    log_info "Caso queira restaurar as configurações originais exatas, use:"
    log_info "  cp ${BACKUP_DIR}/LocalConfig.txt ${ACTIVE_SYMLINK}/"
fi

# ==============================================================================
# FASE 4: Configuração do JEP (Java Embedded Python)
# ==============================================================================
log_info "Instalando jar correto do JEP para evitar falhas JNI..."
JEP_JAR_IN_LIB=$(find lib/ -name "jep-*.jar" | head -n 1)
if [ -n "$JEP_JAR_IN_LIB" ]; then
    log_info "Substituindo JEP jar localizado em: ${JEP_JAR_IN_LIB}"
    cp /usr/local/lib/python3.9/dist-packages/jep/jep-4.2.0.jar "$JEP_JAR_IN_LIB"
else
    log_warn "Nenhum jar do JEP encontrado em lib/. Copiando como lib/jep-4.0.3.jar por compatibilidade..."
    cp /usr/local/lib/python3.9/dist-packages/jep/jep-4.2.0.jar lib/jep-4.0.3.jar
fi

log_info "Atualização concluída com sucesso para a versão ${IPED_RELEASE_VERSION}!"
