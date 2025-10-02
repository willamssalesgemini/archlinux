#!/bin/bash
#
# SCRIPT DE INSTALAÇÃO DEFINITIVO - ARCH LINUX + HYPRLAND
# Versão 7.1 (Completa, Corrigida e Verificada)
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

# Coleta de todas as informações do usuário
HOSTNAME=$(dialog --clear --backtitle "Configuração do Sistema" --inputbox "Digite um nome para o seu computador (hostname):" 10 40 2>&1 >/dev/tty)
clear
USUARIO=$(dialog --clear --backtitle "Configuração do Sistema" --inputbox "Digite um nome para seu usuário (sem maiúsculas):" 10 40 2>&1 >/dev/tty)
clear

# Coleta de Senhas de forma segura
SENHA_USUARIO=$(dialog --clear --backtitle "Segurança" --passwordbox "Digite a senha para o usuário $USUARIO:" 10 40 2>&1 >/dev/tty)
clear
SENHA_USUARIO_CONFIRM=$(dialog --clear --backtitle "Segurança" --passwordbox "Confirme a senha para o usuário $USUARIO:" 10 40 2>&1 >/dev/tty)
clear
while [[ "$SENHA_USUARIO" != "$SENHA_USUARIO_CONFIRM" ]]; do
    SENHA_USUARIO=$(dialog --clear --backtitle "Segurança" --passwordbox "As senhas não coincidem. Digite a senha para $USUARIO novamente:" 10 50 2>&1 >/dev/tty)
    clear
    SENHA_USUARIO_CONFIRM=$(dialog --clear --backtitle "Segurança" --passwordbox "Confirme a senha:" 10 50 2>&1 >/dev/tty)
    clear
done

SENHA_ROOT=$(dialog --clear --backtitle "Segurança" --passwordbox "Digite a senha para o Administrador (root):" 10 40 2>&1 >/dev/tty)
clear
SENHA_ROOT_CONFIRM=$(dialog --clear --backtitle "Segurança" --passwordbox "Confirme a senha para o Administrador (root):" 10 40 2>&1 >/dev/tty)
clear
while [[ "$SENHA_ROOT" != "$SENHA_ROOT_CONFIRM" ]]; do
    SENHA_ROOT=$(dialog --clear --backtitle "Segurança" --passwordbox "As senhas não coincidem. Digite a senha para root novamente:" 10 50 2>&1 >/dev/tty)
    clear
    SENHA_ROOT_CONFIRM=$(dialog --clear --backtitle "Segurança" --passwordbox "Confirme a senha:" 10 50 2>&1 >/dev/tty)
    clear
done

# Pergunta sobre privilégios Sudo
if dialog --clear --backtitle "Segurança" --yesno "Deseja conceder privilégios de administrador (sudo) ao usuário $USUARIO?" 10 60; then
    USER_IS_SUDOER="yes"
else
    USER_IS_SUDOER="no"
fi
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

# Construção da lista de pacotes
GFX_PACKAGES=""
if [ "$GPU_CHOICE" == "NVIDIA" ]; then
    GFX_PACKAGES="nvidia-dkms nvidia-utils lib32-nvidia-utils"
else # Intel ou AMD
    GFX_PACKAGES="mesa lib32-mesa"
fi

echo ">>> Instalando o sistema base e pacotes opcionais. Isso pode levar vários minutos..."
pacstrap -K /mnt base linux linux-firmware intel-ucode micro $EXTRA_PACKAGES
if [ $? -ne 0 ]; then echo "ERRO: Falha ao instalar pacotes base. Verifique a conexão."; exit 1; fi

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
SENHA_USUARIO="$SENHA_USUARIO"
SENHA_ROOT="$SENHA_ROOT"
USER_IS_SUDOER="$USER_IS_SUDOER"
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

echo ":: Criando usuário e definindo senhas..."
echo "root:\$SENHA_ROOT" | chpasswd
if [[ "\$USER_IS_SUDOER" == "yes" ]]; then
    useradd -m -G wheel \$USUARIO
else
    useradd -m \$USUARIO
fi
echo "\$USUARIO:\$SENHA_USUARIO" | chpasswd

echo ":: Configurando sudo (se aplicável)..."
pacman -S --noconfirm --needed sudo
if [[ "\$USER_IS_SUDOER" == "yes" ]]; then
    sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
fi

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

echo ":: Instalando ambiente gráfico e todos os pacotes..."
pacman -S --noconfirm --needed networkmanager iwd udisks2 \$GFX_PACKAGES_CHROOT hyprland wayland xorg-wayland kitty rofi dunst sddm sddm-kcm polkit-kde-agent firefox dolphin bluez bluez-utils pipewire wireplumber pipewire-pulse tlp brightnessctl waybar papirus-icon-theme adw-gtk3 qt6ct qgnomeplatform-qt6 nwg-look archlinux-wallpaper hyprpaper grim slurp cliphist wl-clipboard gammastep
if [ \$? -ne 0 ]; then echo "ERRO: Falha ao baixar pacotes do ambiente gráfico."; exit 1; fi

echo ":: Habilitando serviços..."
systemctl enable sddm NetworkManager iwd bluetooth tlp udisks2

echo ":: Automatizando configurações de sistema..."
cat > /etc/fonts/local.conf << FONTCONF
<?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "fonts.dtd"><fontconfig><match target="font"><edit name="antialias" mode="assign"><bool>true</bool></edit><edit name="hinting" mode="assign"><bool>true</bool></edit><edit name="hintstyle" mode="assign"><const>hintslight</const></edit><edit name="rgba" mode="assign"><const>rgb</const></edit><edit name="lcdfilter" mode="assign"><const>lcddefault</const></edit></match></fontconfig>
FONTCONF
sed -i 's/^#START_CHARGE_THRESH_BAT0=.*/START_CHARGE_THRESH_BAT0=75/' /etc/tlp.conf
sed -i 's/^#STOP_CHARGE_THRESH_BAT0=.*/STOP_CHARGE_THRESH_BAT0=80/' /etc/tlp.conf

echo ":: Gerando script de configuração do usuário..."
cat > /home/\$USUARIO/setup.sh << SETUP
#!/bin/bash
echo ":: Configurando pastas de usuário..."
xdg-user-dirs-update &> /dev/null
echo ":: Configurando tema GTK e Qt..."
mkdir -p /home/\$USUARIO/.config/gtk-3.0
echo -e "[Settings]\ngtk-theme-name=Adwaita-dark\ngtk-icon-theme-name=Papirus-Dark" > /home/\$USUARIO/.config/gtk-3.0/settings.ini
gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark'
gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark'
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
mkdir -p /home/\$USUARIO/.config/qt6ct
cat > /home/\$USUARIO/.config/qt6ct/qt6ct.conf << QTCONF
[Appearance]
color_scheme_path=
custom_palette=false
icon_theme=Papirus-Dark
style=kvantum
[General]
font_style_name=
[Fonts]
fixed_font=
general_font=
QTCONF
echo "export QT_QPA_PLATFORMTHEME=qt6ct" >> /home/\$USUARIO/.profile

echo ":: Configurando Waybar..."
mkdir -p /home/\$USUARIO/.config/waybar
cat > /home/\$USUARIO/.config/waybar/config << WB_CONF
{
    "layer": "top", "position": "top", "height": 40,
    "modules-left": ["hyprland/workspaces", "hyprland/mode"],
    "modules-center": ["hyprland/window"],
    "modules-right": ["pulseaudio", "network", "cpu", "memory", "battery", "clock", "tray"],
    "hyprland/window": { "format": " {} " },
    "tray": { "icon-size": 21, "spacing": 10 },
    "clock": { "format": "{:%H:%M  %d/%m}", "tooltip-format": "<big>{:%Y %B}</big>\\n<tt><small>{calendar}</small></tt>" },
    "cpu": { "format": "{usage}% ", "tooltip": true },
    "memory": { "format": "{}% " },
    "battery": { "format": "{capacity}% {icon}", "format-icons": ["", "", "", "", ""] },
    "network": { "format-wifi": "{essid} ({signalStrength}%) ", "format-ethernet": "{ifname}: {ipaddr}/{cidr} ", "format-disconnected": "Sem Rede ⚠" },
    "pulseaudio": { "format": "{volume}% {icon} {format_source}", "format-bluetooth": "{volume}% {icon} {format_source}", "format-icons": { "default": ["", "", ""] }, "on-click": "pavucontrol" }
}
WB_CONF
cat > /home/\$USUARIO/.config/waybar/style.css << WB_CSS
* { border: none; font-family: DejaVu Sans, FontAwesome; font-size: 13px; }
window#waybar { background-color: rgba(43, 48, 59, 0.5); border-bottom: 3px solid rgba(100, 114, 125, 0.5); color: #ffffff; }
#workspaces button { padding: 0 5px; background-color: transparent; color: #ffffff; border-bottom: 3px solid transparent; }
#workspaces button:hover { background: rgba(0, 0, 0, 0.2); }
#workspaces button.active { background-color: #64727D; border-bottom: 3px solid #ffffff; }
#mode, #clock, #battery, #cpu, #memory, #network, #pulseaudio, #tray { padding: 0 10px; color: #ffffff; }
WB_CSS

echo ":: Configurando Hyprland e Wallpaper..."
mkdir -p /home/\$USUARIO/.config/hypr
cat > /home/\$USUARIO/.config/hypr/hyprpaper.conf << HP_CONF
preload = /usr/share/backgrounds/archlinux/arch-swoosh.png
wallpaper = ,/usr/share/backgrounds/archlinux/arch-swoosh.png
HP_CONF
cat > /home/\$USUARIO/.config/hypr/hyprland.conf << HYPRCONF
monitor=,preferred,auto,1
exec-once = waybar & hyprpaper & /usr/lib/polkit-kde-authentication-agent-1 & wl-paste --watch cliphist store & gammastep-indicator
\$mainMod = SUPER
bind = \$mainMod, Q, killactive,
bind = \$mainMod, M, exit,
bind = \$mainMod, E, exec, dolphin
bind = \$mainMod, V, togglefloating,
bind = \$mainMod, F, fullscreen,
bind = \$mainMod, D, exec, rofi -show drun
bind = \$mainMod, C, exec, cliphist list | rofi -dmenu | cliphist decode | wl-copy
bind = , XF86MonBrightnessUp, exec, brightnessctl set +5%
bind = , XF86MonBrightnessDown, exec, brightnessctl set 5%-
bind = , lidswitch, close, exec, hyprctl keyword monitor "eDP-1, disable"
bind = , lidswitch, open, exec, hyprctl keyword monitor "eDP-1, preferred, auto, 1"
input { kb_layout = us; follow_mouse = 1; touchpad { natural_scroll = yes } }
general { gaps_in = 5; gaps_out = 20; border_size = 2; col.active_border = rgba(33ccffee) rgba(00ff99ee) 45deg; col.inactive_border = rgba(595959aa); layout = dwindle; }
decoration { rounding = 10; blur { enabled = true; size = 3; passes = 1; } drop_shadow = yes; shadow_range = 4; shadow_render_power = 3; col.shadow = rgba(1a1a1aee); }
animations { enabled = yes; bezier = myBezier, 0.05, 0.9, 0.1, 1.05; animation = windows, 1, 7, myBezier; animation = border, 1, 10, default; animation = fade, 1, 7, default; animation = workspaces, 1, 6, default; }
dwindle { pseudotile = yes; preserve_split = yes; }
gestures { workspace_swipe = on; }
windowrulev2 = float, class:^(pavucontrol)\$
windowrulev2 = float, class:^(org.kde.polkit-kde-authentication-agent-1)\$
HYPRCONF

echo ":: Limpando e finalizando..."
rm -- "\$0"
echo "Setup do usuário concluído! Por favor, reinicie ou faça logout/login para que todas as mudanças tenham efeito."
SETUP
chown -R \$USUARIO:\$USUARIO /home/\$USUARIO
chmod +x /home/\$USUARIO/setup.sh
EOF

# --- [ 5. EXECUÇÃO FINAL ] ---
echo ">>> Entrando no novo sistema para a configuração final..."
arch-chroot /mnt /bin/bash /chroot-script.sh

clear
echo "====================================================="
echo "          Instalação Principal Concluída!"
echo "====================================================="
echo "TAREFA FINAL: Após reiniciar, logue com seu usuário e rode './setup.sh'"
umount -R /mnt
echo "Pressione [Enter] para reiniciar."
read
reboot