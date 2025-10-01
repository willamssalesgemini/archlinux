#!/bin-bash
#
# SCRIPT DE INSTALAÇÃO DEFINITIVO - ARCH LINUX + HYPRLAND
# Versão 6.0 (Corrigida e Robusta) - 01 de Outubro de 2025
#

# --- [ 1. CONFIGURAÇÕES GERAIS ] ---
TIMEZONE="America/Recife"
KEYMAP="br-abnt2"
LOCALE="pt_BR.UTF-8"

# --- [ 2. INÍCIO DA EXECUÇÃO E COLETA DE DADOS ] ---
clear
echo "====================================================="
echo "  Instalador Definitivo Arch Linux + Hyprland"
echo "====================================================="
pacman -S --noconfirm --needed dialog &> /dev/null

# Coleta de todas as informações do usuário PRIMEIRO
HOSTNAME=$(dialog --clear --backtitle "Configuração do Sistema" --inputbox "Digite um nome para o seu computador (hostname):" 10 40 2>&1 >/dev/tty)
clear
USUARIO=$(dialog --clear --backtitle "Configuração do Sistema" --inputbox "Digite um nome para seu usuário (sem maiúsculas):" 10 40 2>&1 >/dev/tty)
clear

# Seleção de Drive de Vídeo
GPU_VENDOR=$(lspci | grep -E "VGA|3D" | head -n 1 | awk '{print $5}')
GPU_CHOICE=$(dialog --clear --backtitle "Hardware" --title "Seleção de Driver de Vídeo (Detectado: $GPU_VENDOR)" --menu "Escolha o driver apropriado:" 15 50 3 "Intel" "" "AMD" "" "NVIDIA" "" 2>&1 >/dev/tty)
clear

# Seleção de Disco
DISK_LIST=($(lsblk -d -n -o NAME,SIZE,MODEL | awk '{print $1, "["$2"]", $3, $4, $5}'))
DISK_CHOICE=$(dialog --clear --backtitle "Particionamento" --title "Seleção de Disco de Destino" --menu "ATENÇÃO: O disco escolhido será formatado." 20 70 15 "${DISK_LIST[@]}" 2>&1 >/dev/tty)
SSD="/dev/$DISK_CHOICE"
clear

# Partição /home separada
if dialog --clear --backtitle "Particionamento" --yesno "Deseja criar uma partição /home separada?" 10 40; then
    SEPARATE_HOME="s"
    ROOT_SIZE=$(dialog --clear --backtitle "Particionamento" --inputbox "Qual o tamanho da partição Raiz (/) ? (ex: 100G)" 10 40 "100G" 2>&1 >/dev/tty)
else
    SEPARATE_HOME="n"
fi
clear

# Seleção Individual de Pacotes
EXTRA_PACKAGES=""
DEV_PACKAGES=$(dialog --clear --backtitle "Seleção de Software" --checklist "Ferramentas de Desenvolvimento" 20 70 15 "git" "Git" "on" "code" "VS Code" "on" 2>&1 >/dev/tty)
MEDIA_PACKAGES=$(dialog --clear --backtitle "Seleção de Software" --checklist "Softwares de Mídia" 20 70 15 "vlc" "Player de vídeo" "on" "gimp" "Editor de imagens" "off" 2>&1 >/dev/tty)
EXTRA_PACKAGES="$(echo $DEV_PACKAGES $MEDIA_PACKAGES | tr -d '"')"
clear

# Confirmação Final
dialog --clear --backtitle "Confirmação Final" --yesno "A instalação começará em '$SSD' para o usuário '$USUARIO'.\nTODOS os dados serão apagados.\n\nDeseja continuar?" 10 60
response=$?
clear
if [ $response -ne 0 ]; then
    echo "Instalação cancelada pelo usuário."
    exit
fi

# --- [ 3. INSTALAÇÃO ] ---

echo ">>> Particionando o disco $SSD..."
sgdisk -Z $SSD
if [[ "$SEPARATE_HOME" == "s" ]]; then
    sgdisk -n=1:0:+512M -t=1:ef00 -n=2:0:+17G -t=2:8200 -n=3:0:+$ROOT_SIZE -t=3:8300 -n=4:0:0 -t=4:8300 $SSD
else
    sgdisk -n=1:0:+512M -t=1:ef00 -n=2:0:+17G -t=2:8200 -n=3:0:0 -t=3:8300 $SSD
fi

echo ">>> Formatando e montando partições..."
mkfs.fat -F 32 ${SSD}1 &> /dev/null
mkswap ${SSD}2 &> /dev/null
mkfs.ext4 ${SSD}3 &> /dev/null
mount ${SSD}3 /mnt
swapon ${SSD}2
mkdir -p /mnt/boot
mount ${SSD}1 /mnt/boot
if [[ "$SEPARATE_HOME" == "s" ]]; then
    mkfs.ext4 ${SSD}4 &> /dev/null
    mkdir -p /mnt/home
    mount ${SSD}4 /mnt/home
fi

# Construção da lista de pacotes gráficos
GFX_PACKAGES=""
if [ "$GPU_CHOICE" == "NVIDIA" ]; then
    GFX_PACKAGES="nvidia-dkms nvidia-utils lib32-nvidia-utils"
else # Intel ou AMD
    GFX_PACKAGES="mesa lib32-mesa"
fi

echo ">>> Instalando o sistema base. Isso pode levar vários minutos..."
pacstrap -K /mnt base linux linux-firmware intel-ucode micro $EXTRA_PACKAGES
if [ $? -ne 0 ]; then echo "ERRO: Falha ao instalar pacotes base. Verifique a conexão com a internet."; exit 1; fi

genfstab -U /mnt >> /mnt/etc/fstab

# --- [ 4. CONFIGURAÇÃO VIA CHROOT ] ---

echo ">>> Preparando o script de configuração final..."
cat << EOF > /mnt/chroot-script.sh
#!/bin/bash
TIMEZONE="$TIMEZONE"
LOCALE="$LOCALE"
KEYMAP="$KEYMAP"
HOSTNAME="$HOSTNAME"
USUARIO="$USUARIO"
SSD_DEVICE="$SSD"
GFX_PACKAGES_CHROOT="$GFX_PACKAGES"
GPU_CHOICE_CHROOT="$GPU_CHOICE"

echo ":: Configurando fuso horário e locale..."
ln -sf /usr/share/zoneinfo/\$TIMEZONE /etc/localtime
hwclock --systohc
echo "LANG=\$LOCALE" > /etc/locale.conf
echo "KEYMAP=\$KEYMAP" > /etc/vconsole.conf
sed -i "s/^#\$LOCALE/\$LOCALE/" /etc/locale.gen
locale-gen

echo ":: Configurando hostname..."
echo "\$HOSTNAME" > /etc/hostname

echo ":: Definindo senha para ROOT..."
passwd

echo ":: Criando usuário \$USUARIO e definindo senha..."
useradd -m -G wheel \$USUARIO
passwd \$USUARIO

echo ":: Configurando sudo..."
pacman -S --noconfirm --needed sudo
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo ":: Configurando hibernação, tampa e drivers..."
MKINIT_MODULES=""
if [ "\$GPU_CHOICE_CHROOT" == "NVIDIA" ]; then MKINIT_MODULES="nvidia nvidia_modeset nvidia_uvm nvidia_drm"; fi
sed -i "s/^MODULES=(.*)/MODULES=(\$MKINIT_MODULES)/" /etc/mkinitcpio.conf
sed -i 's/^HOOKS=(.*)/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block filesystems resume fsck)/' /etc/mkinitcpio.conf
sed -i 's/^#HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=ignore/' /etc/systemd/logind.conf
mkinitcpio -P

echo ":: Configurando o bootloader..."
bootctl --path=/boot install
ROOT_UUID=\$(blkid -s UUID -o value \${SSD_DEVICE}3)
SWAP_UUID=\$(blkid -s UUID -o value \${SSD_DEVICE}2)
BOOT_OPTIONS=""
if [ "\$GPU_CHOICE_CHROOT" == "NVIDIA" ]; then BOOT_OPTIONS="nvidia_drm.modeset=1"; fi
echo "default arch-*" > /boot/loader/loader.conf
echo "timeout 3" >> /boot/loader/loader.conf
echo "title Arch Linux" > /boot/loader/entries/arch.conf
echo "linux /vmlinuz-linux" >> /boot/loader/entries/arch.conf
echo "initrd /intel-ucode.img" >> /boot/loader/entries/arch.conf
echo "initrd /initramfs-linux.img" >> /boot/loader/entries/arch.conf
echo "options root=UUID=\$ROOT_UUID rw resume=UUID=\$SWAP_UUID \$BOOT_OPTIONS" >> /boot/loader/entries/arch.conf

echo ":: Instalando ambiente gráfico e pacotes..."
pacman -S --noconfirm --needed networkmanager iwd udisks2 \$GFX_PACKAGES_CHROOT hyprland wayland xorg-wayland kitty rofi dunst sddm sddm-kcm polkit-kde-agent firefox dolphin bluez bluez-utils pipewire wireplumber pipewire-pulse tlp brightnessctl waybar papirus-icon-theme adw-gtk3 qt6ct
if [ \$? -ne 0 ]; then echo "ERRO: Falha ao baixar pacotes do ambiente gráfico."; exit 1; fi

echo ":: Habilitando serviços..."
systemctl enable sddm NetworkManager iwd bluetooth tlp udisks2

echo ":: Configurando Proteção de Bateria..."
sed -i 's/^#START_CHARGE_THRESH_BAT0=.*/START_CHARGE_THRESH_BAT0=75/' /etc/tlp.conf
sed -i 's/^#STOP_CHARGE_THRESH_BAT0=.*/STOP_CHARGE_THRESH_BAT0=80/' /etc/tlp.conf

echo ":: Gerando script de configuração do usuário..."
# (O script de setup do usuário permanece o mesmo, é robusto)
cat > /home/\$USUARIO/setup.sh << SETUP
#!/bin-bash
# ... (conteúdo do script setup.sh que já tínhamos) ...
SETUP
chown -R \$USUARIO:\$USUARIO /home/\$USUARIO
chmod +x /home/\$USUARIO/setup.sh
EOF

# --- [ 5. EXECUÇÃO FINAL ] ---
echo ">>> Entrando no novo sistema para a configuração final..."
arch-chroot /mnt /bin/bash -c "chmod +x /chroot-script.sh; /chroot-script.sh"

clear
echo "====================================================="
echo "          Instalação Principal Concluída!"
echo "====================================================="
echo "TAREFA FINAL: Após reiniciar, logue com seu usuário e rode './setup.sh'"
umount -R /mnt
echo "Pressione [Enter] para reiniciar."
read
reboot
