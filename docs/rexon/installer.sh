#!/bin/bash

# Cross-platform installer: Git, curl, Node.js, JDK, node-pty deps, Rexon (https://github.com/Xenovate-foss/rexon), with Playit.gg
# Supports: Ubuntu/Debian, RHEL/Fedora, macOS, Termux, Alpine (musl-based), with optional nginx proxy config

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ASCII Banner with colors
echo -e "${CYAN}"
echo "
 ______     ______     __  __     ______     __   __    
/\  == \   /\  ___\   /\_\_\_\   /\  __ \   /\ \"-.\ \   
\ \  __<   \ \  __\   \/_/\_\/_  \ \ \/\ \  \ \ \-.  \  
 \ \_\ \_\  \ \_____\   /\_\/\_\  \ \_____\  \ \_\\\"\_\ 
  \/_/ /_/   \/_____/   \/_/\/_/   \/_____/   \/_/ \/_/ 
                                                        
"
echo -e "${NC}"

# Detect OS
echo -e "${BOLD}Detecting operating system...${NC}"
if [[ -n "$(command -v termux-info 2>/dev/null)" ]]; then
    OS="TERMUX"
elif [[ "$OSTYPE" == "linux-musl"* ]] || grep -qi 'alpine' /etc/os-release 2>/dev/null; then
    OS="ALPINE"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if command -v apt-get &> /dev/null; then
        OS="DEBIAN"
    elif command -v dnf &> /dev/null || command -v yum &> /dev/null; then
        OS="RHEL"
    else
        echo -e "${RED}Unsupported Linux distribution.${NC}"
        exit 1
    fi
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="MAC"
else
    echo -e "${RED}Unsupported OS: $OSTYPE${NC}"
    exit 1
fi

echo -e "${GREEN}Detected OS: $OS${NC}"

# Install Homebrew (macOS)
install_homebrew() {
    if ! command -v brew &> /dev/null; then
        echo -e "${YELLOW}Installing Homebrew...${NC}"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
}

[[ "$OS" == "MAC" ]] && install_homebrew

# Update packages
echo -e "${BOLD}Updating package repositories...${NC}"
case $OS in
    DEBIAN) sudo apt-get update;;
    RHEL) sudo dnf check-update || sudo yum check-update || true;;
    TERMUX) apt update;;
    ALPINE) sudo apk update;;
    MAC) echo -e "${BLUE}macOS doesn't require manual update here.${NC}";;
esac

# Install essentials
install_pkg() {
    PKG="$1"
    echo -e "${YELLOW}Installing $PKG...${NC}"
    case $OS in
        DEBIAN) sudo apt-get install -y "$PKG";;
        RHEL) sudo dnf install -y "$PKG" || sudo yum install -y "$PKG";;
        MAC) brew install "$PKG";;
        TERMUX) apt install -y "$PKG";;
        ALPINE) sudo apk add "$PKG";;
    esac
}

echo -e "${BOLD}Checking for required packages...${NC}"
for pkg in git curl nodejs npm; do
    if ! command -v $pkg &>/dev/null; then
        install_pkg "$pkg"
    else
        echo -e "${GREEN}$pkg is already installed.${NC}"
    fi
done

# Install JDK
echo -e "${BOLD}Setting up Java Development Kit...${NC}"
echo -ne "${CYAN}Choose JDK version (8/11/17/21) [default: 17]: ${NC}"; read JDK_VERSION
JDK_VERSION=${JDK_VERSION:-17}
if [[ ! "$JDK_VERSION" =~ ^(8|11|17|21)$ ]]; then
    echo -e "${YELLOW}Invalid version. Defaulting to 17.${NC}"
    JDK_VERSION=17
fi

echo -e "${YELLOW}Installing OpenJDK ${JDK_VERSION}...${NC}"
case $OS in
    DEBIAN) sudo apt-get install -y openjdk-${JDK_VERSION}-jdk;;
    RHEL) install_pkg java-${JDK_VERSION}-openjdk-devel;;
    MAC) brew install --cask temurin${JDK_VERSION};;
    TERMUX) apt install -y openjdk-${JDK_VERSION};;
    ALPINE)
        sudo apk add openjdk${JDK_VERSION} || sudo apk add openjdk${JDK_VERSION%-*} # Fallback
        ;;
esac

# Install node-pty build deps
echo -e "${BOLD}Installing node-pty build dependencies...${NC}"
case $OS in
    DEBIAN) sudo apt-get install -y make g++ python3 pkg-config libx11-dev libxtst-dev libpng-dev libxext-dev;;
    RHEL) install_pkg "make gcc-c++ python3 pkgconfig libX11-devel libXtst-devel libpng-devel libXext-devel";;
    MAC) brew install make python pkg-config xquartz libpng;;
    TERMUX) apt install -y make clang python pkg-config libpng;;
    ALPINE) apk add make g++ python3 pkgconfig libx11-dev libxtst-dev libpng-dev libxext-dev;;
esac

# Install or upgrade Rexon
echo -e "${BOLD}${CYAN}Installing or upgrading Rexon...${NC}"
REXON_DIR="/opt/rexon"
if [[ "$OS" == "TERMUX" ]]; then
    REXON_DIR="$HOME/rexon"
fi

if [[ -d "$REXON_DIR" ]]; then
    echo -e "${BLUE}Rexon already exists, upgrading...${NC}"
    cd "$REXON_DIR"
    if [[ "$OS" != "TERMUX" ]]; then
        sudo git pull
        sudo npm install
    else
        git pull
        npm install
    fi
else
    if [[ "$OS" != "TERMUX" ]]; then
        sudo mkdir -p "$REXON_DIR"
        sudo git clone https://github.com/Xenovate-foss/rexon "$REXON_DIR"
        cd "$REXON_DIR"
        sudo npm install
    else
        git clone https://github.com/Xenovate-foss/rexon "$REXON_DIR"
        cd "$REXON_DIR"
        npm install
    fi
fi

# Optional: setup rexon.local with nginx
if [[ "$OS" == "DEBIAN" || "$OS" == "RHEL" || "$OS" == "ALPINE" ]]; then
    echo -ne "${CYAN}Do you want to set up rexon.local with nginx proxy? (y/n): ${NC}"; read yn
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Installing and configuring nginx...${NC}"
        install_pkg nginx
        sudo tee /etc/nginx/conf.d/rexon.conf > /dev/null <<EOF
server {
    listen 80;
    server_name rexon.local;
    location / {
        proxy_pass http://localhost:3000; # change port if rexon runs on different
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF
        sudo systemctl restart nginx || sudo service nginx restart
        echo "127.0.0.1 rexon.local" | sudo tee -a /etc/hosts > /dev/null
        echo -e "${GREEN}Nginx proxy setup complete. Visit http://rexon.local${NC}"
    fi
fi

# Install Playit.gg
echo -ne "${CYAN}Do you want to install Playit.gg for remote access? (y/n): ${NC}"; read yn
if [[ "$yn" =~ ^[Yy]$ ]]; then
    echo -e "${BOLD}${MAGENTA}Setting up Playit.gg...${NC}"
    
    # Determine architecture
    ARCH=$(uname -m)
    PLAYIT_URL=""
    
    case $ARCH in
        x86_64|amd64)
            PLAYIT_URL="https://github.com/playit-cloud/playit-agent/releases/latest/download/playit-linux-amd64"
            ;;
        aarch64|arm64)
            PLAYIT_URL="https://github.com/playit-cloud/playit-agent/releases/latest/download/playit-linux-aarch64"
            ;;
        armv7l)
            PLAYIT_URL="https://github.com/playit-cloud/playit-agent/releases/latest/download/playit-linux-armv7"
            ;;
        *)
            echo -e "${RED}Unsupported architecture: $ARCH${NC}"
            echo -e "${YELLOW}Playit.gg installation skipped. You can manually install it later.${NC}"
            ;;
    esac
    
    if [[ -n "$PLAYIT_URL" ]]; then
        # Set Playit directory to be inside Rexon
        PLAYIT_DIR="$REXON_DIR/bin"
        
        # Remove any previous Playit installation first
        echo -e "${YELLOW}Removing any previous Playit installation...${NC}"
        if [[ "$OS" != "TERMUX" ]]; then
            sudo rm -f /opt/playit/playit "$PLAYIT_DIR/playit" 2>/dev/null || true
            # Also stop and remove any existing service
            if [[ "$OS" != "MAC" ]]; then
                sudo systemctl stop playit.service 2>/dev/null || true
                sudo systemctl disable playit.service 2>/dev/null || true
                sudo rm -f /etc/systemd/system/playit.service 2>/dev/null || true
            else
                sudo launchctl unload /Library/LaunchDaemons/com.playit.agent.plist 2>/dev/null || true
                sudo rm -f /Library/LaunchDaemons/com.playit.agent.plist 2>/dev/null || true
            fi
        else
            rm -f "$HOME/playit/playit" "$PLAYIT_DIR/playit" 2>/dev/null || true
        fi
        
        # Create directory and download Playit
        echo -e "${BLUE}Installing Playit to $PLAYIT_DIR/playit...${NC}"
        if [[ "$OS" != "TERMUX" ]]; then
            sudo mkdir -p "$PLAYIT_DIR"
            sudo curl -L "$PLAYIT_URL" -o "$PLAYIT_DIR/playit"
            sudo chmod +x "$PLAYIT_DIR/playit"
        else
            mkdir -p "$PLAYIT_DIR"
            curl -L "$PLAYIT_URL" -o "$PLAYIT_DIR/playit"
            chmod +x "$PLAYIT_DIR/playit"
        fi
        
        # Create systemd service for non-termux environments
        if [[ "$OS" != "TERMUX" && "$OS" != "MAC" ]]; then
            echo -e "${BLUE}Creating Playit systemd service...${NC}"
            sudo tee /etc/systemd/system/playit.service > /dev/null <<EOF
[Unit]
Description=Playit.gg agent
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$PLAYIT_DIR
ExecStart=$PLAYIT_DIR/playit
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
            sudo systemctl daemon-reload
            sudo systemctl enable playit.service
            sudo systemctl start playit.service
            echo -e "${GREEN}Playit.gg service installed and started${NC}"
            echo -e "${YELLOW}Note: When running playit for the first time, you'll need to register by visiting the URL it provides.${NC}"
        elif [[ "$OS" == "MAC" ]]; then
            echo -e "${BLUE}Creating Playit launchd service...${NC}"
            sudo tee /Library/LaunchDaemons/com.playit.agent.plist > /dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.playit.agent</string>
    <key>ProgramArguments</key>
    <array>
        <string>$PLAYIT_DIR/playit</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>/tmp/playit.err</string>
    <key>StandardOutPath</key>
    <string>/tmp/playit.out</string>
</dict>
</plist>
EOF
            sudo launchctl load /Library/LaunchDaemons/com.playit.agent.plist
            echo -e "${GREEN}Playit.gg service installed and started${NC}"
            echo -e "${YELLOW}Note: When running playit for the first time, you'll need to register by visiting the URL it provides.${NC}"
        else
            echo -e "${BLUE}On Termux, you'll need to run Playit manually:${NC}"
            echo -e "${CYAN}  $PLAYIT_DIR/playit${NC}"
        fi
    fi
fi

# Create a simple startup script
if [[ "$OS" != "TERMUX" ]]; then
    STARTUP_SCRIPT="/usr/local/bin/rexon"
    echo -e "${BLUE}Creating startup script at $STARTUP_SCRIPT...${NC}"
    sudo tee "$STARTUP_SCRIPT" > /dev/null <<EOF
#!/bin/bash
cd "$REXON_DIR" && npm start
EOF
    sudo chmod +x "$STARTUP_SCRIPT"
else
    STARTUP_SCRIPT="$HOME/bin/rexon"
    echo -e "${BLUE}Creating startup script at $STARTUP_SCRIPT...${NC}"
    mkdir -p "$HOME/bin"
    tee "$STARTUP_SCRIPT" > /dev/null <<EOF
#!/bin/bash
cd "$REXON_DIR" && npm start
EOF
    chmod +x "$STARTUP_SCRIPT"
fi

clear
echo -e "${CYAN}"
echo "
 ______     ______     __  __     ______     __   __    
/\  == \   /\  ___\   /\_\_\_\   /\  __ \   /\ \"-.\ \   
\ \  __<   \ \  __\   \/_/\_\/_  \ \ \/\ \  \ \ \-.  \  
 \ \_\ \_\  \ \_____\   /\_\/\_\  \ \_____\  \ \_\\\"\_\ 
  \/_/ /_/   \/_____/   \/_/\/_/   \/_____/   \/_/ \/_/ 
                                                        
"
echo -e "${NC}"

echo -e "${GREEN}${BOLD}All done! Rexon has been installed successfully.${NC}"
echo -e "${CYAN}You can start Rexon using:${NC}"
echo -e "${YELLOW}  rexon${NC}"
echo -e "${CYAN}Or manually:${NC}"
echo -e "${YELLOW}  cd $REXON_DIR && npm start${NC}"

if [[ -n "$PLAYIT_URL" && "$yn" =~ ^[Yy]$ ]]; then
    echo -e "\n${MAGENTA}${BOLD}Playit.gg Setup Instructions:${NC}"
    if [[ "$OS" != "TERMUX" && "$OS" != "MAC" ]]; then
        echo -e "${CYAN}1. Check Playit status: ${YELLOW}sudo systemctl status playit${NC}"
        echo -e "${CYAN}2. View Playit logs: ${YELLOW}sudo journalctl -u playit${NC}"
    elif [[ "$OS" == "MAC" ]]; then
        echo -e "${CYAN}1. Check Playit status: ${YELLOW}sudo launchctl list | grep playit${NC}"
        echo -e "${CYAN}2. View Playit logs: ${YELLOW}cat /tmp/playit.out${NC}"
    fi
    echo -e "${CYAN}3. When running for the first time, you'll need to register with Playit${NC}"
    echo -e "${CYAN}4. After registration, configure Playit to tunnel the Rexon port (default: 3000)${NC}"
    echo -e "${CYAN}5. To manually start Playit: ${YELLOW}$PLAYIT_DIR/playit${NC}"
fi

echo -e "\n${GREEN}${BOLD}Thanks for installing Rexon! Happy coding!${NC}"
