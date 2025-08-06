#!/bin/env bash

#
# This is for upgrading stratum.
#
# Author: afiniel
#
# 2025-02-06
#

source /etc/functions.sh
source /etc/yiimpool.conf
source $STORAGE_ROOT/yiimp/.yiimp.conf

# Set default values for private repository configuration
USE_PRIVATE_WEB_REPO=${USE_PRIVATE_WEB_REPO:-"no"}
PRIVATE_WEB_REPO_URL=${PRIVATE_WEB_REPO_URL:-""}
SSH_PRIVATE_KEY_PATH=${SSH_PRIVATE_KEY_PATH:-""}
SSH_PRIVATE_KEY_CONTENT=${SSH_PRIVATE_KEY_CONTENT:-""}

YIIMP_DIR="$STORAGE_ROOT/yiimp/yiimp_setup/yiimp"
if [[ -d "$YIIMP_DIR" ]]; then
    sudo rm -rf "$YIIMP_DIR"
fi

# Clean up temporary directories from dual repository setup
if [[ -d "$STORAGE_ROOT/yiimp/yiimp_setup/yiimp_private" ]]; then
    sudo rm -rf "$STORAGE_ROOT/yiimp/yiimp_setup/yiimp_private"
fi
if [[ -d "$STORAGE_ROOT/yiimp/yiimp_setup/yiimp_public" ]]; then
    sudo rm -rf "$STORAGE_ROOT/yiimp/yiimp_setup/yiimp_public"
fi

echo -e "$GREEN Cloning fresh YiiMP repository... $NC"

if [[ "${USE_PRIVATE_WEB_REPO}" == "yes" ]]; then
    # Verify this is a multi-server setup
    if [[ "${wireguard:-false}" != "true" ]]; then
        echo -e "$YELLOW Private repository is only supported for multi-server setups $NC"
        echo -e "$YELLOW Falling back to public repository for single-server upgrade $NC"
        USE_PRIVATE_WEB_REPO="no"
    else
        echo -e "$YELLOW Using dual repository setup for multi-server upgrade... $NC"
        echo -e "$CYAN Private web repository: ${PRIVATE_WEB_REPO_URL} $NC"
        echo -e "$CYAN Public repository: ${YiiMPRepo} $NC"
    fi
fi

if [[ "${USE_PRIVATE_WEB_REPO}" == "yes" && "${wireguard:-false}" == "true" ]]; then

    # Clone private repository for web component
    if ! clone_private_repository "${PRIVATE_WEB_REPO_URL}" "$STORAGE_ROOT/yiimp/yiimp_setup/yiimp_private" "private web"; then
        echo -e "$RED Failed to clone private web repository. Exiting... $NC"
        exit 1
    fi

    # Clone public repository for stratum and other components
    if ! sudo git clone "${YiiMPRepo}" "$STORAGE_ROOT/yiimp/yiimp_setup/yiimp_public"; then
        echo -e "$RED Failed to clone public YiiMP repository. Exiting... $NC"
        exit 1
    fi

    # Create combined directory structure
    sudo mkdir -p "$YIIMP_DIR"

    # Copy stratum and other components from public repo
    sudo cp -r $STORAGE_ROOT/yiimp/yiimp_setup/yiimp_public/stratum "$YIIMP_DIR/"
    sudo cp -r $STORAGE_ROOT/yiimp/yiimp_setup/yiimp_public/bin "$YIIMP_DIR/"
    sudo cp -r $STORAGE_ROOT/yiimp/yiimp_setup/yiimp_public/blocknotify "$YIIMP_DIR/"

    # Copy web component from private repo
    sudo cp -r $STORAGE_ROOT/yiimp/yiimp_setup/yiimp_private/web "$YIIMP_DIR/"

    echo -e "$GREEN Combined YiiMP repository structure created successfully $NC"
else
    # Standard single repository clone
    if ! sudo git clone "${YiiMPRepo}" "$YIIMP_DIR"; then
        echo -e "$RED Failed to clone YiiMP repository. Exiting... $NC"
        exit 1
    fi
fi

echo -e "$GREEN Setting gcc to version 9... $NC"
hide_output sudo update-alternatives --set gcc /usr/bin/gcc-9

echo
echo -e "$YELLOW => Upgrading stratum <= ${NC}"
echo
cd $YIIMP_DIR/stratum
sudo git submodule init
sudo git submodule update
cd secp256k1 && sudo chmod +x autogen.sh &&  sudo ./autogen.sh &&  sudo ./configure --enable-experimental --enable-module-ecdh --with-bignum=no --enable-endomorphism &&  sudo make -j$((`nproc`+1))
cd $YIIMP_DIR/stratum

echo -e "$GREEN Building stratum... $NC" 

if ! sudo sudo make -C algos -j$(($(nproc)+1)); then
    echo -e "$RED Failed to build stratum. Please check the build output above for errors. Exiting... $NC"
    exit 1
fi
echo -e "$GREEN algos built successfully! $NC"

if ! sudo sudo make -C sha3 -j$(($(nproc)+1)); then
    echo -e "$RED Failed to build sha3. Please check the build output above for errors. Exiting... $NC"
    exit 1
fi
echo -e "$GREEN sha3 built successfully! $NC"

if ! sudo sudo make -C iniparser -j$(($(nproc)+1)); then
    echo -e "$RED Failed to build iniparser. Please check the build output above for errors. Exiting... $NC"
    exit 1
fi
echo -e "$GREEN iniparser built successfully! $NC"

if ! sudo sudo make -j$(($(nproc)+1)); then
    echo -e "$RED Failed to build stratum. Please check the build output above for errors. Exiting... $NC"
    exit 1
fi
echo -e "$GREEN stratum built successfully! $NC"

echo -e "$GREEN Installing stratum... $NC"
if ! sudo mv stratum "$STORAGE_ROOT/yiimp/site/stratum"; then
    echo -e "$RED Failed to install stratum. Exiting... $NC"
    exit 1
fi

echo -e "$GREEN Copying yaamp.php to the site directory... $NC"
cd $YIIMP_DIR/web/yaamp/core/functions/
cp -r yaamp.php $STORAGE_ROOT/yiimp/site/web/yaamp/core/functions

hide_output sudo update-alternatives --set gcc /usr/bin/gcc-10
echo -e "$GREEN Stratum upgrade completed successfully! $NC"
cd
