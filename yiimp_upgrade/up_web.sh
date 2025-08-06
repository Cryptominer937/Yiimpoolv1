#####################################################
# Created by afiniel for crypto use...
#####################################################

source /etc/functions.sh
source /etc/yiimpool.conf
source $STORAGE_ROOT/yiimp/.yiimp.conf

# Set default values for private repository configuration
USE_PRIVATE_WEB_REPO=${USE_PRIVATE_WEB_REPO:-"no"}
PRIVATE_WEB_REPO_URL=${PRIVATE_WEB_REPO_URL:-""}
SSH_PRIVATE_KEY_PATH=${SSH_PRIVATE_KEY_PATH:-""}
SSH_PRIVATE_KEY_CONTENT=${SSH_PRIVATE_KEY_CONTENT:-""}

# Remove existing directory
if [[ -d '$STORAGE_ROOT/yiimp/yiimp_setup/yiimp' ]]; then
    sudo rm -rf $STORAGE_ROOT/yiimp/yiimp_setup/yiimp
fi

# Clean up temporary directories from dual repository setup
if [[ -d "$STORAGE_ROOT/yiimp/yiimp_setup/yiimp_private" ]]; then
    sudo rm -rf "$STORAGE_ROOT/yiimp/yiimp_setup/yiimp_private"
fi
if [[ -d "$STORAGE_ROOT/yiimp/yiimp_setup/yiimp_public" ]]; then
    sudo rm -rf "$STORAGE_ROOT/yiimp/yiimp_setup/yiimp_public"
fi

echo "Upgrading web component..."

if [[ "${USE_PRIVATE_WEB_REPO}" == "yes" ]]; then
    # Verify this is a multi-server setup
    if [[ "${wireguard:-false}" != "true" ]]; then
        echo "Private repository is only supported for multi-server setups"
        echo "Falling back to public repository for single-server web upgrade"
        USE_PRIVATE_WEB_REPO="no"
    else
        echo "Using private repository for multi-server web component: ${PRIVATE_WEB_REPO_URL}"
    fi
fi

if [[ "${USE_PRIVATE_WEB_REPO}" == "yes" && "${wireguard:-false}" == "true" ]]; then

    # For web upgrade, we only need the web component from private repo
    if ! clone_private_repository "${PRIVATE_WEB_REPO_URL}" "$STORAGE_ROOT/yiimp/yiimp_setup/yiimp_private" "private web"; then
        echo "Failed to clone private web repository. Exiting..."
        exit 1
    fi

    # Create main directory and copy web component
    sudo mkdir -p $STORAGE_ROOT/yiimp/yiimp_setup/yiimp
    sudo cp -r $STORAGE_ROOT/yiimp/yiimp_setup/yiimp_private/web $STORAGE_ROOT/yiimp/yiimp_setup/yiimp/

    echo "Private web repository cloned successfully"
else
    # Standard repository clone
    hide_output sudo git clone ${YiiMPRepo} $STORAGE_ROOT/yiimp/yiimp_setup/yiimp
    echo "Public repository cloned successfully"
fi

echo Upgrading stratum...
cd $STORAGE_ROOT/yiimp/yiimp_setup/yiimp/web/yaamp/core/functions/

cp -r yaamp.php $STORAGE_ROOT/yiimp/site/web/yaamp/core/functions

echo "Web upgrade complete..."
cd $HOME/Yiimpoolv1/yiimp_upgrade
