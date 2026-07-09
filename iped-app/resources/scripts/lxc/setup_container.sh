#!/bin/bash
# ==============================================================================
# Script de Inicialização para Contêineres LXC - IPED Digital Forensic Tool
# ==============================================================================
# Este script configura o ambiente Linux, instala todas as dependências,
# compila as ferramentas nativas necessárias e configura os perfis do IPED.
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

log_info "Iniciando a configuração do contêiner LXC..."

# ==============================================================================
# FASE 1: Ferramentas do Sistema e Repositórios APT
# ==============================================================================
log_info "Instalando ferramentas essenciais do sistema..."
apt-get update && apt-get install -y \
    curl \
    wget \
    gnupg \
    apt-utils \
    apt-transport-https \
    software-properties-common \
    jq \
    ca-certificates

log_info "Atualizando certificados locais de segurança..."
update-ca-certificates

log_info "Configurando repositórios de terceiros..."
# Python 3.9
add-apt-repository ppa:deadsnakes/ppa -y

# BellSoft Java JDK
mkdir -p /etc/apt/keyrings
wget -q -O - https://download.bell-sw.com/pki/GPG-KEY-bellsoft | gpg --dearmor -o /etc/apt/keyrings/bellsoft.gpg
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/bellsoft.gpg] https://apt.bell-sw.com/ stable main" > /etc/apt/sources.list.d/bellsoft.list

# ==============================================================================
# FASE 2: Instalação de Dependências APT
# ==============================================================================
log_info "Instalando dependências do sistema via APT..."
apt-get update && apt-get install -y \
    git build-essential autoconf automake autopoint libtool pkg-config yasm gettext flex byacc ant ant-optional cmake zlib1g-dev libncurses5-dev libcurl4-openssl-dev libexpat1-dev libreadline-dev wget unzip patch \
    libaa1-dev libasound2-dev libcaca-dev libcdparanoia-dev libdca-dev libdirectfb-dev libenca-dev libfontconfig1-dev libfreetype6-dev libfribidi-dev libgif-dev libgl1-mesa-dev libjack-jackd2-dev libopenal1 libpulse-dev libsdl1.2-dev libvdpau-dev libxinerama-dev libxv-dev libxvmc-dev libxxf86dga-dev libxxf86vm-dev librtmp-dev libsctp-dev libass-dev libfaac-dev libsmbclient-dev libtheora-dev libogg-dev libxvidcore-dev libspeex-dev libvpx-dev libdv4-dev \
    libopencore-amrnb-dev libopencore-amrwb-dev libmp3lame-dev libtwolame-dev libmad0-dev libgsm1-dev libbs2b-dev liblzo2-dev ladspa-sdk libfaad-dev libmpg123-dev libopus-dev libbluray-dev libaacs-dev libjpeg-dev libtiff-dev libpng-dev libwmf-dev libheif-dev libwebp-dev librsvg2-dev libopenexr-dev libatomic1 vim less libparse-win32registry-perl \
    tesseract-ocr tesseract-ocr-osd tesseract-ocr-por tesseract-ocr-eng tesseract-ocr-deu tesseract-ocr-frk tesseract-ocr-ita graphviz bellsoft-java11-full mplayer rifiuti2 python3.9 python3.9-distutils python3-pip python3.9-dev sudo libssl-dev sed

log_info "Configurando alternativas do sistema (rifiuti2 & python)..."
update-alternatives --install /usr/bin/rifiuti rifiuti /usr/bin/rifiuti2 1
update-alternatives --install /usr/bin/python python /usr/bin/python3.9 1
update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.9 1

# ==============================================================================
# FASE 3: Instalação de Dependências Python
# ==============================================================================
log_info "Atualizando pip, setuptools e wheel..."
python -m pip install pip --upgrade
python -m pip install setuptools wheel --upgrade

log_info "Instalando dlib..."
python -m pip install dlib==19.24.2 --no-build-isolation

log_info "Instalando pacotes Python adicionais (Jep, Numpy, face_recognition, OpenCV)..."
python -m pip install jep==4.2.0 numpy==1.26.4 face_recognition opencv-python==4.11.0.86

# ==============================================================================
# FASE 4: Compilação e Instalação de Ferramentas Nativas
# ==============================================================================
# Criação do diretório temporário para compilação
export PKGTMPDIR=/tmp/pkgs
mkdir -p "$PKGTMPDIR" && cd "$PKGTMPDIR"

# Função auxiliar para clonar e compilar as bibliotecas libyal de forma limpa
build_libyal() {
    local lib="$1"
    log_info "Compilando biblioteca libyal: ${lib}..."
    git clone "https://github.com/libyal/${lib}"
    (
        cd "$lib"
        ./synclibs.sh
        ./autogen.sh
        ./configure --prefix=/usr
        make -j$(nproc)
        make install
    )
}

# Itera sobre todas as bibliotecas forenses do libyal necessárias
for lib in libbfio libvslvm libvmdk libvhdi libewf libagdb libevtx libevt libscca libesedb libpff libmsiecf; do
    build_libyal "$lib"
done

# Compilação da AFFLIBv3 (Suporte ao formato forense AFF)
log_info "Compilando AFFLIBv3..."
git clone -b v3.7.20 https://github.com/sshock/AFFLIBv3
(
    cd AFFLIBv3
    ./bootstrap.sh
    ./configure --prefix=/usr
    make -j$(nproc)
    make install
)

# Compilação do Sleuthkit com patch de compatibilidade com a libewf
log_info "Compilando Sleuthkit..."
git clone -b 4.12.0_iped_patch https://github.com/sepinf-inc/sleuthkit
curl -L https://raw.githubusercontent.com/iped-docker/iped/master/resources/ewf.cpp.patch --output ewf.cpp.patch
(
    cd sleuthkit
    patch tsk/img/ewf.cpp < ../ewf.cpp.patch
    ./bootstrap
    ./configure --prefix=/usr/ --enable-java
    make -j$(nproc)
    make install
)

# Compilação do ImageMagick para suporte avançado a processamento de imagens
log_info "Compilando ImageMagick..."
git clone --branch "7.1.1-21" https://github.com/ImageMagick/ImageMagick
(
    cd ImageMagick
    ./configure --prefix=/usr
    make -j$(nproc)
    make install
)

# ==============================================================================
# FASE 5: Instalação e Configuração do IPED
# ==============================================================================
# Configurações do repositório/release
export IPED_REPO_OWNER="${IPED_REPO_OWNER:-filipesimoes}"
export IPED_RELEASE_VERSION="${IPED_RELEASE_VERSION:-4.3.1}"
export IPED_RELEASE_FILE="${IPED_RELEASE_FILE:-iped-${IPED_RELEASE_VERSION}.tar.gz}"

log_info "Baixando release do IPED de ${IPED_REPO_OWNER}/${IPED_RELEASE_VERSION}..."
mkdir -p /opt/IPED/ && cd /opt/IPED/

curl -L "https://github.com/${IPED_REPO_OWNER}/IPED/releases/download/${IPED_RELEASE_VERSION}/${IPED_RELEASE_FILE}" --output "$PKGTMPDIR/iped_release"

log_info "Extraindo o pacote do IPED..."
if [[ "$IPED_RELEASE_FILE" == *.zip ]]; then
    unzip "$PKGTMPDIR/iped_release"
elif [[ "$IPED_RELEASE_FILE" == *.tar.gz ]]; then
    tar -zxvf "$PKGTMPDIR/iped_release"
else
    log_error "Erro: Formato de arquivo desconhecido para $IPED_RELEASE_FILE"
    exit 1
fi

# Cria link simbólico geral para a pasta da versão extraída
ls | grep "iped-" | xargs -i sh -c 'ln -s "{}" iped'
cd iped

# --- Configurações Básicas em LocalConfig.txt ---
log_info "Aplicando configurações locais no LocalConfig.txt..."
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

# --- Perfil: fastrobust ---
log_info "Configurando o perfil 'fastrobust'..."
cp -r profiles/forensic profiles/fastrobust
echo "parseUnknown = false" >> profiles/fastrobust/conf/ParsingTaskConfig.txt
echo "excludeKnown = true" >> profiles/fastrobust/conf/HashDBLookupConfig.txt
echo "robustImageReading = true" >> profiles/fastrobust/conf/FileSystemConfig.txt
echo "enableExternalParsing = true" >> profiles/fastrobust/conf/ParsingTaskConfig.txt
sed -i -e "s/enableCarving = true/enableCarving = false/" profiles/fastrobust/IPEDConfig.txt

# --- Perfil: pedorobust ---
log_info "Configurando o perfil 'pedorobust'..."
cp -r profiles/pedo profiles/pedorobust
echo "excludeKnown = true" >> profiles/pedorobust/conf/HashDBLookupConfig.txt
echo "robustImageReading = true" >> profiles/pedorobust/conf/FileSystemConfig.txt
echo "enableExternalParsing = true" >> profiles/pedorobust/conf/ParsingTaskConfig.txt

# --- Perfil: ocr ---
log_info "Configurando o perfil 'ocr'..."
cp -r profiles/pedo profiles/ocr
echo "excludeKnown = true" >> profiles/ocr/conf/HashDBLookupConfig.txt
echo "enableOCR = true" >> profiles/ocr/conf/OCRConfig.txt

# Substituição do JAR JEP (Java Embedded Python) para evitar falhas JNI
log_info "Instalando jar correto do JEP..."
cp /usr/local/lib/python3.9/dist-packages/jep/jep-4.2.0.jar lib/jep-4.0.3.jar

# ==============================================================================
# FASE 6: Limpeza e Finalização
# ==============================================================================
log_info "Limpando arquivos temporários e cache do APT..."
rm -rfv "${PKGTMPDIR:?}"/* && apt-get clean && rm -rfv /var/lib/apt/lists/*

log_info "Instalação concluída com sucesso."