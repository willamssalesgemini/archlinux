#!/bin/bash
#
# SCRIPT DE INSTALAÇÃO AUTOCONTIDO E PROFISSIONAL - ARCH LINUX + HYPRLAND
# Versão 15.0 (Final - Lógica de 'umount' aprimorada)
#

# --- [ 1. CONFIGURAÇÕES E MODO DE SEGURANÇA ] ---
set -eo pipefail

# --- [ 2. VARIÁVEIS GLOBAIS E CONSTANTES ] ---
TIMEZONE="America/Recife"
KEYMAP="br-abnt2"
LOCALE="pt_BR.UTF-8"

# --- [ 3. FUNÇÕES ] ---
function log_step {
    echo "....................................................."
    echo ">>> $1"
    echo "....................................................."
}

# --- [ 4. EXECUÇÃO PRINCIPAL ] ---

# ETAPA 1: PREPARAÇÃO DO AMBIENTE LIVE
clear
echo "====================================================="
echo "  Instalador Definitivo Arch Linux + Hyprland"
echo "====================================================="
log_step "(Etapa 1/7) Preparando o ambiente de instalação"
echo "--> Verificando conexão com a internet..."
if ! ping -c 1 archlinux.org &> /dev/null; then echo "ERRO: Sem internet."; exit 1; fi
echo "✔ Internet OK."
echo "--> Ativando o repositório Multilib e sincronizando..."
sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
pacman -Sy --noconfirm archlinux-keyring
echo "--> Instalando dependências para o script..."
pacman -S --noconfirm --needed dialog reflector
echo "--> Otimizando servidores de download (mirrors)..."
reflector --country Brazil --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist

# ETAPA 2: DETECÇÃO DO MODO DE BOOT
log_step "(Etapa 2/7) Detectando modo de boot"
BOOT_MODE="BIOS"
if [ -d "/sys/firmware/efi/efivars" ]; then BOOT_MODE="UEFI"; fi
echo "✔ Modo de Boot detectado: $BOOT_MODE"

# ETAPA 3: COLETA DE DADOS - PARTE 1 (USUÁRIO E SENHAS)
log_step "(Etapa 3/7) Coletando informações do usuário"
HOSTNAME=$(dialog --clear --inputbox "Digite um nome para o seu computador (hostname):" 10 40 2>&1 >/dev/tty)
[[ -z "$HOSTNAME" ]] && { echo "Hostname não pode ser vazio."; exit 1; }
USUARIO=$(dialog --clear --inputbox "Digite um nome para seu usuário (sem maiúsculas):" 10 40 2>&1 >/dev/tty)
[[ -z "$USUARIO" ]] && { echo "Usuário não pode ser vazio."; exit 1; }
while true; do
    SENHA_USUARIO=$(dialog --clear --passwordbox "Digite a senha para o usuário $USUARIO:" 10 40 2>&1 >/dev/tty)
    [[ -z "$SENHA_USUARIO" ]] && { dialog --msgbox "A senha não pode ser vazia." 10 40; clear; continue; }
    SENHA_USUARIO_CONFIRM=$(dialog --clear --passwordbox "Confirme a senha para o usuário $USUARIO:" 10 40 2>&1 >/dev/tty)
    if [[ "$SENHA_USUARIO" == "$SENHA_USUARIO_CONFIRM" ]]; then break; else dialog --msgbox "As senhas não coincidem." 10 40; clear; fi
done
while true; do
    SENHA_ROOT=$(dialog --clear --passwordbox "Digite a senha para o Administrador (root):" 10 40 2>&1 >/dev/tty)
    [[ -z "$SENHA_ROOT" ]] && { dialog --msgbox "A senha não pode ser vazia." 10 40; clear; continue; }
    SENHA_ROOT_CONFIRM=$(dialog --clear --passwordbox "Confirme a senha para o Administrador (root):" 10 40 2>&1 >/dev/tty)
    if [[ "$SENHA_ROOT" == "$SENHA_ROOT_CONFIRM" ]]; then break; else dialog --msgbox "As senhas não coincidem." 10 40; clear; fi
done
if dialog --clear --yesno "Deseja conceder privilégios de administrador (sudo) ao usuário $USUARIO?" 10 60; then USER_IS_SUDOER="yes"; else USER_IS_SUDOER="no"; fi
clear

# ETAPA 4: COLETA DE DADOS - PARTE 2 (HARDWARE)
log_step "(Etapa 4/7) Coletando informações de Hardware"
dialog_options=()
while IFS= read -r line; do
    DEVICE=$(echo "$line" | awk '{print $1}'); SIZE=$(echo "$line" | awk '{print $2}'); MODEL=$(echo "$line" | awk '{$1=$2=""; print $0}' | sed 's/^[ \t]*//')
    DISK_TYPE="SATA/USB"; if [[ "$DEVICE" == /dev/nvme* ]]; then DISK_TYPE="NVMe SSD"; fi
    status="off"; [[ ${#dialog_options[@]} -eq 0 ]] && status="on"
    dialog_options+=("$DEVICE" "[$DISK_TYPE] ${SIZE} - ${MODEL}" "$status")
done < <(lsblk -d -n -o NAME,SIZE,MODEL --exclude 7,11)
SSD=$(dialog --clear --backtitle "Seleção de Disco de Destino" --radiolist "Use ESPAÇO para selecionar o disco onde o Arch Linux será instalado.\n\nATENÇÃO: TODOS os dados do disco selecionado serão APAGADOS." 20 78 15 "${dialog_options[@]}" 2>&1 >/dev/tty)
[[ -z "$SSD" ]] && { echo "Seleção de disco cancelada."; exit 1; }
clear
GPU_VENDOR=$(lspci | grep -E "VGA|3D" | head -n 1 | awk '{print $5}')
GPU_CHOICE=$(dialog --clear --title "Seleção de Driver (Detectado: $GPU_VENDOR)" --menu "Escolha:" 15 50 3 "Intel" "" "AMD" "" "NVIDIA" "" 2>&1 >/dev/tty)
[[ -z "$GPU_CHOICE" ]] && { echo "Seleção de GPU cancelada."; exit 1; }
clear
if dialog --clear --yesno "Deseja criar uma partição /home separada?" 10 40; then
    SEPARATE_HOME="s"; ROOT_SIZE=$(dialog --clear --inputbox "Qual o tamanho da partição Raiz (/) ? (ex: 100G)" 10 40 "100G" 2>&1 >/dev/tty)
    [[ -z "$ROOT_SIZE" ]] && { echo "Tamanho da partição raiz cancelado."; exit 1; }
else SEPARATE_HOME="n"; fi
clear

# ETAPA 5: COLETA DE DADOS - PARTE 3 (PACOTES EXTRAS)
log_step "(Etapa 5/7) Selecionando pacotes adicionais"
DEV_PACKAGES_OPTIONS=("git" "Git - Sistema de controle de versão" "on" "neovim" "Editor de texto moderno no terminal" "on" "code" "VS Code - Editor de código da Microsoft" "on" "docker" "Plataforma de contêineres" "off" "docker-compose" "Ferramenta para orquestrar contêineres" "off" "python" "Linguagem de programação Python" "on" "nodejs" "Ambiente de execução JavaScript" "off" "npm" "Gerenciador de pacotes para Node.js" "off")
MEDIA_PACKAGES_OPTIONS=("vlc" "Reprodutor de mídia universal" "on" "gimp" "Editor de imagens estilo Photoshop" "off" "inkscape" "Editor de gráficos vetoriais" "off" "obs-studio" "Software para gravação e streaming" "off" "kdenlive" "Editor de vídeo não-linear" "off" "krita" "Software de pintura digital e animação" "off" "blender" "Criação 3D, animação e efeitos visuais" "off")
DEV_PACKAGES=$(dialog --clear --backtitle "Seleção de Software" --checklist "Ferramentas de Desenvolvimento" 20 70 15 "${DEV_PACKAGES_OPTIONS[@]}" 2>&1 >/dev/tty); clear
MEDIA_PACKAGES=$(dialog --clear --backtitle "Seleção de Software" --checklist "Softwares de Mídia" 20 70 15 "${MEDIA_PACKAGES_OPTIONS[@]}" 2>&1 >/dev/tty); clear
EXTRA_PACKAGES_STRING="$(echo $DEV_PACKAGES $MEDIA_PACKAGES | tr -d '"')"
dialog --clear --backtitle "Confirmação Final" --yesno "A instalação começará em '$SSD' para '$USUARIO'.\nTODOS os dados serão apagados.\n\nDeseja continuar?" 10 60
response=$?; if [ $response -ne 0 ]; then echo "Instalação cancelada."; exit; fi
clear

# ETAPA 6: INSTALAÇÃO NO DISCO E CONFIGURAÇÃO
log_step "(Etapa 6/7) Executando a instalação no disco"
echo "--> Particionando o disco $SSD (Modo $BOOT_MODE)..."
sgdisk -Z "$SSD"
if [ "$BOOT_MODE" == "UEFI" ]; then
    if [[ "$SEPARATE_HOME" == "s" ]]; then sgdisk -n=1:0:+512M -t=1:ef00 -n=2:0:+17G -t=2:8200 -n=3:0:+$ROOT_SIZE -t=3:8300 -n=4:0:0 -t=4:8300 "$SSD"; else sgdisk -n=1:0:+512M -t=1:ef00 -n=2:0:+17G -t=2:8200 -n=3:0:0 -t=3:8300 "$SSD"; fi
    EFI_PART="${SSD}1"; SWAP_PART="${SSD}2"; ROOT_PART="${SSD}3"; [[ "$SEPARATE_HOME" == "s" ]] && HOME_PART="${SSD}4"
    echo "--> Formatando e montando partições..."; mkfs.fat -F 32 "$EFI_PART"; mkswap "$SWAP_PART"; mkfs.ext4 "$ROOT_PART"
    mount "$ROOT_PART" /mnt; swapon "$SWAP_PART"; mkdir -p /mnt/boot; mount "$EFI_PART" /mnt/boot
else
    if [[ "$SEPARATE_HOME" == "s" ]]; then sgdisk -n=1:0:+1M -t=1:ef02 -n=2:0:+17G -t=2:8200 -n=3:0:+$ROOT_SIZE -t=3:8300 -n=4:0:0 -t=4:8300 "$SSD"; else sgdisk -n=1:0:+1M -t=1:ef02 -n=2:0:+17G -t=2:8200 -n=3:0:0 -t=3:8300 "$SSD"; fi
    SWAP_PART="${SSD}2"; ROOT_PART="${SSD}3"; [[ "$SEPARATE_HOME" == "s" ]] && HOME_PART="${SSD}4"
    echo "--> Formatando e montando partições..."; mkswap "$SWAP_PART"; mkfs.ext4 "$ROOT_PART"
    mount "$ROOT_PART" /mnt; swapon "$SWAP_PART"
fi
if [[ "$SEPARATE_HOME" == "s" ]]; then mkfs.ext4 "$HOME_PART"; mkdir -p /mnt/home; mount "$HOME_PART" /mnt/home; fi
GFX_PACKAGES=(); if [ "$GPU_CHOICE" == "NVIDIA" ]; then GFX_PACKAGES=("nvidia-dkms" "nvidia-utils" "lib32-nvidia-utils"); else GFX_PACKAGES=("mesa" "lib32-mesa"); fi
BASE_PACKAGES=("base" "linux" "linux-firmware" "intel-ucode" "micro" "networkmanager" "iwd" "sudo" "udisks2"); if [ "$BOOT_MODE" == "UEFI" ]; then BASE_PACKAGES+=("efibootmgr"); fi
DESKTOP_PACKAGES=("hyprland" "xorg-xwayland" "kitty" "rofi" "dunst" "sddm" "sddm-kcm" "polkit-kde-agent" "firefox" "dolphin" "bluez" "bluez-utils" "pipewire" "wireplumber" "pipewire-pulse" "tlp" "brightnessctl" "waybar" "papirus-icon-theme" "gtk3" "qt6ct" "qgnomeplatform-qt6" "archlinux-wallpaper" "hyprpaper" "grim" "slurp" "cliphist" "wl-clipboard" "gammastep")
EXTRA_PACKAGES=($EXTRA_PACKAGES_STRING)
echo "--> Instalando TODOS os pacotes com pacstrap..."; pacstrap -K /mnt "${BASE_PACKAGES[@]}" "${GFX_PACKAGES[@]}" "${DESKTOP_PACKAGES[@]}" "${EXTRA_PACKAGES[@]}"; genfstab -U /mnt >> /mnt/etc/fstab
GRUB_INSTALL_COMMAND=""; if [ "$BOOT_MODE" == "UEFI" ]; then GRUB_INSTALL_COMMAND="grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=ARCH"; else GRUB_INSTALL_COMMAND="grub-install --target=i386-pc $SSD"; fi
arch-chroot /mnt /bin/bash -c "set -e; ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime; hwclock --systohc; sed -i 's/^#$LOCALE/$LOCALE/' /etc/locale.gen; locale-gen; echo 'LANG=$LOCALE' > /etc/locale.conf; echo 'KEYMAP=$KEYMAP' > /etc/vconsole.conf; echo '$HOSTNAME' > /etc/hostname; systemctl enable NetworkManager iwd sddm bluetooth tlp; echo 'root:$SENHA_ROOT' | chpasswd; useradd -m -G wheel -s /bin/bash $USUARIO; echo '$USUARIO:$SENHA_USUARIO' | chpasswd; if [ '$USER_IS_SUDOER' == 'yes' ]; then sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers; fi; pacman -S --noconfirm grub; $GRUB_INSTALL_COMMAND; grub-mkconfig -o /boot/grub/grub.cfg;"

# ETAPA 7: FINALIZAÇÃO
log_step "(Etapa 7/7) Finalizando a instalação"
if mountpoint -q /mnt; then
    echo "--> Desmontando todas as partições..."
    umount -R /mnt
    echo "✔ Partições desmontadas."
else
    echo "--> Partições já estavam desmontadas, prosseguindo."
fi
clear
echo "====================================================="
echo "          Instalação Concluída!"
echo "====================================================="
echo "O sistema está pronto. Pressione [Enter] para reiniciar."
read
reboot
