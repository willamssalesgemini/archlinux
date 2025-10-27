#!/bin/bash
#
# Script de Pós-Instalação Interativo para Arch + Hyprland
# Versão Final Polida: Idempotente, Detecção de Erros, Desinstalador, Tematização, Pipewire, FS Externo.
# Requer 'dialog' para a interface TUI.
#

# --- Configurações Iniciais e Cores ---
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_CYAN='\033[0;36m'
C_WHITE='\033[1;37m'

# --- Variáveis de Título ---
BACKTITLE="Assistente de Pós-Instalação Arch/Hyprland (Profissional vFinal)"

# --- Arquivos Temporários e de Log ---
CHOICES_FILE="/tmp/arch_choices.txt"
LOG_FILE="/tmp/pos_install.log"
> "$LOG_FILE" # Limpa o log anterior

# --- Funções de Log (para debug, não para dialog) ---
msg_info() { echo -e "${C_CYAN}[INFO]${C_RESET} $1"; }
msg_ok() { echo -e "${C_GREEN}[OK]${C_RESET} $1"; }
msg_err() { echo -e "${C_RED}[ERRO]${C_RESET} $1"; }

# --- Função de Verificação de Comando ---
command_exists() {
    command -v "$1" &> /dev/null
}

# --- Função de Exibição de Log ---
show_log() {
    local title="$1"
    dialog --backtitle "$BACKTITLE" --title "$title" --tailbox "$LOG_FILE" 20 80
}

# --- FUNÇÃO ROBUSTA: Instalação de Pacotes (Pacman) ---
# Verifica pacotes já instalados e detecta erros.
install_pacman_packages() {
    local packages_to_check=($@)
    local packages_to_install=()
    local packages_already_installed=()

    echo "--- Verificando pacotes Pacman: ${packages_to_check[*]} ---" >> "$LOG_FILE"
    
    # Filtra pacotes que não estão instalados
    for pkg in "${packages_to_check[@]}"; do
        # Trata grupos de pacotes (ex: base-devel)
        if pacman -Qg "$pkg" &>/dev/null || pacman -Q "$pkg" &>/dev/null; then
             packages_already_installed+=("$pkg")
        else
            packages_to_install+=("$pkg")
        fi
    done

    if [ ${#packages_already_installed[@]} -gt 0 ]; then
        echo "Pacotes/Grupos já instalados (pulando): ${packages_already_installed[*]}" >> "$LOG_FILE"
    fi

    if [ ${#packages_to_install[@]} -eq 0 ]; then
        echo "Nenhum pacote novo para instalar." >> "$LOG_FILE"
        # Não mostra infobox aqui para não interromper fluxos longos
        # dialog --infobox "Todos os pacotes selecionados já estão instalados." 4 60
        # sleep 1
        return 0
    fi

    echo "Iniciando instalação (Pacman): ${packages_to_install[*]}" >> "$LOG_FILE"
    sudo pacman -S "${packages_to_install[@]}" --noconfirm --needed &>> "$LOG_FILE"
    
    if [ $? -ne 0 ]; then
        echo "ERRO: Falha ao instalar um ou mais pacotes Pacman." >> "$LOG_FILE"
        dialog --msgbox "ERRO: Falha ao instalar pacotes.\n\nPor favor, verifique o log para detalhes." 8 60
        show_log "Log de Erro (Pacman)"
        return 1
    fi
    
    echo "Pacotes Pacman instalados com sucesso: ${packages_to_install[*]}" >> "$LOG_FILE"
    return 0
}

# --- FUNÇÃO ROBUSTA: Instalação de Pacotes (AUR / yay) ---
# Verifica pacotes já instalados e detecta erros.
install_aur_packages() {
    if ! command_exists yay; then
        dialog --msgbox "ERRO: 'yay' não está instalado.\n\nExecute o 'Passo 8' primeiro." 7 60
        return 1
    fi

    local packages_to_check=($@)
    local packages_to_install=()
    local packages_already_installed=()

    echo "--- Verificando pacotes AUR: ${packages_to_check[*]} ---" >> "$LOG_FILE"
    
    for pkg in "${packages_to_check[@]}"; do
        if ! yay -Q "$pkg" &>/dev/null; then
            packages_to_install+=("$pkg")
        else
            packages_already_installed+=("$pkg")
        fi
    done
    
    if [ ${#packages_already_installed[@]} -gt 0 ]; then
        echo "Pacotes AUR já instalados (pulando): ${packages_already_installed[*]}" >> "$LOG_FILE"
    fi

    if [ ${#packages_to_install[@]} -eq 0 ]; then
        echo "Nenhum pacote novo do AUR para instalar." >> "$LOG_FILE"
        # dialog --infobox "Todos os pacotes AUR selecionados já estão instalados." 4 60
        # sleep 1
        return 0
    fi
    
    echo "Iniciando instalação (AUR): ${packages_to_install[*]}" >> "$LOG_FILE"
    yay -S "${packages_to_install[@]}" --noconfirm --needed &>> "$LOG_FILE"
    
    if [ $? -ne 0 ]; then
        echo "ERRO: Falha ao instalar um ou mais pacotes AUR." >> "$LOG_FILE"
        dialog --msgbox "ERRO: Falha ao instalar pacotes do AUR.\n\nPor favor, verifique o log para detalhes." 8 60
        show_log "Log de Erro (AUR)"
        return 1
    fi
    
    echo "Pacotes AUR instalados com sucesso: ${packages_to_install[*]}" >> "$LOG_FILE"
    return 0
}


# --- 1. Verificação e Instalação do 'dialog' ---
check_dialog() {
    if ! command_exists dialog; then
        echo -e "${C_YELLOW}A dependência 'dialog' não está instalada.${C_RESET}"
        echo "Tentando instalar 'dialog' via Pacman..."
        sudo pacman -S dialog --noconfirm --needed
        if [ $? -ne 0 ]; then
            echo -e "${C_RED}Falha ao instalar 'dialog'. Este script não pode continuar.${C_RESET}"
            exit 1
        fi
        clear
    fi
}

# --- 1b. Verificações de Pré-requisitos ---
check_prereqs() {
    if [ "$(id -u)" -eq 0 ]; then
        dialog --msgbox "ERRO: Este script não deve ser executado como 'root'.\n\nExecute como seu usuário normal. Ele solicitará a senha 'sudo' quando necessário." 10 60
        exit 1
    fi
    
    dialog --infobox "Verificando conexão com a internet..." 4 50
    if ! ping -c 1 archlinux.org &> /dev/null; then
        dialog --msgbox "ERRO: Não foi possível conectar à internet.\n\nPor favor, conecte-se (ex: 'nmcli device wifi connect ...') e tente novamente." 10 60
        exit 1
    fi
}

# --- 2. Atualizar Sistema ---
update_system() {
    dialog --backtitle "$BACKTITLE" --title "Atualizar Sistema" \
           --yesno "Deseja sincronizar e atualizar todos os pacotes do sistema agora? (Recomendado)" 7 60
    if [ $? -eq 0 ]; then
        echo "--- Log: Atualizando o Sistema (pacman -Syu) ---" > "$LOG_FILE"
        sudo pacman -Syu --noconfirm &>> "$LOG_FILE"
        
        if [ $? -ne 0 ]; then
            dialog --msgbox "Ocorreu um erro durante a atualização. Verifique o log." 6 50
            show_log "Log da Atualização do Sistema" # Mostra o log em caso de erro
        else
            dialog --msgbox "Sistema atualizado com sucesso." 6 50
        fi
        # Removido show_log daqui para não mostrar sempre
    fi
}

# --- 3. Instalar Pacotes Base ---
install_base_system() {
    # --- AJUSTE NVIDIA: Perguntar sobre a GPU ---
    local hyprland_pkg_status="on"
    local use_nvidia=false
    dialog --backtitle "$BACKTITLE" --title "Detecção de Hardware" \
           --yesno "Você está usando uma placa gráfica NVIDIA (proprietária)?" 7 60
    if [ $? -eq 0 ]; then
        # Se SIM (NVIDIA):
        use_nvidia=true
        hyprland_pkg_status="off"
        dialog --msgbox "OK. O pacote 'hyprland' padrão NÃO será instalado.\n\nA versão correta para NVIDIA ('hyprland-nvidia-dkms' do AUR) será oferecida no 'Passo 9: Drivers Gráficos'." 10 60
    else
        # Se NÃO (Intel/AMD):
        use_nvidia=false
        hyprland_pkg_status="on"
    fi
    
    # --- MELHORIA: Pipewire vs Pulseaudio ---
    local audio_choice
    local audio_pkgs=()
    local pavucontrol_status="on"
    dialog --backtitle "$BACKTITLE" --title "Seleção de Áudio" \
           --radiolist "Escolha o servidor de áudio:" 12 70 2 \
           "pipewire" "Pipewire (Moderno, Recomendado)" on \
           "pulseaudio" "Pulseaudio (Legado)" off \
           2> "$CHOICES_FILE"

    if [ $? -ne 0 ]; then rm -f "$CHOICES_FILE"; return; fi # Cancelou
    audio_choice=$(cat "$CHOICES_FILE" | tr -d '"')

    if [ "$audio_choice" == "pipewire" ]; then
        audio_pkgs=("pipewire" "wireplumber" "pipewire-pulse" "pipewire-alsa")
        pavucontrol_status="off" # Não instalar pavucontrol com pipewire
    else
        audio_pkgs=("pulseaudio")
        pavucontrol_status="on"
    fi
    
    # Lista de pacotes
    local base_packages=(
           "hyprland" "O compositor Wayland (Obrigatório)" "$hyprland_pkg_status"
           "kitty" "Terminal recomendado para Hyprland" "on"
           "micro" "Seu editor de texto (fácil de usar)" "on"
           "firefox" "Navegador Web" "on"
           "thunar" "Gerenciador de arquivos leve (GTK)" "on"
           "wofi" "Lançador de aplicativos (Menu Iniciar)" "on"
           "waybar" "Barra de status (Wayland)" "on"
           "mako" "Servidor de notificações" "on"
           "swaybg" "Utilitário para papel de parede" "on"
           "swaylock" "Bloqueio de tela" "on"
           "xdg-desktop-portal-hyprland" "Integração de portal (Obrigatório)" "on"
           "polkit-kde-agent" "Agente de autenticação (para permissões)" "on"
           "xdg-user-dirs" "Cria pastas (~/Documentos, ~/Imagens, etc)" "on"
           "ufw" "Firewall simples (Recomendado)" "on"
           # Áudio: Adicionado dinamicamente abaixo
           "pavucontrol" "Mixer de áudio gráfico (Pulseaudio)" "$pavucontrol_status"
           "grim" "Utilitário de screenshot para Wayland" "on"
           "slurp" "Utilitário para selecionar área (p/ grim)" "on"
           "wl-clipboard" "Suporte a Copiar/Colar no terminal" "on"
           "nautilus" "Gerenciador de arquivos (Gnome, pesado, Escolha 1)" "off"
           "dolphin" "Gerenciador de arquivos (KDE, pesado, Escolha 1)" "off"
           # --- MELHORIA: Suporte a Filesystems Externos ---
           "ntfs-3g" "Suporte a partições NTFS (Windows)" "on"
           "exfatprogs" "Suporte a partições exFAT (Pendrives/Cartões)" "on"
           "udisks2" "Serviço para montar discos (Auto-mount)" "on" # Essencial p/ Thunar
           "gvfs" "Virtual Filesystem (Ajuda Thunar)" "on" # Essencial p/ Thunar
           # --- MELHORIA: Wallpaper Padrão ---
           "archlinux-wallpaper" "Papéis de parede padrão do Arch" "on"
    )

    dialog --backtitle "$BACKTITLE" --title "Pacotes Base + FS + Áudio" \
           --checklist "Selecione os pacotes essenciais (Use Espaço para marcar/desmarcar):" 20 75 25 \
           "${base_packages[@]}" \
           2> "$CHOICES_FILE"
           
    if [ $? -eq 0 ]; then
        choices=$(cat "$CHOICES_FILE" | tr -d '"')
        # Adiciona os pacotes de áudio escolhidos à lista
        choices_with_audio=(${choices[@]} ${audio_pkgs[@]})
        
        if [ ${#choices_with_audio[@]} -gt 0 ]; then
            echo "--- Log: Instalando Pacotes Base ---" > "$LOG_FILE"
            # Usa a nova função robusta
            if install_pacman_packages "${choices_with_audio[@]}"; then
                if [[ " ${choices[@]} " =~ " ufw " ]]; then
                    echo "--- Ativando UFW (Firewall) ---" >> "$LOG_FILE"
                    sudo systemctl enable ufw &>> "$LOG_FILE"
                    sudo ufw enable &>> "$LOG_FILE"
                fi

                if [[ " ${choices[@]} " =~ " xdg-user-dirs " ]]; then
                    xdg-user-dirs-update &>> "$LOG_FILE"
                    echo "Diretórios de usuário (~/Documentos) criados." >> "$LOG_FILE"
                fi
                
                # Ativar serviço udisks2 se instalado
                if [[ " ${choices[@]} " =~ " udisks2 " ]]; then
                    echo "--- Ativando serviço udisks2 (Auto-mount) ---" >> "$LOG_FILE"
                    sudo systemctl enable udisks2 &>> "$LOG_FILE"
                fi

                # Copiar wallpaper padrão se instalado
                if [[ " ${choices[@]} " =~ " archlinux-wallpaper " ]]; then
                    echo "--- Copiando wallpaper padrão ---" >> "$LOG_FILE"
                    mkdir -p ~/Imagens &>> "$LOG_FILE"
                    cp /usr/share/backgrounds/archlinux/archwave.png ~/Imagens/wallpaper.png &>> "$LOG_FILE"
                    if [ $? -eq 0 ]; then
                        echo "Wallpaper copiado para ~/Imagens/wallpaper.png" >> "$LOG_FILE"
                    else
                        echo "ERRO: Falha ao copiar wallpaper padrão." >> "$LOG_FILE"
                    fi
                fi
                
                dialog --msgbox "Pacotes base instalados e configurados." 6 60
            fi
            show_log "Log de Instalação (Pacotes Base)"
        else
            dialog --msgbox "Nenhum pacote selecionado." 6 50
        fi
    fi
    rm -f "$CHOICES_FILE"
}

# --- 4. Instalar Fontes e Codecs ---
install_fonts_codecs() {
    dialog --backtitle "$BACKTITLE" --title "Fontes e Codecs" \
           --checklist "Selecione fontes e codecs de mídia (Recomendado marcar todos):" 20 70 10 \
           "noto-fonts" "Fontes padrão do Google (Boa cobertura)" on \
           "noto-fonts-cjk" "Fontes para Chinês/Japonês/Coreano" on \
           "noto-fonts-emoji" "Suporte completo a Emojis" on \
           "ttf-liberation" "Substitutas para fontes da Microsoft" on \
           "ttf-font-awesome" "Fonte de ícones (essencial para Waybar)" on \
           "gstreamer" "Framework base de mídia" on \
           "gst-plugins-good" "Codecs de mídia (Bons)" on \
           "gst-plugins-bad" "Codecs de mídia (Ruins, mas úteis)" on \
           "gst-plugins-ugly" "Codecs de mídia (Feios, mas úteis)" on \
           "libavcodec" "Codecs FFmpeg (para MPV, VLC, etc)" on \
           2> "$CHOICES_FILE"
           
    if [ $? -eq 0 ]; then
        choices=$(cat "$CHOICES_FILE" | tr -d '"')
        if [ -n "$choices" ]; then
            echo "--- Log: Instalando Fontes e Codecs ---" > "$LOG_FILE"
            if install_pacman_packages $choices; then
                dialog --msgbox "Fontes e codecs instalados." 6 50
            fi
            show_log "Log de Instalação (Fontes/Codecs)"
        else
            dialog --msgbox "Nenhum item selecionado." 6 50
        fi
    fi
    rm -f "$CHOICES_FILE"
}

# --- 5. Criar Configs Tematizadas (Vidro) ---
setup_configs() {
    local config_dir="$HOME/.config"
    
    dialog --backtitle "$BACKTITLE" --title "Configs Tematizadas (Vidro + Env/Rules)" \
           --yesno "Deseja criar os arquivos de configuração iniciais com tema de 'vidro' (blur)?\n\n(Configs: Hyprland, Kitty, Waybar, Wofi, Mako)\n(Adiciona Vars. de Ambiente e Regras de Janela)\n\n(AVISO: Pastas existentes serão renomeadas para '.bak.DATA')" 14 70
           
    if [ $? -eq 0 ]; then
        echo "--- Log: Configurando arquivos .conf ---" > "$LOG_FILE"
        
        # --- Função de Backup ---
        backup_config() {
            local dir_to_backup="$config_dir/$1"
            if [ -d "$dir_to_backup" ]; then
                local backup_dir="$dir_to_backup.bak.$(date +%Y%m%d-%H%M%S)"
                echo "Fazendo backup de $dir_to_backup para $backup_dir" >> "$LOG_FILE"
                mv "$dir_to_backup" "$backup_dir" &>> "$LOG_FILE"
            fi
        }

        dialog --infobox "Criando diretórios e arquivos..." 4 50
        
        # --- Backup e Criação de Pastas ---
        backup_config "hypr"
        backup_config "kitty"
        backup_config "waybar"
        backup_config "wofi"
        backup_config "mako"
        
        mkdir -p "$config_dir/hypr" &>> "$LOG_FILE"
        mkdir -p "$config_dir/kitty" &>> "$LOG_FILE"
        mkdir -p "$config_dir/waybar" &>> "$LOG_FILE"
        mkdir -p "$config_dir/wofi" &>> "$LOG_FILE"
        mkdir -p "$config_dir/mako" &>> "$LOG_FILE"


        # --- hyprland.conf (Arquivo Mestre) ---
        cat > "$config_dir/hypr/hyprland.conf" << EOF
# --- Arquivo Mestre: hyprland.conf ---
# Gerado por pos_install.sh

# Monitor (será preenchido pelo Passo 5)
# monitor=,preferred,auto,1

# Carrega arquivos de configuração separados
source = ~/.config/hypr/startup.conf
source = ~/.config/hypr/binds.conf
source = ~/.config/hypr/windowrules.conf
source = ~/.config/hypr/monitors.conf
source = ~/.config/hypr/environment.conf

# Configurações de Aparência
general {
    gaps_in = 5
    gaps_out = 10
    border_size = 2
    col.active_border = rgba(33ccffee) rgba(00ff99ee) 45deg
    col.inactive_border = rgba(595959aa)
    layout = dwindle
    # allow_tearing = false # Descomente se tiver tearing
}

# Decoração (Blur, Bordas, Sombra)
decoration {
    rounding = 10
    
    blur {
        enabled = true
        size = 5
        passes = 2
        new_optimizations = true
        xray = true # Descomente se usar blur em janelas flutuantes sobre outras
    }

    drop_shadow = yes
    shadow_range = 4
    shadow_render_power = 3
    col.shadow = rgba(1a1a1aee)
}

# Animações
animations {
    enabled = yes
    # Exemplo: Deslizar janelas
    bezier = myBezier, 0.05, 0.9, 0.1, 1.05
    animation = windows, 1, 7, myBezier
    animation = windowsOut, 1, 7, default, popin 80%
    animation = border, 1, 10, default
    animation = fade, 1, 7, default
    animation = workspaces, 1, 6, default
}

# Layout Dwindle (Espiral)
dwindle {
    pseudotile = yes # Janela master ocupa metade da tela
    preserve_split = yes 
}

# Layout Master (Principal + Pilha)
# master {
#    new_is_master = true
# }

# Gestos (ex: touchpad)
gestures {
    workspace_swipe = on
}

# Diversos
misc {
    force_default_wallpaper = -1 # Permite swaybg
    vfr = true # Variable Refresh Rate (conserva recursos)
    # enable_swallow = true # Descomente para ativar window swallowing
    # swallow_regex = ^(kitty)$ # Exemplo: engolir apenas o kitty
}

# Input (Teclado, Mouse)
input {
    kb_layout = br
    kb_variant = abnt2
    kb_options = grp:alt_shift_toggle # Ex: Trocar layout com Alt+Shift
    follow_mouse = 1 # 1 = Foco segue o mouse

    touchpad {
        natural_scroll = no
        disable_while_typing = true
    }

    sensitivity = 0 # -1.0 a 1.0; 0 = padrão
}

# Ativa blur para Waybar e Wofi
layerrule = blur, waybar
layerrule = blur, wofi
EOF

        # --- startup.conf (Apps de Inicialização) ---
        cat > "$config_dir/hypr/startup.conf" << EOF
# --- Programas de Inicialização ---
# Gerado por pos_install.sh

exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP # Necessário para alguns serviços
exec-once = systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP # Necessário para alguns serviços
exec-once = /usr/lib/polkit-kde-authentication-agent-1 # Agente de autenticação
exec-once = waybar # Barra de status
exec-once = swaybg -i ~/Imagens/wallpaper.png # Define wallpaper (copiado no Passo 2)
exec-once = mako # Servidor de notificação
# exec-once = dunst # Alternativa ao mako
# exec-once = blueman-applet # Ícone do Bluetooth na bandeja (se instalado)
# exec-once = nm-applet --indicator # Ícone de rede na bandeja (se instalado NetworkManager)

# Se usar Pipewire:
# exec-once = systemctl --user start pipewire pipewire-pulse wireplumber
EOF

        # --- binds.conf (Atalhos) ---
        cat > "$config_dir/hypr/binds.conf" << EOF
# --- Atalhos de Teclado (Binds) ---
# Gerado por pos_install.sh
# Veja https://wiki.hyprland.org/Configuring/Binds/ para mais exemplos

\$mod = SUPER # Tecla "Windows"

# Aplicativos Essenciais
bind = \$mod, RETURN, exec, kitty # Terminal
bind = \$mod, D, exec, wofi --show drun # Lançador de Apps
bind = \$mod, E, exec, thunar # Gerenciador de Arquivos (se instalado)
bind = \$mod, B, exec, firefox # Navegador (se instalado)

# Gerenciamento de Janelas
bind = \$mod, Q, killactive, # Fecha janela ativa
bind = \$mod SHIFT, F, fullscreen, # Alterna fullscreen
bind = \$mod, SPACE, togglefloating, # Alterna modo flutuante
bind = \$mod, P, pseudo, # Alterna pseudotile
bind = \$mod, J, togglesplit, # Altera divisão no dwindle

# Mover Foco
bind = \$mod, left, movefocus, l
bind = \$mod, right, movefocus, r
bind = \$mod, up, movefocus, u
bind = \$mod, down, movefocus, d
# Alternativa com HJKL (estilo Vim)
# bind = \$mod, H, movefocus, l
# bind = \$mod, L, movefocus, r
# bind = \$mod, K, movefocus, u
# bind = \$mod, J, movefocus, d

# Mover Janelas
bind = \$mod SHIFT, left, movewindow, l
bind = \$mod SHIFT, right, movewindow, r
bind = \$mod SHIFT, up, movewindow, u
bind = \$mod SHIFT, down, movewindow, d

# Workspaces (Áreas de Trabalho)
bind = \$mod, 1, workspace, 1
bind = \$mod, 2, workspace, 2
bind = \$mod, 3, workspace, 3
bind = \$mod, 4, workspace, 4
bind = \$mod, 5, workspace, 5
# ... adicione mais workspaces se desejar

# Mover Janela para Workspace
bind = \$mod SHIFT, 1, movetoworkspace, 1
bind = \$mod SHIFT, 2, movetoworkspace, 2
bind = \$mod SHIFT, 3, movetoworkspace, 3
bind = \$mod SHIFT, 4, movetoworkspace, 4
bind = \$mod SHIFT, 5, movetoworkspace, 5
# ... adicione mais workspaces se desejar

# Mover Janela para Workspace (Silencioso)
bind = \$mod CTRL, 1, movetoworkspacesilent, 1
bind = \$mod CTRL, 2, movetoworkspacesilent, 2
# ...

# Mudar Workspace com Scroll do Mouse na Barra
bind = , mouse_down, workspace, e+1
bind = , mouse_up, workspace, e-1

# Mover/Redimensionar Janelas com Mouse
bindm = \$mod, mouse:272, movewindow
bindm = \$mod, mouse:273, resizewindow

# Screenshot (usando grim e slurp)
bind = , Print, exec, grim -g "\$(slurp)" - | wl-copy # Captura área e copia
bind = SHIFT, Print, exec, grim - | wl-copy # Captura tela inteira e copia
# bind = CTRL, Print, exec, grim -o "\$(hyprctl monitors -j | jq -r '.[0].name')" # Captura monitor ativo

# Bloquear Tela
bind = \$mod, L, exec, swaylock 
EOF

        # --- monitors.conf (Vazio) ---
        touch "$config_dir/hypr/monitors.conf"
        
        # --- environment.conf (MELHORIA: Vars de PDFs) ---
        cat > "$config_dir/hypr/environment.conf" << EOF
# --- Variáveis de Ambiente ---
# Gerado por pos_install.sh

# Define Wayland como padrão para Toolkits (Baseado nos PDFs)
env = GDK_BACKEND,wayland,x11,*
env = QT_QPA_PLATFORM,wayland;xcb
env = SDL_VIDEODRIVER,wayland
env = CLUTTER_BACKEND,wayland

# Tema e Tamanho do Cursor (Baseado nos PDFs)
env = XCURSOR_THEME,Bibata-Modern-Classic # Troque pelo seu tema preferido
env = XCURSOR_SIZE,24

# XDG Desktop Portal (Importante para Flatpak, etc)
env = XDG_CURRENT_DESKTOP,Hyprland
env = XDG_SESSION_TYPE,wayland
env = XDG_SESSION_DESKTOP,Hyprland

# Exemplo para tema Qt (se usar qt5ct ou Kvantum)
# env = QT_QPA_PLATFORMTHEME,qt5ct 

# Variáveis NVIDIA serão adicionadas aqui pelo Passo 9, se aplicável
EOF
        
        # --- windowrules.conf (MELHORIA: Exemplos de PDFs) ---
        cat > "$config_dir/hypr/windowrules.conf" << EOF
# --- Regras de Janela (Exemplos) ---
# Gerado por pos_install.sh
# Veja https://wiki.hyprland.org/Configuring/Window-Rules/

# Flutuar mixer de áudio
windowrule = float,pavucontrol
windowrule = size 60% 60%,pavucontrol
windowrule = center,pavucontrol

# Flutuar diálogos do Thunar (copiar, preferências, etc)
windowrule = float,class:^(thunar)$,title:^(?!.*\/) # Janelas Thunar sem '/' no título
windowrule = float,class:^(Thunar)$,title:^(?!.*\/) 
windowrule = float,title:^(Transferência de Arquivos)$
windowrule = float,title:^(File Operation Progress)$
windowrule = float,title:^(Confirmar)$
windowrule = float,title:^(Renomear)$

# Não desligar tela ao assistir vídeos no MPV
windowrule = idleinhibit focus,class:^(mpv)$

# Exemplo: Abrir Firefox sempre no workspace 2
# windowrule = workspace 2,class:^(firefox)$

# Exemplo: Definir opacidade para o terminal Kitty
# windowrule = opacity 0.9 0.8,class:^(kitty)$

# Exemplo: Centralizar janela específica
# windowrule = float,class:^(meu-app-flutuante)$
# windowrule = center,class:^(meu-app-flutuante)$
# windowrule = size 800 600,class:^(meu-app-flutuante)$
EOF
        
        
        # --- kitty.conf (Terminal com Transparência) ---
        cat > "$config_dir/kitty/kitty.conf" << EOF
# --- Configuração do Kitty (Vidro) ---
# Gerado por pos_install.sh
font_size 12.0
# Font family (Exemplo: use 'kitty +list-fonts' para ver as disponíveis)
# font_family      JetBrainsMono Nerd Font Mono
# bold_font        auto
# italic_font      auto
# bold_italic_font auto

# Transparência e Blur
background_opacity 0.85 
# background_blur 10 # Descomente se quiser blur no Kitty (pode impactar performance)

# Tema (Exemplo Catppuccin Mocha)
# include themes/Catppuccin-Mocha.conf 
# (Baixe temas de https://github.com/kovidgoyal/kitty-themes)
EOF

        # --- waybar/config (Básica) ---
        cat > "$config_dir/waybar/config" << EOF
// -*- mode: json -*-
{
    // Gerado por pos_install.sh
    "layer": "top", // Waybar na camada superior
    "position": "top", // Waybar no topo da tela
    "height": 30, // Altura da Waybar
    // "width": 1280, // Descomente para largura fixa
    // "spacing": 4, // Descomente para espaçamento entre módulos

    // Escolha os módulos que deseja - veja https://github.com/Alexays/Waybar/wiki/Module
    "modules-left": ["hyprland/workspaces", "hyprland/mode", "hyprland/scratchpad"],
    "modules-center": ["hyprland/window"],
    "modules-right": ["tray", "pulseaudio", "network", "cpu", "memory", "temperature", "battery", "clock"],

    "hyprland/workspaces": {
        "disable-scroll": false,
        "all-outputs": true,
        "warp-on-scroll": false, // Evita que o mouse prenda ao rolar
        "format": "{icon}",
        "format-icons": {
            "1": "",
            "2": "",
            "3": "",
            "4": "",
            "5": "",
            "urgent": "",
            "focused": "",
            "default": ""
        }
    },
    "hyprland/window": {
        "format": "{}" // Mostra o título da janela ativa
        // "max-length": 50 // Limita o tamanho do título
    },
    "tray": {
        "icon-size": 18,
        "spacing": 10
    },
    "clock": {
        "format": "{:%H:%M | %d/%m/%Y}", // Formato 24h | Dia/Mês/Ano
        "tooltip-format": "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>"
    },
    "cpu": {
        "format": " {usage}%", // Ícone CPU + porcentagem
        "tooltip": true
    },
    "memory": {
        "format": " {}%" // Ícone RAM + porcentagem usada
    },
    "temperature": {
        // "thermal-zone": 2, // Descomente e ajuste se necessário
        // "hwmon-path": "/sys/class/hwmon/hwmon2/temp1_input", // Descomente e ajuste se necessário
        "critical-threshold": 80,
        "format-critical": "{temperatureC}°C ",
        "format": "{temperatureC}°C "
    },
    "battery": {
        "states": {
            "good": 95,
            "warning": 30,
            "critical": 15
        },
        "format": "{capacity}% {icon}",
        "format-charging": "{capacity}% ",
        "format-plugged": "{capacity}% ",
        "format-alt": "{time} {icon}",
        "format-icons": ["", "", "", "", ""]
    },
    "network": {
        "format-wifi": " {essid}", // Ícone Wifi + Nome da Rede
        "format-ethernet": "󰈀 {ifname}", // Ícone Ethernet + Interface
        "tooltip-format": "{ifname} via {gwaddr} ",
        "format-linked": "{ifname} (Não Conectado)",
        "format-disconnected": "󰖪 Desconectado",
        "format-alt": "{ifname}: {ipaddr}/{cidr}"
    },
    "pulseaudio": {
        "format": "{volume}% {icon} {format_source}",
        "format-bluetooth": "{volume}% {icon} {format_source}",
        "format-bluetooth-muted": " {icon} {format_source}",
        "format-muted": " {format_source}",
        "format-source": "{volume}% ",
        "format-source-muted": "",
        "format-icons": {
            "headphone": "",
            "hands-free": "󰋎",
            "headset": "󰋎",
            "phone": "",
            "portable": "",
            "car": "",
            "default": ["", "", ""]
        },
        "on-click": "pavucontrol" // Abre o pavucontrol ao clicar
    }
}
EOF

        # --- waybar/style.css (Tema de Vidro) ---
        cat > "$config_dir/waybar/style.css" << EOF
/* --- Estilo Waybar (Vidro) --- */
/* Gerado por pos_install.sh */
* {
    /* Use a fonte que você instalou ou uma padrão como Cantarell */
    font-family: "Noto Sans", FontAwesome, sans-serif; 
    font-size: 14px;
    border: none;
    border-radius: 0;
    min-height: 0;
    margin: 0 2px; /* Pequeno espaço entre módulos */
}

window#waybar {
    /* Fundo de vidro: cor RGBA (preto com opacidade) */
    background-color: rgba(26, 27, 38, 0.7); 
    border-bottom: 1px solid rgba(100, 114, 125, 0.5); /* Linha sutil abaixo */
    color: #cdd6f4; /* Cor do texto padrão */
    transition-property: background-color;
    transition-duration: .5s;
}

window#waybar.hidden {
    opacity: 0.2;
}

#workspaces button {
    padding: 0 8px;
    background-color: transparent;
    color: #a6adc8; /* Cor dos workspaces inativos */
    /* Use box-shadow para sublinhado sutil */
    box-shadow: inset 0 -3px transparent; 
}

#workspaces button:hover {
    background: rgba(0, 0, 0, 0.2);
    box-shadow: inset 0 -3px #cdd6f4; /* Sublinhado ao passar o mouse */
}

#workspaces button.focused {
    color: #cdd6f4; /* Cor do workspace ativo */
    box-shadow: inset 0 -3px #89b4fa; /* Sublinhado azul para ativo */
}

#workspaces button.urgent {
    color: #f38ba8; /* Cor vermelha para urgente */
    box-shadow: inset 0 -3px #f38ba8; /* Sublinhado vermelho */
}

/* Estilos para outros módulos (ajuste cores conforme seu tema) */
#clock,
#battery,
#cpu,
#memory,
#temperature,
#network,
#pulseaudio,
#tray,
#window, 
#mode {
    padding: 0 10px;
    color: #cdd6f4;
}

#window {
    font-weight: bold;
}

#battery.critical:not(.charging) {
    color: #f38ba8; /* Vermelho */
}

/* Adicione mais estilos específicos se desejar */
/* Exemplo: Cor diferente para rede conectada */
#network:not(.disconnected) {
     color: #a6e3a1; /* Verde */
}

/* Exemplo: Cor diferente para áudio mudo */
#pulseaudio.muted {
    color: #f5c2e7; /* Rosa */
}
EOF

        # --- wofi/style.css (Tema de Vidro com Bordas Redondas) ---
        cat > "$config_dir/wofi/style.css" << EOF
/* --- Estilo Wofi (Vidro) --- */
/* Gerado por pos_install.sh */
window {
    margin: 0px;
    background-color: rgba(26, 27, 38, 0.8); /* Fundo de vidro */
    border: 1px solid #7f849c; /* Borda sutil */
    border-radius: 10px; /* Bordas arredondadas */
    font-family: "Noto Sans", sans-serif;
    font-size: 14px;
    color: #cdd6f4; /* Cor do texto */
}

#input {
    margin: 5px;
    border: none;
    padding: 8px 10px;
    background-color: rgba(205, 214, 244, 0.1); /* Fundo levemente claro */
    color: #cdd6f4;
    border-radius: 5px;
}

#inner-box {
    margin: 5px;
    border: none;
    background-color: transparent;
}

#outer-box {
    margin: 5px;
    border: none;
    background-color: transparent;
}

#scroll {
    margin: 0px;
    border: none;
}

#text {
    margin: 5px;
    border: none;
    color: #cdd6f4;
} 

#entry:selected {
    background-color: rgba(137, 180, 250, 0.3); /* Fundo azul claro ao selecionar */
    border-radius: 5px;
}
EOF

        # --- mako/config (Tema de Vidro) ---
        cat > "$config_dir/mako/config" << EOF
# --- Configuração Mako (Vidro) ---
# Gerado por pos_install.sh
font=Noto Sans 10
default-timeout=5000
padding=10
border-size=1
border-radius=5
border-color=#7f849c # Cor da borda sutil

# --- Tema de Vidro ---
background-color=rgba(26, 27, 38, 0.8) # Fundo escuro transparente
text-color=#cdd6f4 # Cor do texto
EOF
        
        dialog --title "Configurações Concluídas" \
               --msgbox "Arquivos de configuração com tema de 'vidro' criados para:\n\n- Hyprland (+ Env Vars & Window Rules)\n- Kitty (Terminal)\n- Waybar (Barra de Status)\n- Wofi (Lançador)\n- Mako (Notificações)\n\nIMPORTANTE: Para aplicar o tema em aplicativos GTK (como o Thunar), instale 'lxappearance' e um tema GTK (como 'adw-gtk3') no Passo 10." 17 70
    fi
}

# --- 6. Auto-Detectar Monitores ---
setup_monitors() {
    local config_file="$HOME/.config/hypr/monitors.conf"
    
    # Criar o arquivo se não existir (caso o passo 4 seja pulado)
    mkdir -p "$(dirname "$config_file")"
    touch "$config_file"
    
    local monitors_list=()
    local raw_monitors=()
    
    dialog --infobox "Detectando monitores..." 4 50
    sleep 1 # Pequena pausa para o usuário ler

    # Tenta obter nomes dos monitores via hyprctl se Hyprland já estiver rodando
    if pgrep -x Hyprland > /dev/null && command_exists hyprctl; then
         while IFS= read -r line; do
            raw_monitors+=("$line")
         done < <(hyprctl monitors -j | jq -r '.[].name')
    else 
        # Fallback para /sys/class/drm se Hyprland não estiver rodando
         while IFS= read -r line; do
            raw_monitors+=("$line")
         done < <(ls /sys/class/drm/ 2>/dev/null | grep -E 'card[0-9]+-(eDP|DP|HDMI|VGA)-[0-9]+' | sed 's/card[0-9]+-//')
    fi


    if [ ${#raw_monitors[@]} -eq 0 ]; then
        dialog --msgbox "Nenhum monitor foi detectado.\n\nVerifique se o Hyprland está rodando ou se há saídas conectadas em /sys/class/drm/.\n\nNenhuma configuração foi salva." 10 70
        return 1
    fi

    for mon in "${raw_monitors[@]}"; do
        # Marca eDP como 'on' por padrão, assumindo ser o interno
        local default_status="off"
        if [[ "$mon" == *"eDP"* ]]; then default_status="on"; fi
        monitors_list+=("$mon" "$mon" "$default_status")
    done

    local monitor_interno
    monitor_interno=$(dialog --backtitle "$BACKTITLE" --title "Auto-Detectar Monitores (1/2)" \
                             --radiolist "Detectamos: ${raw_monitors[*]}.\n\nQual é o seu monitor PRINCIPAL/INTERNO? (Use Espaço)" 15 70 $((${#raw_monitors[@]} + 3)) \
                             "${monitors_list[@]}" \
                             --output-fd 1)
    
    if [ $? -ne 0 ]; then return; fi # Cancelou

    local monitores_externos_list=()
    for mon in "${raw_monitors[@]}"; do
        if [ "$mon" != "$monitor_interno" ]; {
            # Mantém externos ligados por padrão
             monitores_externos_list+=("$mon" "Ativar $mon" "on")
        }
    done

    local monitores_externos=()
    if [ ${#monitores_externos_list[@]} -gt 0 ]; then
        monitores_externos=$(dialog --backtitle "$BACKTITLE" --title "Auto-Detectar Monitores (2/2)" \
                                    --checklist "Selecione os monitores EXTERNOS que deseja ativar:" 15 70 $((${#monitores_externos_list[@]} / 3 + 3)) \
                                    "${monitores_externos_list[@]}" \
                                    --output-fd 1)
        if [ $? -ne 0 ]; then return; fi # Cancelou
    fi

    echo "--- Log: Configurando Monitores ---" > "$LOG_FILE"
    {
        echo "# --- Configuração de Monitores (Gerado Automaticamente) ---"
        echo "# Veja https://wiki.hyprland.org/Configuring/Monitors/"
        echo "monitor=$monitor_interno,preferred,auto,1" # Principal sempre ligado
        
        local final_msg="Monitor principal '$monitor_interno' configurado como 'preferred,auto,1'."
        
        local externos_ativos=0
        if [ -n "$monitores_externos" ]; then
            final_msg+="\n\nMonitores externos ATIVADOS:"
            for ext_mon in $monitores_externos; do
                local clean_mon=$(echo "$ext_mon" | tr -d '"')
                echo "monitor=$clean_mon,preferred,auto,1"
                final_msg+="\n- $clean_mon (preferred,auto,1)"
                externos_ativos=$((externos_ativos + 1))
            done
        fi
        
        # Adiciona monitores detectados mas NÃO selecionados como desabilitados
        local tem_desabilitados=false
        for mon in "${raw_monitors[@]}"; do
             if [ "$mon" != "$monitor_interno" ] && ! [[ " ${monitores_externos[*]} " =~ " ${mon} " ]]; then
                 if [ $tem_desabilitados = false ]; then
                    final_msg+="\n\nMonitores externos DESABILITADOS:"
                    tem_desabilitados=true
                 fi
                 echo "monitor=$mon,disable"
                 final_msg+="\n- $mon (disable)"
             fi
        done

        # Adiciona exemplo de workspaces se houver monitor externo ativo
        if [ "$externos_ativos" -gt 0 ]; then
            echo ""
            echo "# --- Exemplo de Workspaces por Monitor ---"
            echo "# Descomente e ajuste conforme necessário"
            echo "# workspace=1,monitor:$monitor_interno"
            echo "# workspace=6,monitor:$(echo "$monitores_externos" | tr -d '"' | head -n 1)"
        fi
        
    } > "$config_file"
    
    dialog --msgbox "$final_msg\n\nArquivo salvo em '$config_file'." $(($externos_ativos + $tem_desabilitados + 10)) 70
}


# --- 7. Funções de Notebook ---
fn_tlp_menu() {
    echo "--- Log: Configurando TLP ---" > "$LOG_FILE"
    if ! install_pacman_packages "tlp"; then
        show_log "Log de Erro (TLP)"
        return 1
    fi
    
    local tlp_choice
    tlp_choice=$(dialog --backtitle "$BACKTITLE" --title "Limite de Carga (TLP)" \
                        --menu "Escolha um limite para parar de carregar a bateria:" 15 70 5 \
                        "1" "80% (Recomendado para longevidade)" \
                        "2" "85%" \
                        "3" "90%" \
                        "4" "95%" \
                        "5" "Padrão (100% / Desativar limite)" \
                        --output-fd 1)
                        
    if [ $? -ne 0 ]; then return; fi # Cancelou

    local start_val=75
    local stop_val=80
    local tlp_config_file="/etc/tlp.conf"

    # Garante que as linhas existem antes de usar sed (evita erros se tlp.conf for mínimo)
    if ! grep -q "START_CHARGE_THRESH_BAT0" "$tlp_config_file"; then
        echo "#START_CHARGE_THRESH_BAT0=75" | sudo tee -a "$tlp_config_file" > /dev/null
    fi
    if ! grep -q "STOP_CHARGE_THRESH_BAT0" "$tlp_config_file"; then
        echo "#STOP_CHARGE_THRESH_BAT0=80" | sudo tee -a "$tlp_config_file" > /dev/null
    fi

    case "$tlp_choice" in
        1) start_val=75; stop_val=80 ;;
        2) start_val=80; stop_val=85 ;;
        3) start_val=85; stop_val=90 ;;
        4) start_val=90; stop_val=95 ;;
        5) 
            dialog --infobox "Redefinindo para o padrão (100%)..." 4 50
            # Comenta as linhas para desativar
            sudo sed -i -E "s/^(START_CHARGE_THRESH_BAT0=.*)/#\1/g" "$tlp_config_file" &>> "$LOG_FILE"
            sudo sed -i -E "s/^(STOP_CHARGE_THRESH_BAT0=.*)/#\1/g" "$tlp_config_file" &>> "$LOG_FILE"
            sudo systemctl enable tlp &>> "$LOG_FILE" # Garante que está ativo
            sudo systemctl restart tlp &>> "$LOG_FILE" # Aplica a mudança
            dialog --msgbox "Limite de carga TLP desativado (Padrão 100%).\n\nServiço TLP ativado e reiniciado." 8 60
            return
            ;;
    esac

    dialog --infobox "Aplicando limite de ${stop_val}%..." 4 50
    # Descomenta e define os valores
    sudo sed -i -E "s/^#?(START_CHARGE_THRESH_BAT0=.*)/START_CHARGE_THRESH_BAT0=$start_val/g" "$tlp_config_file" &>> "$LOG_FILE"
    sudo sed -i -E "s/^#?(STOP_CHARGE_THRESH_BAT0=.*)/STOP_CHARGE_THRESH_BAT0=$stop_val/g" "$tlp_config_file" &>> "$LOG_FILE"
    sudo systemctl enable tlp &>> "$LOG_FILE" # Garante que está ativo
    sudo systemctl restart tlp &>> "$LOG_FILE" # Aplica a mudança
    
    local tlp_msg="TLP configurado para parar a carga em ${stop_val}%.\n\nArquivo '/etc/tlp.conf' foi modificado.\n\nServiço TLP ativado e reiniciado."
    if command_exists yay; then
        tlp_msg+="\n\nDICA: Instale 'tlp-rdw' (via Passo 10) para gerenciar rádio-frequência."
    fi
    dialog --title "TLP Configurado" --msgbox "$tlp_msg" 14 70
}

fn_lid_menu() {
    local logind_config_file="/etc/systemd/logind.conf"
    local choice_bateria
    local choice_ac
    local action_bateria
    local action_ac

    choice_bateria=$(dialog --backtitle "$BACKTITLE" --title "Ação ao Fechar a Tampa (1/2)" \
                            --menu "O que fazer ao fechar a tampa (NA BATERIA):" 15 70 4 \
                            "1" "Suspender (Sleep)" \
                            "2" "Ignorar (Não fazer nada)" \
                            "3" "Hibernar (Requer config. extra!)" \
                            "4" "Desligar" \
                            --output-fd 1)
    if [ $? -ne 0 ]; then return; fi
    case "$choice_bateria" in
        1) action_bateria="suspend" ;;
        2) action_bateria="ignore" ;;
        3) action_bateria="hibernate"; dialog --msgbox "AVISO: Hibernar requer configuração manual de SWAP e Kernel. Veja a Arch Wiki." 8 60 ;;
        4) action_bateria="poweroff" ;;
    esac

    choice_ac=$(dialog --backtitle "$BACKTITLE" --title "Ação ao Fechar a Tampa (2/2)" \
                       --menu "O que fazer ao fechar a tampa (CONECTADO):" 15 70 4 \
                       "1" "Ignorar (Não fazer nada)" \
                       "2" "Suspender (Sleep)" \
                       "3" "Hibernar (Requer config. extra!)" \
                       "4" "Desligar" \
                       --output-fd 1)
    if [ $? -ne 0 ]; then return; fi
    case "$choice_ac" in
        1) action_ac="ignore" ;;
        2) action_ac="suspend" ;;
        3) action_ac="hibernate"; dialog --msgbox "AVISO: Hibernar requer configuração manual de SWAP e Kernel. Veja a Arch Wiki." 8 60 ;;
        4) action_ac="poweroff" ;;
    esac

    dialog --infobox "Aplicando configurações da tampa..." 4 50
    echo "--- Log: Configurando Ações da Tampa ---" > "$LOG_FILE"
    
    # Garante que as linhas existem antes de usar sed
     if ! grep -q "HandleLidSwitch=" "$logind_config_file"; then
        echo "#HandleLidSwitch=suspend" | sudo tee -a "$logind_config_file" > /dev/null
    fi
     if ! grep -q "HandleLidSwitchExternalPower=" "$logind_config_file"; then
        echo "#HandleLidSwitchExternalPower=suspend" | sudo tee -a "$logind_config_file" > /dev/null
    fi

    # Descomenta e define os valores
    sudo sed -i -E "s/^#?(HandleLidSwitch=.*)/HandleLidSwitch=$action_bateria/g" "$logind_config_file" &>> "$LOG_FILE"
    sudo sed -i -E "s/^#?(HandleLidSwitchExternalPower=.*)/HandleLidSwitchExternalPower=$action_ac/g" "$logind_config_file" &>> "$LOG_FILE"
    
    sudo systemctl restart systemd-logind &>> "$LOG_FILE"
    
    dialog --msgbox "Configurações de tampa aplicadas:\n\n- Na Bateria: $action_bateria\n- Conectado: $action_ac\n\nArquivo '$logind_config_file' modificado.\nServiço 'systemd-logind' reiniciado." 14 70
}

setup_laptop() {
    local laptop_choice
    laptop_choice=$(dialog --backtitle "$BACKTITLE" --title "Configurações de Notebook" \
                           --menu "Selecione uma otimização para Notebook:" 15 70 4 \
                           "1" "Configurar TLP (Limite de Bateria)" \
                           "2" "Instalar Controle de Brilho (brightnessctl)" \
                           "3" "Configurar Ação de Fechar a Tampa" \
                           "4" "Voltar ao Menu Principal" \
                           --output-fd 1)
    
    case "$laptop_choice" in
        1)
            fn_tlp_menu
            ;;
        2)
            dialog --yesno "Instalar 'brightnessctl' para ajustar o brilho da tela (via atalhos de teclado)?" 7 60
            if [ $? -eq 0 ]; then
                echo "--- Log: Instalando brightnessctl ---" > "$LOG_FILE"
                if install_pacman_packages "brightnessctl"; then
                    if ! groups "$USER" | grep -q video; then
                         sudo usermod -aG video "$USER" &>> "$LOG_FILE"
                         dialog --msgbox "'brightnessctl' instalado.\n\nVocê foi adicionado ao grupo 'video'.\n\nIMPORTANTE: Você precisa SAIR e LOGAR NOVAMENTE para que a permissão de brilho funcione." 12 70
                    else
                         dialog --msgbox "'brightnessctl' instalado.\n\n(Você já estava no grupo 'video')" 8 60
                    fi
                fi
                show_log "Log de Instalação (brightnessctl)"
            fi
            ;;
        3)
            fn_lid_menu
            ;;
        4)
            return
            ;;
        *) # Trata Esc ou Cancel
            return
            ;;
    esac
    setup_laptop # Volta ao menu de notebook
}

# --- 8. Instalar YAY (AUR Helper) ---
install_yay() {
    if command_exists yay; then
        dialog --msgbox "'yay' (AUR Helper) já está instalado." 6 50
        return
    fi
    
    dialog --backtitle "$BACKTITLE" --title "Instalar 'yay' (Opcional)" \
           --yesno "O 'yay' é um (AUR Helper).\nEle permite instalar pacotes da comunidade (não-oficiais).\n\n(Obrigatório para usuários NVIDIA)\n\nDeseja instalá-lo agora?" 12 70
           
    if [ $? -eq 0 ]; then
        echo "--- Log: Instalando dependências para 'yay' (git, base-devel) ---" > "$LOG_FILE"
        # Instala 'base-devel' que contém 'make', 'gcc', etc.
        if ! install_pacman_packages "git" "base-devel"; then
            dialog --msgbox "Erro ao instalar dependências (git, base-devel)." 6 50
            show_log "Log de Erro (yay-deps)"
            return 1
        fi

        local temp_yay_dir="/tmp/yay-install-$(date +%s)"
        mkdir -p "$temp_yay_dir"
        cd "$temp_yay_dir" || { dialog --msgbox "Erro ao criar diretório temporário para yay." 6 50; return 1; }
        
        echo "--- Log: Clonando 'yay' ---" >> "$LOG_FILE"
        git clone https://aur.archlinux.org/yay.git . &>> "$LOG_FILE" # Clona no diretório atual
        if [ $? -ne 0 ]; then
            dialog --msgbox "Erro ao clonar 'yay'. Verifique sua conexão e se o git foi instalado." 7 60
            show_log "Log de Erro (yay-clone)"
            cd ~; rm -rf "$temp_yay_dir" # Limpa
            return 1
        fi
        
        echo "--- Log: Compilando 'yay' (makepkg) ---" >> "$LOG_FILE"
        # Roda makepkg como usuário normal
        makepkg -si --noconfirm &>> "$LOG_FILE"
        local makepkg_exit_code=$? # Captura código de saída
        
        cd ~ 
        rm -rf "$temp_yay_dir" # Limpa o diretório temporário
        
        if [ $makepkg_exit_code -ne 0 ]; then
            dialog --msgbox "Erro ao compilar 'yay'. Verifique o log para detalhes sobre dependências faltantes ou erros de compilação." 8 70
            show_log "Log de Erro (yay-makepkg)"
            return 1
        fi
        
        dialog --msgbox "'yay' foi instalado com sucesso!" 6 50
        # show_log "Log de Instalação (yay)" # Geralmente não necessário se deu certo
    fi
}

# --- 9. Instalar Drivers Gráficos ---
install_drivers() {
    echo "--- Log: Instalando Drivers Gráficos ---" > "$LOG_FILE"
    
    dialog --backtitle "$BACKTITLE" --title "Drivers Gráficos e Aceleração" \
           --msgbox "O driver base 'mesa' (para Intel e AMD) já deve ter sido instalado como dependência (Passo 2).\n\nEsta etapa oferece pacotes adicionais para aceleração de hardware (VA-API/Vulkan) e drivers proprietários da NVIDIA." 10 70

    dialog --backtitle "$BACKTITLE" --title "Drivers Gráficos e Aceleração" \
           --checklist "Selecione os pacotes de drivers/aceleração:" 20 70 5 \
           "intel_amd_extras" "Aceleração VA-API/Vulkan (Intel/AMD)" on \
           "nvidia_proprietary" "Drivers Proprietários NVIDIA" off \
           2> "$CHOICES_FILE"

    if [ $? -ne 0 ]; then rm -f "$CHOICES_FILE"; return; fi # Cancelou

    choices=$(cat "$CHOICES_FILE" | tr -d '"')
    local install_ok=true
    local nvidia_installed=false

    if [[ $choices == *"intel_amd_extras"* ]]; then
        echo "--- Instalando extras Intel/AMD (VA-API/Vulkan) ---" >> "$LOG_FILE"
        # libva-mesa-driver é dependência do mesa
        local intel_amd_pkgs=("mesa-vdpau" "vulkan-intel" "vulkan-radeon" "libva-utils") # libva-utils para teste (vainfo)
        if ! install_pacman_packages "${intel_amd_pkgs[@]}"; then
            install_ok=false
        fi
    fi
    
    if [[ $choices == *"nvidia_proprietary"* ]]; then
        echo "--- Instalando drivers NVIDIA (Proprietários) ---" >> "$LOG_FILE"
        local nvidia_pkgs=("nvidia-dkms" "linux-headers") # libva-nvidia-driver é AUR
        if ! install_pacman_packages "${nvidia_pkgs[@]}"; then
            install_ok=false
        else
            nvidia_installed=true # Driver base instalado
            local nvidia_msg="Drivers NVIDIA (Pacman: nvidia-dkms, headers) instalados.\n\nPRÓXIMOS PASSOS OBRIGATÓRIOS:\n1. Instale o 'yay' (Passo 8), se ainda não o fez.\n2. Execute este Passo 9 novamente para instalar os pacotes AUR.\n3. Adicione 'nvidia_drm.modeset=1' aos parâmetros do kernel."
            
            if command_exists yay; then
                dialog --yesno "Drivers NVIDIA base (Pacman) instalados.\n\n'yay' detectado. Deseja instalar os pacotes AUR essenciais?\n(hyprland-nvidia-dkms, libva-nvidia-driver-git, etc)" 15 70
                if [ $? -eq 0 ]; then
                    local nvidia_aur_pkgs=("hyprland-nvidia-dkms" "libva-nvidia-driver-git" "egl-wayland") # egl-wayland é crucial
                    if ! install_aur_packages "${nvidia_aur_pkgs[@]}"; then
                        install_ok=false
                    else
                        # --- AJUSTE NVIDIA: Adicionar variáveis de ambiente ---
                        echo "--- Adicionando variáveis de ambiente NVIDIA ---" >> "$LOG_FILE"
                        local env_file="$HOME/.config/hypr/environment.conf"
                        if [ ! -f "$env_file" ]; then
                             dialog --msgbox "ERRO: '$env_file' não encontrado.\n\nExecute o 'Passo 4' primeiro para criar os arquivos de configuração." 8 70
                             install_ok=false # Marca como erro
                        else
                            # Verifica se já existem para não duplicar
                            if ! grep -q "# --- Variáveis NVIDIA ---" "$env_file"; then
                                echo -e "\n# --- Variáveis NVIDIA (Adicionadas pelo Assistente) ---" >> "$env_file"
                                echo "env = LIBVA_DRIVER_NAME,nvidia" >> "$env_file"
                                echo "env = __GLX_VENDOR_LIBRARY_NAME,nvidia" >> "$env_file"
                                echo "env = WLR_NO_HARDWARE_CURSORS,1" >> "$env_file"
                                echo "env = NVD_BACKEND,direct" >> "$env_file" 
                                # GBM_BACKEND não é mais recomendado pela wiki Hyprland para GBM
                                # echo "env = GBM_BACKEND,nvidia-drm" >> "$env_file" 
                                echo "Variáveis de ambiente NVIDIA salvas em '$env_file'." >> "$LOG_FILE"
                            else
                                echo "Variáveis NVIDIA já presentes em '$env_file'." >> "$LOG_FILE"
                            fi
                            # --- MELHORIA: Mensagem final NVIDIA mais clara ---
                            dialog --title "NVIDIA Quase Pronto!" \
                                   --msgbox "Pacotes NVIDIA (Pacman e AUR) instalados!\nVariáveis de ambiente configuradas em '$env_file'.\n\n!! AÇÃO MANUAL OBRIGATÓRIA !!\n\nAntes de reiniciar, você PRECISA adicionar:\n'nvidia_drm.modeset=1'\naos parâmetros do seu Kernel.\n\nExemplo (GRUB): Edite '/etc/default/grub', adicione à linha GRUB_CMDLINE_LINUX_DEFAULT e rode 'sudo grub-mkconfig -o /boot/grub/grub.cfg'.\n\nExemplo (systemd-boot): Edite '/boot/loader/entries/arch.conf', adicione à linha 'options'.\n\nConsulte a Arch Wiki ('Kernel parameters') se tiver dúvidas." 22 75
                        fi
                    fi
                fi
            else
                dialog --msgbox "$nvidia_msg\n\n'yay' não detectado. Instale o 'yay' (Passo 8) e rode esta etapa novamente para instalar os pacotes AUR necessários (incluindo a versão correta do Hyprland para NVIDIA)." 16 70
                install_ok=false # Marca como erro parcial pois faltou o AUR
            fi
        fi
    fi
    
    # Mensagem final genérica
    if [ $install_ok = true ] && [ -n "$choices" ] && [ $nvidia_installed = false ]; then
        dialog --msgbox "Instalação de drivers/aceleração concluída." 6 60
    elif [ $install_ok = false ]; then
         dialog --msgbox "Instalação de drivers concluída com AVISOS ou ERROS.\n\nVerifique o log para detalhes." 8 60
    elif [ -z "$choices" ]; then
         dialog --msgbox "Nenhum driver/aceleração selecionado." 6 50
    fi

    # Só mostra o log se algo foi selecionado ou houve erro
    if [ $install_ok = false ] || [ -n "$choices" ]; then
        show_log "Log de Instalação (Drivers)"
    fi
    rm -f "$CHOICES_FILE"
}

# --- 10. Instalar Aplicativos Adicionais ---
install_extra_apps() {
    echo "--- Log: Instalação de Aplicativos Adicionais ---" > "$LOG_FILE"
    
    # --- Pacotes Pacman ---
    dialog --backtitle "$BACKTITLE" --title "Aplicativos Adicionais (Oficiais)" \
           --checklist "Selecione aplicativos (Pacman) para instalar:" 20 70 15 \
           "gimp" "Editor de imagens (Photoshop FOSS)" off \
           "krita" "Pintura digital" off \
           "inkscape" "Editor de vetores (Illustrator FOSS)" off \
           "blender" "Software de modelagem 3D" off \
           "vlc" "Player de mídia (reprod. tudo)" off \
           "mpv" "Player de mídia (leve e minimalista)" on \
           "obs-studio" "Gravação e streaming de tela" off \
           "ardour" "DAW (Estação de Áudio Digital)" off \
           "wine" "Camada de compatibilidade (Windows)" off \
           "chromium" "Navegador Web (Base do Chrome)" off \
           "neovim" "Editor de texto avançado (Vim)" off \
           "btop" "Monitor de sistema avançado (hTop++)" on \
           # --- MELHORIA: GTK Theme ---
           "adw-gtk3" "Tema GTK moderno (para Thunar, etc)" on \
           "lxappearance" "Ferramenta para configurar tema GTK" on \
           2> "$CHOICES_FILE"
           
    local pacman_choices=""
    local install_ok=true
    if [ $? -eq 0 ]; then
        pacman_choices=$(cat "$CHOICES_FILE" | tr -d '"')
        if [ -n "$pacman_choices" ]; then
            echo "--- Instalando pacotes Pacman: $pacman_choices ---" >> "$LOG_FILE"
            if ! install_pacman_packages $pacman_choices; then
                install_ok=false
            fi
        fi
    fi
    
    # --- Pacotes AUR ---
    if ! command_exists yay; then
        dialog --msgbox "O 'yay' não está instalado, pulando seleção de apps do AUR.\n\nInstale o 'yay' (Passo 8) e rode esta opção novamente." 8 70
        rm -f "$CHOICES_FILE"
        if [ $install_ok = true ] && [ -n "$pacman_choices" ]; then
             dialog --msgbox "Instalação de aplicativos (Pacman) concluída." 6 60
             show_log "Log de Instalação (Aplicativos)"
        elif [ $install_ok = false ]; then
             dialog --msgbox "Instalação de aplicativos (Pacman) concluída com ERROS.\nVerifique o log." 8 60
             show_log "Log de Instalação (Aplicativos)"
        fi
        return
    fi
    
    dialog --backtitle "$BACKTITLE" --title "Aplicativos Adicionais (AUR)" \
           --checklist "Selecione aplicativos (AUR) para instalar:" 20 70 7 \
           "visual-studio-code-bin" "VSCode (binário da Microsoft)" off \
           "brave-bin" "Navegador Brave (binário)" off \
           "reaper-bin" "DAW de Áudio (Binário)" off \
           "obsidian" "Aplicativo de notas (Markdown)" off \
           "nwg-look" "Editor de temas GTK (alternativa ao lxappearance)" off \
           "sddm-config-editor-git" "Editor gráfico para tela de login" off \
           "tlp-rdw" "Otimização de rádio p/ notebook (TLP)" off \
           2> "$CHOICES_FILE"
           
    local aur_choices=""
    if [ $? -eq 0 ]; then
        aur_choices=$(cat "$CHOICES_FILE" | tr -d '"')
        if [ -n "$aur_choices" ]; then
            echo "--- Instalando pacotes AUR: $aur_choices ---" >> "$LOG_FILE"
            if ! install_aur_packages $aur_choices; then
                install_ok=false
            fi
        fi
    fi
    
    if [ $install_ok = true ]; then
        if [ -n "$pacman_choices" ] || [ -n "$aur_choices" ]; then
            dialog --msgbox "Instalação de aplicativos adicionais concluída." 6 60
        else
            dialog --msgbox "Nenhum aplicativo selecionado." 6 50
        fi
    else
         dialog --msgbox "Instalação de aplicativos concluída com AVISOS ou ERROS.\n\nVerifique o log." 8 60
    fi
    
    # Só mostra log se algo foi selecionado ou houve erro
    if [ $install_ok = false ] || [ -n "$pacman_choices" ] || [ -n "$aur_choices" ]; then
        show_log "Log de Instalação (Aplicativos)"
    fi
    rm -f "$CHOICES_FILE"
}

# --- 11. Configurar Serviços (Login, Bluetooth) ---
setup_services() {
    dialog --backtitle "$BACKTITLE" --title "Serviços Adicionais" \
           --checklist "Selecione os serviços para instalar e ativar:" 15 70 2 \
           "sddm" "Tela de Login Gráfica (Login Manager)" off \
           "bluetooth" "Suporte a Bluetooth (bluez + blueman)" off \
           2> "$CHOICES_FILE"
           
    if [ $? -eq 0 ]; then
        choices=$(cat "$CHOICES_FILE" | tr -d '"')
        echo "--- Log: Configurando Serviços ---" > "$LOG_FILE"
        local service_msg=""
        local install_ok=true
        
        if [[ $choices == *"sddm"* ]]; then
            echo "--- Instalando e ativando SDDM ---" >> "$LOG_FILE"
            if install_pacman_packages "sddm" "sddm-qt6"; then
                sudo systemctl enable sddm &>> "$LOG_FILE"
                
                # Configurar SDDM para Wayland
                echo "--- Configurando SDDM para Wayland ---" >> "$LOG_FILE"
                sudo mkdir -p /etc/sddm.conf.d
                echo -e "[General]\nDisplayServer=wayland\nInputMethod=\n" | sudo tee /etc/sddm.conf.d/10-wayland.conf &>> "$LOG_FILE"
                
                service_msg+="SDDM instalado e ativado para Wayland.\nNa próxima reinicialização, você terá uma tela de login gráfica.\n\n"

                # Perguntar sobre tema (se yay estiver instalado)
                if command_exists yay; then
                    dialog --yesno "SDDM configurado para Wayland.\n\nDeseja instalar e ativar um tema de 'vidro' (sddm-blur-git) via AUR?" 10 70
                    if [ $? -eq 0 ]; then
                        if install_aur_packages "sddm-blur-git"; then
                            echo "--- Configurando tema SDDM (blur) ---" >> "$LOG_FILE"
                            sudo mkdir -p /etc/sddm.conf.d
                            echo -e "[Theme]\nCurrent=blur\n" | sudo tee /etc/sddm.conf.d/20-theme.conf &>> "$LOG_FILE"
                            service_msg+="Tema 'sddm-blur-git' instalado e ativado.\n"
                        else
                            install_ok=false
                        fi
                    fi
                fi
            else
                 install_ok=false
            fi
        fi
        
        if [[ $choices == *"bluetooth"* ]]; then
            echo "--- Instalando e ativando Bluetooth ---" >> "$LOG_FILE"
            if install_pacman_packages "bluez" "bluez-utils" "blueman"; then
                sudo systemctl enable bluetooth &>> "$LOG_FILE"
                service_msg+="Bluetooth instalado e ativado.\nReinicie para usar o blueman-manager.\n"
            else
                install_ok=false
            fi
        fi
        
        # Mensagem final
        if [ $install_ok = true ]; then
            if [ -n "$choices" ]; then
                dialog --msgbox "$service_msg" 15 70
            else
                dialog --msgbox "Nenhum serviço selecionado." 6 50
            fi
        else
            dialog --msgbox "Configuração de serviços concluída com AVISOS ou ERROS.\n\n$service_msg\nVerifique o log." 18 70
        fi

        # Só mostra log se algo foi selecionado ou houve erro
        if [ $install_ok = false ] || [ -n "$choices" ]; then
            show_log "Log de Configuração (Serviços)"
        fi
    fi
    rm -f "$CHOICES_FILE"
}

# --- 12. Limpeza do Sistema ---
system_cleanup() {
    dialog --backtitle "$BACKTITLE" --title "Limpeza do Sistema" \
           --yesno "Deseja realizar uma limpeza completa do sistema?\n\nIsso irá:\n1. Remover pacotes órfãos (não necessários)\n2. Limpar TODO o cache de pacotes (Pacman e Yay)\n\n(Recomendado para liberar espaço em disco)" 12 70
           
    if [ $? -eq 0 ]; then
        echo "--- Log: Limpeza do Sistema ---" > "$LOG_FILE"
        local cleanup_msg=""
        
        # 1. Remover órfãos
        echo "--- Removendo pacotes órfãos ---" >> "$LOG_FILE"
        orphans=$(pacman -Qtdq)
        if [ -n "$orphans" ]; then
            dialog --infobox "Removendo pacotes órfãos..." 4 50
            sudo pacman -Rns "$orphans" --noconfirm &>> "$LOG_FILE"
            cleanup_msg+="Pacotes órfãos removidos.\n"
        else
            echo "Nenhum órfão encontrado." >> "$LOG_FILE"
            cleanup_msg+="Nenhum pacote órfão encontrado.\n"
        fi
        
        # 2. Limpar cache do Pacman
        echo "--- Limpando cache do Pacman ---" >> "$LOG_FILE"
        dialog --infobox "Limpando cache do Pacman..." 4 50
        sudo pacman -Scc --noconfirm &>> "$LOG_FILE"
        cleanup_msg+="Cache do Pacman limpo.\n"
        
        # 3. Limpar cache do Yay
        if command_exists yay; then
            echo "--- Limpando cache do Yay ---" >> "$LOG_FILE"
            dialog --infobox "Limpando cache do Yay..." 4 50
            yay -Scc --noconfirm &>> "$LOG_FILE"
            cleanup_msg+="Cache do Yay limpo.\n"
        fi
        
        dialog --msgbox "Limpeza do sistema concluída.\n\n$cleanup_msg" 10 60
        show_log "Log de Limpeza do Sistema"
    fi
}

# --- 13. Desinstalar Pacotes ---
uninstall_packages() {
    # Lista mestre de todos os pacotes que este script pode instalar
    local master_pkg_list=(
        hyprland hyprland-nvidia-dkms kitty micro firefox thunar wofi waybar mako swaybg swaylock
        xdg-desktop-portal-hyprland polkit-kde-agent xdg-user-dirs ufw
        pipewire wireplumber pipewire-pulse pipewire-alsa pulseaudio pavucontrol # Audio
        grim slurp wl-clipboard nautilus dolphin
        noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-liberation ttf-font-awesome
        gstreamer gst-plugins-good gst-plugins-bad gst-plugins-ugly libavcodec
        mesa-vdpau vulkan-intel vulkan-radeon libva-utils # Intel/AMD Extras
        nvidia-dkms linux-headers libva-nvidia-driver-git egl-wayland # Nvidia
        tlp brightnessctl
        sddm sddm-qt6 bluez bluez-utils blueman
        gimp krita inkscape blender vlc mpv obs-studio ardour wine chromium neovim btop
        adw-gtk3 lxappearance # GTK Theming
        visual-studio-code-bin brave-bin reaper-bin obsidian nwg-look 
        sddm-config-editor-git tlp-rdw sddm-blur-git
        ntfs-3g exfatprogs udisks2 gvfs archlinux-wallpaper # FS & Wallpaper
    )
    
    local installed_pkgs_checklist=()
    echo "--- Verificando pacotes para desinstalação ---" > "$LOG_FILE"
    
    for pkg in "${master_pkg_list[@]}"; do
        if pacman -Q "$pkg" &>/dev/null || (command_exists yay && yay -Q "$pkg" &>/dev/null); then
            # Obtém a descrição do pacote, se possível
            local desc=$(pacman -Qi "$pkg" 2>/dev/null | grep Description | cut -d':' -f2- | sed 's/^[ \t]*//' || echo "Pacote $pkg")
            installed_pkgs_checklist+=("$pkg" "$desc" "off")
        fi
    done

    if [ ${#installed_pkgs_checklist[@]} -eq 0 ]; then
        dialog --msgbox "Nenhum pacote gerenciado por este script foi encontrado instalado." 6 60
        return
    fi

    dialog --backtitle "$BACKTITLE" --title "Desinstalar Pacotes" \
           --checklist "Selecione os pacotes que deseja REMOVER (Use Espaço):" 20 70 15 \
           "${installed_pkgs_checklist[@]}" \
           2> "$CHOICES_FILE"
           
    if [ $? -eq 0 ]; then
        choices=$(cat "$CHOICES_FILE" | tr -d '"')
        if [ -n "$choices" ]; then
            # Transforma a string de volta em array para exibição
            local choices_array=($choices) 
            local choices_formatted=$(printf "%s\n" "${choices_array[@]}")
            
            dialog --yesno "!! ATENÇÃO !!\n\nTEM CERTEZA?\n\nOs seguintes pacotes (e suas dependências órfãs) serão removidos:\n\n${choices_formatted}\n\nEsta ação não pode ser desfeita." 18 70
            if [ $? -eq 0 ]; then
                echo "--- Log: Desinstalando Pacotes ---" > "$LOG_FILE"
                dialog --infobox "Removendo pacotes selecionados..." 4 50
                sudo pacman -Rns $choices --noconfirm &>> "$LOG_FILE"
                if [ $? -ne 0 ]; then
                    dialog --msgbox "ERRO: Falha ao remover um ou mais pacotes.\n\nVerifique o log para detalhes." 8 60
                else
                    dialog --msgbox "Pacotes removidos com sucesso." 6 50
                fi
                show_log "Log de Desinstalação"
            fi
        else
            dialog --msgbox "Nenhum pacote selecionado para desinstalação." 6 50
        fi
    fi
    rm -f "$CHOICES_FILE"
}


# --- MENU PRINCIPAL ---
main_menu() {
    local choice
    choice=$(dialog --backtitle "$BACKTITLE" --title "Menu Principal" \
                    --menu "Escolha um passo (a ordem é recomendada):" 22 75 14 \
                    "1" "Atualizar o Sistema (Recomendado)" \
                    "2" "Instalar Pacotes Base + FS + Áudio" \
                    "3" "Instalar Fontes e Codecs de Mídia" \
                    "4" "Criar Configs Tematizadas (Vidro + Env/Rules)" \
                    "5" "Auto-Detectar Monitores" \
                    "6" "Configurar Otimizações de Notebook" \
                    "7" "Instalar Serviços (Login/Bluetooth)" \
                    "8" "Instalar 'yay' (AUR Helper) (Opcional, mas Req. p/ NVIDIA)" \
                    "9" "Instalar Drivers Gráficos e Aceleração" \
                    "10" "Instalar Aplicativos Adicionais (Pacman/AUR)" \
                    "11" "Limpeza do Sistema (Cache/Órfãos)" \
                    "12" "Desinstalar Pacotes (Gerenciados por este script)" \
                    "Q" "Sair" \
                    --output-fd 1)
    
    case "$choice" in
        1) update_system ;;
        2) install_base_system ;;
        3) install_fonts_codecs ;;
        4) setup_configs ;;
        5) setup_monitors ;;
        6) setup_laptop ;;
        7) setup_services ;;
        8) install_yay ;;
        9) install_drivers ;;
        10) install_extra_apps ;;
        11) system_cleanup ;;
        12) uninstall_packages ;;
        Q|q) 
            dialog --yesno "Tem certeza que deseja sair?" 6 50
            if [ $? -eq 0 ]; then
                clear
                # --- MELHORIA: Mensagem Final ---
                local final_msg="Assistente finalizado.\n\nLog de operações salvo em: $LOG_FILE\n\nPróximos Passos Recomendados:\n\n"
                local reboot_needed=false
                
                # Verifica se SDDM foi instalado/ativado
                if systemctl is-enabled sddm &>/dev/null; then
                    final_msg+=" - REINICIE o sistema para usar a tela de login gráfica (SDDM).\n"
                    reboot_needed=true
                fi
                # Verifica se grupo 'video' foi modificado
                if grep -q "Adicionado ao grupo 'video'" "$LOG_FILE"; then
                     final_msg+=" - FAÇA LOGOUT e LOGIN novamente para aplicar permissões de brilho (grupo 'video').\n"
                     # Não força reboot se só isso mudou
                fi
                # Verifica se drivers NVIDIA foram instalados
                if grep -q "Adicionando variáveis de ambiente NVIDIA" "$LOG_FILE"; then
                    final_msg+=" - (NVIDIA) LEMBRE-SE de adicionar 'nvidia_drm.modeset=1' aos parâmetros do kernel ANTES de reiniciar!\n"
                    reboot_needed=true # Kernel param exige reboot
                fi
                
                if [ $reboot_needed = false ]; then
                    final_msg+=" - Explore seu novo ambiente Hyprland!\n   (Pressione Super+Enter para abrir o terminal)\n"
                fi

                final_msg+="\n - Consulte os arquivos em ~/.config/hypr/ para customizar.\n - Use 'yay -S <pacote>' para instalar mais apps do AUR.\n"

                dialog --title "Instalação Concluída (ou quase!)" --msgbox "$final_msg" 20 75
                clear
                msg_ok "Script finalizado."
                exit 0
            fi
            ;;
        *) 
            # dialog --msgbox "Opção inválida." 6 50 # Desnecessário, o menu trata Esc/Cancel
            ;;
    esac
}

# --- Loop Principal do Script ---
check_dialog # Verifica se o 'dialog' está instalado
check_prereqs # Verifica internet e usuário

while true; do
    main_menu
done

