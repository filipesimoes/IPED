#!/bin/bash
# Define o interpretador de comandos.

set -e

# Evita interações do usuário durante instalações via apt.
export DEBIAN_FRONTEND=noninteractive
# Define o fuso horário para o contêiner.
export TZ="Brazil/East"
# Configura a codificação de caracteres padrão para evitar erros de leitura.
export LANG="C.UTF-8"
export LC_ALL="C.UTF-8"
# Define o caminho do Java, requisito do IPED e do Sleuthkit.
export JAVA_HOME="/usr/lib/jvm/bellsoft-java11-full-amd64/"
# Adiciona o JEP (Java Embedded Python) e bibliotecas do sistema ao path para serem localizadas dinamicamente.
export LD_LIBRARY_PATH="/usr/lib/:/usr/local/lib/python3.9/dist-packages/jep/"

# MELHORIA: Instala ferramentas essenciais incluindo ca-certificates logo no início para evitar erros de handshake SSL
apt-get update && apt-get install -y curl wget gnupg apt-utils apt-transport-https software-properties-common jq ca-certificates
# Atualiza a lista de certificados locais.
update-ca-certificates

# Adiciona o repositório deadsnakes para ter acesso ao Python 3.9.
add-apt-repository ppa:deadsnakes/ppa -y

# MELHORIA: Cria o diretório de chaves e assina o repositório BellSoft seguindo as diretrizes modernas de segurança do APT
mkdir -p /etc/apt/keyrings
wget -q -O - https://download.bell-sw.com/pki/GPG-KEY-bellsoft | gpg --dearmor -o /etc/apt/keyrings/bellsoft.gpg
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/bellsoft.gpg] https://apt.bell-sw.com/ stable main" > /etc/apt/sources.list.d/bellsoft.list

# Instala todas as dependências do sistema: compiladores, bibliotecas de mídia, forenses e de visão computacional.
apt-get update && apt-get install -y \
    git build-essential autoconf automake autopoint libtool pkg-config yasm gettext flex byacc ant ant-optional cmake zlib1g-dev libncurses5-dev libcurl4-openssl-dev libexpat1-dev libreadline-dev wget unzip patch \
    libaa1-dev libasound2-dev libcaca-dev libcdparanoia-dev libdca-dev libdirectfb-dev libenca-dev libfontconfig1-dev libfreetype6-dev libfribidi-dev libgif-dev libgl1-mesa-dev libjack-jackd2-dev libopenal1 libpulse-dev libsdl1.2-dev libvdpau-dev libxinerama-dev libxv-dev libxvmc-dev libxxf86dga-dev libxxf86vm-dev librtmp-dev libsctp-dev libass-dev libfaac-dev libsmbclient-dev libtheora-dev libogg-dev libxvidcore-dev libspeex-dev libvpx-dev libdv4-dev \
    libopencore-amrnb-dev libopencore-amrwb-dev libmp3lame-dev libtwolame-dev libmad0-dev libgsm1-dev libbs2b-dev liblzo2-dev ladspa-sdk libfaad-dev libmpg123-dev libopus-dev libbluray-dev libaacs-dev libjpeg-dev libtiff-dev libpng-dev libwmf-dev libheif-dev libwebp-dev librsvg2-dev libopenexr-dev libatomic1 vim less libparse-win32registry-perl \
    tesseract-ocr tesseract-ocr-osd tesseract-ocr-por tesseract-ocr-eng tesseract-ocr-deu tesseract-ocr-frk tesseract-ocr-ita graphviz bellsoft-java11-full mplayer rifiuti2 python3.9 python3.9-distutils python3-pip python3.9-dev sudo libssl-dev sed

# Define o rifiuti2 como padrão quando o comando 'rifiuti' for chamado.
update-alternatives --install /usr/bin/rifiuti rifiuti /usr/bin/rifiuti2 1
# Define o Python 3.9 como versão padrão no sistema.
update-alternatives --install /usr/bin/python python /usr/bin/python3.9 1
update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.9 1

# Atualiza o pip do Python.
python -m pip install pip --upgrade
python -m pip install setuptools wheel --upgrade
python -m pip install dlib==19.24.2 --no-build-isolation

# CORREÇÃO PRINCIPAL: Removido o pacote 'cmake' do pip. Isso força o instalador a usar o CMake 3.22 nativo
# do Ubuntu para compilar o dlib, evitando o conflito de políticas obsoletas trazido pelo CMake 4.x.
python -m pip install jep==4.2.0 numpy==1.26.4 face_recognition opencv-python==4.11.0.86

# Define variável para o diretório de compilação temporário.
export PKGTMPDIR=/tmp/pkgs
mkdir -p $PKGTMPDIR && cd $PKGTMPDIR

# Função em shell para padronizar o clone, sincronização e compilação das bibliotecas libyal.
build_libyal() {
    git clone https://github.com/libyal/$1 && cd $1 && ./synclibs.sh && ./autogen.sh && ./configure --prefix=/usr && make all install && cd ..
}

# Itera sobre lista de bibliotecas forenses do libyal chamando a função de compilação.
for lib in libbfio libvslvm libvmdk libvhdi libewf libagdb libevtx libevt libscca libesedb libpff libmsiecf; do
    build_libyal $lib
done

# Clona e compila a AFFLIBv3, garantindo suporte ao formato de imagens forenses AFF.
git clone -b v3.7.20 https://github.com/sshock/AFFLIBv3 && cd AFFLIBv3 && ./bootstrap.sh && ./configure --prefix=/usr && make all install && cd ..

# Clona versão customizada do Sleuthkit e aplica um patch de compatibilidade com a libewf.
git clone -b 4.12.0_iped_patch https://github.com/sepinf-inc/sleuthkit && cd sleuthkit
curl https://raw.githubusercontent.com/iped-docker/iped/master/resources/ewf.cpp.patch --output ../ewf.cpp.patch
patch tsk/img/ewf.cpp < ../ewf.cpp.patch && ./bootstrap && ./configure --prefix=/usr/ --enable-java && make && make install && cd ..

# Clona e compila ImageMagick para extração/renderização avançada de imagens no IPED.
git clone --branch "7.1.1-21" https://github.com/ImageMagick/ImageMagick && cd ImageMagick && ./configure --prefix=/usr && make all install && cd ..

# Define o repositório, versão e arquivo do release do IPED que será baixada.
export IPED_REPO_OWNER="${IPED_REPO_OWNER:-filipesimoes}"
export IPED_RELEASE_VERSION="${IPED_RELEASE_VERSION:-4.3.1}"
export IPED_RELEASE_FILE="${IPED_RELEASE_FILE:-iped-${IPED_RELEASE_VERSION}.tar.gz}"

mkdir -p /opt/IPED/ && cd /opt/IPED/
# Baixa o release diretamente do repositório do GitHub.
curl -L "https://github.com/${IPED_REPO_OWNER}/IPED/releases/download/${IPED_RELEASE_VERSION}/${IPED_RELEASE_FILE}" --output "$PKGTMPDIR/iped_release"
# Descompacta o IPED conforme a extensão do arquivo.
if [[ "$IPED_RELEASE_FILE" == *.zip ]]; then
    unzip "$PKGTMPDIR/iped_release"
elif [[ "$IPED_RELEASE_FILE" == *.tar.gz ]]; then
    tar -zxvf "$PKGTMPDIR/iped_release"
else
    echo "Erro: Formato de arquivo desconhecido para $IPED_RELEASE_FILE"
    exit 1
fi
# Cria um link simbólico 'iped' apontando para a pasta da versão recém extraída.
ls | grep "iped-" | xargs -i sh -c 'ln -s "{}" iped'

# Acessa a pasta raiz de configuração da ferramenta.
cd iped
# Altera configurações padrão de processamento (idioma, diretório temp e uso de threads/SSD).
sed -i -e "s/locale =.*/locale = pt-BR/" LocalConfig.txt
sed -i -e "s/indexTemp =.*/indexTemp = \/mnt\/ipedtmp/" LocalConfig.txt
sed -i -e "s/indexTempOnSSD =.*/indexTempOnSSD = true/" LocalConfig.txt
sed -i -e "s/outputOnSSD =.*/outputOnSSD = false/" LocalConfig.txt
sed -i -e "s/numThreads =.*/numThreads = 8/" LocalConfig.txt
sed -i -e "s/#hashesDB =.*/hashesDB = \/mnt\/hashesdb\/iped-hashes.db/" LocalConfig.txt
# Define o caminho para a biblioteca compilada do Sleuthkit.
sed -i -e "s/#tskJarPath =.*/tskJarPath = \/usr\/share\/java\/sleuthkit-4.12.0.jar/" LocalConfig.txt
# Define o caminho do executável do MPlayer para gerar miniaturas de vídeo.
sed -i -e "s/mplayerPath =.*/mplayerPath = \/usr\/bin\/mplayer/" LocalConfig.txt
# Ajusta configurações de identificação de números de telefone para a região BR.
sed -i -e "s/\"phone-region\":.*/\"phone-region\":\"BR\",/" conf/GraphConfig.json

# Cria e customiza um perfil "fastrobust" com foco em velocidade e contorno de erros em disco.
cp -r profiles/forensic profiles/fastrobust
echo "parseUnknown = false" >> profiles/fastrobust/conf/ParsingTaskConfig.txt
echo "excludeKnown = true" >> profiles/fastrobust/conf/HashDBLookupConfig.txt
echo "robustImageReading = true" >> profiles/fastrobust/conf/FileSystemConfig.txt
echo "enableExternalParsing = true" >> profiles/fastrobust/conf/ParsingTaskConfig.txt
sed -i -e "s/enableCarving = true/enableCarving = false/" profiles/fastrobust/IPEDConfig.txt

# Cria e customiza um perfil "pedorobust" voltado a casos complexos de mídias danificadas.
cp -r profiles/pedo profiles/pedorobust
echo "excludeKnown = true" >> profiles/pedorobust/conf/HashDBLookupConfig.txt
echo "robustImageReading = true" >> profiles/pedorobust/conf/FileSystemConfig.txt
echo "enableExternalParsing = true" >> profiles/pedorobust/conf/ParsingTaskConfig.txt

# Cria perfil focado em OCR, ignorando imagens de sistema.
cp -r profiles/pedo profiles/ocr
echo "excludeKnown = true" >> profiles/ocr/conf/HashDBLookupConfig.txt
echo "enableOCR = true" >> profiles/ocr/conf/OCRConfig.txt

# Substitui o JAR do JEP do IPED pelo instalado via pip para evitar crash de JNI (biblioteca C/Java).
cp /usr/local/lib/python3.9/dist-packages/jep/jep-4.2.0.jar lib/jep-4.0.3.jar

# Remove pastas temporárias e cache do apt para reduzir o tamanho final da máquina.
rm -rfv $PKGTMPDIR/* && apt-get clean && rm -rfv /var/lib/apt/lists/*

echo "Instalação concluída com sucesso."