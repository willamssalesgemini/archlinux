#!/bin-bash
#
# SCRIPT DE INSTALAÇÃO PROFISSIONAL - ARCH LINUX + HYPRLAND
# Versão 15.0 (Retornando ao systemd-boot para maior robustez)
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
log_step "(Etapa 1/6) Preparando o ambiente de instalação"
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

# ETAPA 2: COLETA DE DADOS DO USUÁRIO
log_step "(Etapa 2/6) Coletando informações do usuário"
HOSTNAME=$(dialog --clear --inputbox "Nome do computador (hostname):" 10 40 2>&1 >/dev/tty)
[[ -z "$HOSTNAME" ]] && { echo "Hostname não pode ser vazio."; exit 1; }
USUARIO=$(dialog --clear --inputbox "Nome de usuário (sem maiúsculas):" 10 40 2>&1 >/dev/tty)
[[ -z "$USUARIO" ]] && { echo "Usuário não pode ser vazio."; exit 1; }
while true; do
    SENHA_USUARIO=$(dialog --clear --passwordbox "Senha para o usuário $USUARIO:" 10 40 2>&1 >/dev/tty)
    [[ -z "$SENHA_USUARIO" ]] && { dialog --msgbox "A senha não pode ser vazia." 10 40; clear; continue; }
    SENHA_USUARIO_CONFIRM=$(dialog --clear --passwordbox "Confirme a senha:" 10 40 2>&1 >/dev/tty)
    if [[ "$SENHA_USUARIO" == "$SENHA_USUARIO_CONFIRM" ]]; then break; else dialog --msgbox "As senhas não coincidem." 10 40; clear; fi
done
while true; do
    SENHA_ROOT=$(dialog --clear --passwordbox "Senha para o Administrador (root):" 10 40 2>&1 >/dev/tty)
    [[ -z "$SENHA_ROOT" ]] && { dialog --msgbox "A senha não pode ser vazia." 10 40; clear; continue; }
    SENHA_ROOT_CONFIRM=$(dialog --clear --passwordbox "Confirme a senha:" 10 40 2>&1 >/dev/tty)
    if [[ "$SENHA_ROOT" == "$SENHA_ROOT_CONFIRM" ]]; then break; else dialog --msgbox "As senhas não coincidem." 10 40; clear; fi
done
if dialog --clear --yesno "Conceder privilégios de administrador (sudo) ao usuário $USUARIO?" 10 60; then USER_IS_SUDOER="yes"; else USER_IS_SUDOER="no"; fi
clear

# ETAPA 3: COLETA DE DADOS DE HARDWARE E SOFTWARE
log_step "(Etapa 3/6) Coletando informações de Hardware e Software"
dialog_options=()
while IFS= read -r line; do
    DEVICE=$(echo "$line" | awk '{print $1}')
    SIZE=$(echo "$line" | awk '{print $2}')
    MODEL=$(echo "$line" | awk '{$1=$2=""; print $0}' | sed 's/^[ \t]*//')
    DISK_TYPE="SATA/USB"; if [[ "$DEVICE" == nvme* ]]; then DISK_TYPE="NVMe SSD"; fi
    status="off"; [[ ${#dialog_options[@]} -eq 0 ]] && status="on"
    dialog_options+=("/dev/$DEVICE" "[$DISK_TYPE] ${SIZE} - ${MODEL}" "$status")
done < <(lsblk -d -n -o NAME,SIZE,MODEL --exclude 7,11)
SSD=$(dialog --clear --backtitle "Seleção de Disco" --radiolist "Use ESPAÇO para selecionar o disco de instalação.\n\nATENÇÃO: TODOS os dados serão APAGADOS." 20 78 15 "${dialog_options[@]}" 2>&1 >/dev/tty)
[[ -z "$SSD" ]] && { echo "Seleção de disco cancelada."; exit 1; }
clear

GPU_VENDOR=$(lspci | grep -E "VGA|3D" | head -n 1 | awk '{print $5}')
GPU_CHOICE=$(dialog --clear --title "Seleção de Driver (Detectado: $GPU_VENDOR)" --menu "Escolha:" 15 50 3 "Intel" "" "AMD" "" "NVIDIA" "" 2>&1 >/dev/tty)
[[ -z "$GPU_CHOICE" ]] && { echo "Seleção de GPU cancelada."; exit 1; }
clear

if dialog --clear --yesno "Deseja criar uma partição /home separada?" 10 40; then
    SEPARATE_HOME="s"
    ROOT_SIZE=$(dialog --clear --inputbox "Qual o tamanho da partição Raiz (/) ? (ex: 100G)" 10 40 "100G" 2>&1 >/dev/tty)
    [[ -z "$ROOT_SIZE" ]] && { echo "Tamanho da partição raiz cancelado."; exit 1; }
else
    SEPARATE_HOME="n"
fi
clear

DEV_PACKAGES_OPTIONS=("git" "Controle de versão" "on" "neovim" "Editor de texto" "on" "code" "VS Code" "on" "docker" "Plataforma de contêineres" "off")
MEDIA_PACKAGES_OPTIONS=("vlc" "Reprodutor de mídia" "on" "gimp" "Editor de imagens" "off" "inkscape" "Gráficos vetoriais" "off" "obs-studio" "Gravação e streaming" "off")
DEV_PACKAGES=$(dialog --clear --backtitle "Software" --checklist "Ferramentas de Desenvolvimento" 20 70 15 "${DEV_PACKAGES_OPTIONS[@]}" 2>&1 >/dev/tty)
MEDIA_PACKAGES=$(dialog --clear --backtitle "Software" --checklist "Softwares de Mídia" 20 70 15 "${MEDIA_PACKAGES_OPTIONS[@]}" 2>&1 >/dev/tty)
EXTRA_PACKAGES_STRING="$(echo $DEV_PACKAGES $MEDIA_PACKAGES | tr -d '"')"
clear

dialog --clear --backtitle "Confirmação Final" --yesno "A instalação começará em '$SSD' para '$USUARIO'.\n\nConfirma?" 10 60
response=$?
if [ $response -ne 0 ]; then echo "Instalação cancelada."; exit; fi
clear

# ETAPA 4: INSTALAÇÃO NO DISCO
log_step "(Etapa 4/6) Executando a instalação no disco"
echo "--> Particionando o disco $SSD..."
sgdisk -Z "$SSD"
if [[ "$SEPARATE_HOME" == "s" ]]; then sgdisk -n=1:0:+512M -t=1:ef00 -n=2:0:+17G -t=2:8200 -n=3:0:+$ROOT_SIZE -t=3:8300 -n=4:0:0 -t=4:8300 "$SSD"; else sgdisk -n=1:0:+512M -t=1:ef00 -n=2:0:+17G -t=2:8200 -n=3:0:0 -t=3:8300 "$SSD"; fi
EFI_PART="${SSD}1"; SWAP_PART="${SSD}2"; ROOT_PART="${SSD}3"; [[ "$SEPARATE_HOME" == "s" ]] && HOME_PART="${SSD}4"

echo "--> Formatando e montando partições..."
mkfs.fat -F 32 "$EFI_PART"; mkswap "$SWAP_PART"; mkfs.ext4 "$ROOT_PART"
mount "$ROOT_PART" /mnt; swapon "$SWAP_PART"; mkdir -p /mnt/boot; mount "$EFI_PART" /mnt/boot
if [[ "$SEPARATE_HOME" == "s" ]]; then mkfs.ext4 "$HOME_PART"; mkdir -p /mnt/home; mount "$HOME_PART" /mnt/home; fi

GFX_PACKAGES=(); if [ "$GPU_CHOICE" == "NVIDIA" ]; then GFX_PACKAGES=("nvidia-dkms" "lib32-nvidia-utils"); else GFX_PACKAGES=("mesa" "lib32-mesa"); fi
BASE_PACKAGES=("base" "linux" "linux-firmware" "intel-ucode" "micro" "networkmanager" "iwd" "sudo" "udisks2" "efibootmgr")
DESKTOP_PACKAGES=("hyprland" "xorg-xwayland" "kitty" "rofi" "dunst" "sddm" "sddm-kcm" "polkit-kde-agent" "firefox" "dolphin" "bluez" "bluez-utils" "pipewire" "wireplumber" "pipewire-pulse" "tlp" "brightnessctl" "waybar" "papirus-icon-theme" "gtk3" "qt6ct" "qgnomeplatform-qt6" "archlinux-wallpaper" "hyprpaper" "grim" "slurp" "cliphist" "wl-clipboard" "gammastep")
EXTRA_PACKAGES=($EXTRA_PACKAGES_STRING)

echo "--> Instalando TODOS os pacotes com pacstrap..."; pacstrap -K /mnt "${BASE_PACKAGES[@]}" "${GFX_PACKAGES[@]}" "${DESKTOP_PACKAGES[@]}" "${EXTRA_PACKAGES[@]}"; genfstab -U /mnt >> /mnt/etc/fstab

# ETAPA 5: CONFIGURAÇÃO VIA CHROOT
log_step "(Etapa 5/6) Configurando o novo sistema"
# --- [ MUDANÇA: LÓGICA DO SYSTEMD-BOOT RESTAURADA ] ---
cat << EOF > /mnt/chroot-script.sh
#!/bin/bash
set -e
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime; hwclock --systohc
sed -i 's/^#$LOCALE/$LOCALE/' /etc/locale.gen; locale-gen
echo 'LANG=$LOCALE' > /etc/locale.conf; echo 'KEYMAP=$KEYMAP' > /etc/vconsole.conf
echo '$HOSTNAME' > /etc/hostname
systemctl enable NetworkManager iwd sddm bluetooth tlp udisks2
echo 'root:$SENHA_ROOT' | chpasswd
if [[ "$USER_IS_SUDOER" == "yes" ]]; then useradd -m -G wheel -s /bin/bash $USUARIO; else useradd -m -s /bin/bash $USUARIO; fi
echo '$USUARIO:$SENHA_USUARIO' | chpasswd
if [ '$USER_IS_SUDOER' == 'yes' ]; then sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers; fi

MKINIT_MODULES=""; if [ "$GPU_CHOICE" == "NVIDIA" ]; then MKINIT_MODULES="nvidia nvidia_modeset nvidia_uvm nvidia_drm"; fi
sed -i "s/^MODULES=(.*)/MODULES=(\$MKINIT_MODULES)/" /etc/mkinitcpio.conf
sed -i 's/^HOOKS=(.*)/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block filesystems resume fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

echo ":: [Chroot] Configurando systemd-boot..."
bootctl --path=/boot install
ROOT_UUID=\$(blkid -s UUID -o value $ROOT_PART)
SWAP_UUID=\$(blkid -s UUID -o value $SWAP_PART)
BOOT_OPTIONS=""; if [ "$GPU_CHOICE" == "NVIDIA" ]; then BOOT_OPTIONS="nvidia_drm.modeset=1"; fi
echo "default arch-*" > /boot/loader/loader.conf
echo "timeout 3" >> /boot/loader/loader.conf
echo "title Arch Linux" > /boot/loader/entries/arch.conf
echo "linux /vmlinuz-linux" >> /boot/loader/entries/arch.conf
echo "initrd /intel-ucode.img" >> /boot/loader/entries/arch.conf
echo "initrd /initramfs-linux.img" >> /boot/loader/entries/arch.conf
echo "options root=UUID=\$ROOT_UUID rw resume=UUID=\$SWAP_UUID \$BOOT_OPTIONS" >> /boot/loader/entries/arch.conf
EOF
arch-chroot /mnt /bin/bash /chroot-script.sh

# ETAPA 6: FINALIZAÇÃO
log_step "(Etapa 6/6) Finalizando a instalação"
umount -R /mnt
clear
echo "====================================================="
echo "          Instalação Concluída!"
echo "====================================================="
echo "Pressione [Enter] para reiniciar o sistema."
read
reboot
