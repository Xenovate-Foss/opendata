#!/bin/bash

# Cross-platform installer: Git, curl, Node.js, JDK, node-pty deps, Rexon (https://github.com/Xenovate-foss/rexon)
# Supports: Ubuntu/Debian, RHEL/Fedora, macOS, Termux, Alpine (musl-based), with optional nginx proxy config

set -e

# ASCII Banner
echo "
 ______     ______     __  __     ______     __   __    
/\  == \   /\  ___\   /\_\_\_\   /\  __ \   /\ \"-.\ \   
\ \  __<   \ \  __\   \/_/\_\/_  \ \ \/\ \  \ \ \-.  \  
 \ \_\ \_\  \ \_____\   /\_\/\_\  \ \_____\  \ \_\\\"\_\ 
  \/_/ /_/   \/_____/   \/_/\/_/   \/_____/   \/_/ \/_/ 
                                                        
"

# Detect OS
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
        echo "Unsupported Linux distribution."
        exit 1
    fi
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="MAC"
else
    echo "Unsupported OS: $OSTYPE"
    exit 1
fi

echo "Detected OS: $OS"

# Install Homebrew (macOS)
install_homebrew() {
    if ! command -v brew &> /dev/null; then
        echo "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
}

[[ "$OS" == "MAC" ]] && install_homebrew

# Update packages
case $OS in
    DEBIAN) sudo apt-get update;;
    RHEL) sudo dnf check-update || sudo yum check-update;;
    TERMUX) apt update;;
    ALPINE) sudo apk update;;
    MAC) echo "macOS doesn't require manual update here.";;
esac

# Install essentials
install_pkg() {
    PKG="$1"
    case $OS in
        DEBIAN) sudo apt-get install -y "$PKG";;
        RHEL) sudo dnf install -y "$PKG" || sudo yum install -y "$PKG";;
        MAC) brew install "$PKG";;
        TERMUX) apt install -y "$PKG";;
        ALPINE) sudo apk add "$PKG";;
    esac
}

for pkg in git curl nodejs npm; do
    if ! command -v $pkg &>/dev/null; then
        echo "Installing $pkg..."
        install_pkg "$pkg"
    else
        echo "$pkg is already installed."
    fi

done

# Install JDK
echo -n "Choose JDK version (8/11/17/21) [default: 17]: "; read JDK_VERSION
JDK_VERSION=${JDK_VERSION:-17}
if [[ ! "$JDK_VERSION" =~ ^(8|11|17|21)$ ]]; then
    echo "Invalid version. Defaulting to 17."
    JDK_VERSION=17
fi
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
case $OS in
    DEBIAN) sudo apt-get install -y make g++ python3 pkg-config libx11-dev libxtst-dev libpng-dev libxext-dev;;
    RHEL) install_pkg "make gcc-c++ python3 pkgconfig libX11-devel libXtst-devel libpng-devel libXext-devel";;
    MAC) brew install make python pkg-config xquartz libpng;;
    TERMUX) apt install -y make clang python pkg-config libpng;;
    ALPINE) apk add make g++ python3 pkgconfig libx11-dev libxtst-dev libpng-dev libxext-dev;;
esac

# Install or upgrade Rexon
echo "Installing or upgrading Rexon..."
REXON_DIR="/opt/rexon"
if [[ -d "$REXON_DIR" ]]; then
    echo "Rexon already exists, upgrading..."
    cd "$REXON_DIR"
    git pull
    npm install
else
    sudo git clone https://github.com/Xenovate-foss/rexon "$REXON_DIR"
    cd "$REXON_DIR"
    npm install
fi

# Optional: setup rexon.local with nginx
if [[ "$OS" == "DEBIAN" || "$OS" == "RHEL" || "$OS" == "ALPINE" ]]; then
    echo -n "Do you want to set up rexon.local with nginx proxy? (y/n): "; read yn
    if [[ "$yn" =~ ^[Yy]$ ]]; then
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
        echo "Nginx proxy setup complete. Visit http://rexon.local"
    fi
fi

echo "All done. Rexon installed at $REXON_DIR. Run it using:"
echo "  cd $REXON_DIR && npm start"
