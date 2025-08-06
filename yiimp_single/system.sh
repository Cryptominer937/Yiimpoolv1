#!/bin/env bash

##################################################################################
# This is the entry point for configuring the system.
# Source https://mailinabox.email/ https://github.com/mail-in-a-box/mailinabox
# Updated by Afiniel for yiimpool use...
##################################################################################

clear
source /etc/functions.sh
source /etc/yiimpool.conf
source $STORAGE_ROOT/yiimp/.yiimp.conf

# Set default values if not defined (for backward compatibility)
USE_AAPANEL=${USE_AAPANEL:-"no"}
WEB_SERVER_TYPE=${WEB_SERVER_TYPE:-"nginx"}
SKIP_WEB_SERVER_INSTALL=${SKIP_WEB_SERVER_INSTALL:-"false"}
SKIP_PHP_INSTALL=${SKIP_PHP_INSTALL:-"false"}
SKIP_MYSQL_INSTALL=${SKIP_MYSQL_INSTALL:-"false"}
PHP_VERSION=${PHP_VERSION:-"8.1"}
DEDICATED_DB_SERVER_IP=${DEDICATED_DB_SERVER_IP:-"localhost"}

set -eu -o pipefail

function print_error {
    read line file <<<$(caller)
    echo "An error occurred in line $line of file $file:" >&2
    sed "${line}q;d" "$file" >&2
}
trap print_error ERR

term_art
print_header "System Configuration"
print_info "Starting system configuration..."

# Set timezone to UTC
print_header "Setting TimeZone"
if [ ! -f /etc/timezone ]; then
    print_status "Setting timezone to UTC"
    sudo timedatectl set-timezone UTC
    restart_service rsyslog
fi
print_success "Timezone set to UTC"

apt_install software-properties-common build-essential

# CertBot
print_header "Installing CertBot"

if [[ "$DISTRO" == "16" || "$DISTRO" == "18" ]]; then
    print_status "Installing CertBot PPA for Ubuntu 16/18"
    hide_output sudo add-apt-repository -y ppa:certbot/certbot
    hide_output sudo apt-get update
    print_success "CertBot installation complete"
elif [[ "$DISTRO" == "20" || "$DISTRO" == "22" || "$DISTRO" == "23" || "$DISTRO" == "24" ]]; then
    print_status "Installing CertBot via Snap for Ubuntu 20/22/23/24"
    hide_output sudo apt install -y snapd
    hide_output sudo snap install core
    hide_output sudo snap refresh core
    hide_output sudo snap install --classic certbot
    sudo ln -s /snap/bin/certbot /usr/bin/certbot
    print_success "CertBot installation complete"
elif [[ "$DISTRO" == "12" ]]; then
    print_status "Installing CertBot for Debian 12"
    hide_output sudo apt install -y certbot
    print_success "CertBot installation complete"
fi

print_header "Installing MariaDB"

# Create directory for keys if it doesn't exist
if [ ! -d /etc/apt/keyrings ]; then
    sudo mkdir -p /etc/apt/keyrings
fi

# Download and add the MariaDB signing key
if [ ! -f /etc/apt/keyrings/mariadb.gpg ]; then
    print_status "Downloading MariaDB signing key"
    sudo curl -fsSL https://mariadb.org/mariadb_release_signing_key.pgp | sudo gpg --dearmor -o /etc/apt/keyrings/mariadb.gpg
fi

case "$DISTRO" in
    "16")  # Ubuntu 16.04
        echo "deb [signed-by=/etc/apt/keyrings/mariadb.gpg arch=amd64,arm64,i386,ppc64el] https://mirror.mariadb.org/repo/10.4/ubuntu xenial main" \ 
        ;;
    "18")  # Ubuntu 18.04
        echo "deb [signed-by=/etc/apt/keyrings/mariadb.gpg arch=amd64,arm64,ppc64el] https://mirror.mariadb.org/repo/10.6/ubuntu bionic main" \ 
        ;;
    "20")  # Ubuntu 20.04
        echo "deb [signed-by=/etc/apt/keyrings/mariadb.gpg arch=amd64,arm64,ppc64el,s390x] https://mirror.mariadb.org/repo/10.6/ubuntu focal main" \
        ;;
    "22")  # Ubuntu 22.04
        echo "deb [signed-by=/etc/apt/keyrings/mariadb.gpg arch=amd64,arm64,ppc64el,s390x] https://mirror.mariadb.org/repo/10.6/ubuntu jammy main" \
        ;;
    "23")  # Ubuntu 23.04
        echo "deb [signed-by=/etc/apt/keyrings/mariadb.gpg arch=amd64,arm64,ppc64el,s390x] https://mirror.mariadb.org/repo/11.6/ubuntu lunar main" \
        ;;
    "24")  # Ubuntu 24.04
        echo "deb [signed-by=/etc/apt/keyrings/mariadb.gpg arch=amd64,arm64,ppc64el,s390x] https://mirror.mariadb.org/repo/11.6/ubuntu noble main" \
        ;;
    "12")  # Debian 12
        echo "deb [signed-by=/etc/apt/keyrings/mariadb.gpg arch=amd64,arm64,ppc64el,s390x] https://mirror.mariadb.org/repo/11.6/debian bookworm main" \
        ;;
    "11")  # Debian 11
        echo "deb [signed-by=/etc/apt/keyrings/mariadb.gpg arch=amd64,arm64,ppc64el,s390x] https://mirror.mariadb.org/repo/10.6/debian bullseye main" \
        ;;
    *)
        print_error "Unsupported Ubuntu/Debian version: $DISTRO"
        exit 1
        ;;
esac
print_success "MariaDB repository setup complete"
hide_output sudo apt-get update

if [ ! -f /boot/grub/menu.lst ]; then
    hide_output sudo apt-get upgrade -y
else
    sudo rm /boot/grub/menu.lst
    sudo update-grub-legacy-ec2 -y
    hide_output sudo apt-get upgrade -y
fi

hide_output sudo apt-get dist-upgrade -y
hide_output sudo apt-get autoremove -y

print_header "Installing Base System Packages"
apt_install python3 python3-dev python3-pip \
	wget curl git sudo coreutils bc \
	haveged pollinate unzip \
	unattended-upgrades cron ntp fail2ban screen rsyslog lolcat haproxy supervisor

# Install nginx only if not skipping web server installation
if [[ "${SKIP_WEB_SERVER_INSTALL}" != "true" ]]; then
    print_status "Installing nginx..."
    apt_install nginx
else
    print_info "Skipping nginx installation - using existing web server (${WEB_SERVER_TYPE})"
fi

print_success "Base system packages installed"

print_header "Initializing System Random Number Generator"
hide_output dd if=/dev/random of=/dev/urandom bs=1 count=32 2>/dev/null
hide_output sudo pollinate -q -r
print_success "Random number generator initialized"

print_header "Initializing UFW Firewall"
set +eu +o pipefail
if [ -z "${DISABLE_FIREWALL:-}" ]; then
    hide_output sudo apt-get install -y ufw
    
    print_status "Configuring firewall rules..."
    ufw_allow ssh
    print_success "SSH port opened"
    
    ufw_allow http
    print_success "HTTP port opened"
    
    ufw_allow https
    print_success "HTTPS port opened"

    SSH_PORT=$(sshd -T 2>/dev/null | grep "^port " | sed "s/port //")
    if [ ! -z "$SSH_PORT" ] && [ "$SSH_PORT" != "22" ]; then
        print_status "Opening alternate SSH port: $SSH_PORT"
        ufw_allow $SSH_PORT
        print_success "Alternate SSH port opened"
    fi

    hide_output sudo ufw --force enable
    print_success "Firewall enabled and configured"
fi
set -eu -o pipefail

print_header "Installing YiiMP Required Packages"
if [ -f /usr/sbin/apache2 ]; then
    print_status "Removing Apache..."
    hide_output sudo apt-get -y purge apache2 apache2-*
    hide_output sudo apt-get -y --purge autoremove
fi

hide_output sudo apt-get update

if [[ "${SKIP_PHP_INSTALL}" != "true" ]]; then
    print_header "Installing PHP"

    if [[ "$DISTRO" == "11" || "$DISTRO" == "12" ]]; then
        if [ ! -f /etc/apt/sources.list.d/ondrej-php.list ]; then
            print_status "Adding PHP repository for Debian"
            apt_install python3-launchpadlib apt-transport-https lsb-release ca-certificates
            curl -fsSL https://packages.sury.org/php/apt.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/php.gpg
            echo "deb [signed-by=/etc/apt/keyrings/php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" | \
                sudo tee /etc/apt/sources.list.d/php.list
            hide_output sudo apt-get update
        fi
    else
        if [ ! -f /etc/apt/sources.list.d/ondrej-php-bionic.list ]; then
            print_status "Adding PHP repository for Ubuntu"
            hide_output sudo add-apt-repository -y ppa:ondrej/php
        fi
    fi

    hide_output sudo apt-get update

    print_status "Installing PHP ${PHP_VERSION} packages..."

    # Install PHP packages based on version
    apt_install php${PHP_VERSION}-fpm php${PHP_VERSION}-opcache php${PHP_VERSION} php${PHP_VERSION}-common php${PHP_VERSION}-gd
    apt_install php${PHP_VERSION}-mysql php${PHP_VERSION}-imap php${PHP_VERSION}-cli php${PHP_VERSION}-cgi
    apt_install php-pear php-auth-sasl mcrypt imagemagick libruby
    apt_install php${PHP_VERSION}-curl php${PHP_VERSION}-intl php${PHP_VERSION}-pspell php${PHP_VERSION}-sqlite3
    apt_install php${PHP_VERSION}-tidy php${PHP_VERSION}-xmlrpc php${PHP_VERSION}-xsl memcached php-memcache
    apt_install php-imagick php-gettext php${PHP_VERSION}-zip php${PHP_VERSION}-mbstring
    apt_install php${PHP_VERSION}-memcache php${PHP_VERSION}-memcached
    apt_install php${PHP_VERSION}-mysql php${PHP_VERSION}-mbstring
    apt_install libssh-dev libbrotli-dev php${PHP_VERSION}-curl

    print_success "PHP ${PHP_VERSION} installation complete"

    print_header "Installing phpMyAdmin"
    hide_output sudo wget https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.tar.gz
    hide_output sudo tar xzf phpMyAdmin-latest-all-languages.tar.gz
    sudo rm phpMyAdmin-latest-all-languages.tar.gz
    sudo mv phpMyAdmin-*-all-languages /usr/share/phpmyadmin
    sudo mkdir -p /usr/share/phpmyadmin/tmp
    sudo chmod 777 /usr/share/phpmyadmin/tmp
    print_success "phpMyAdmin installation complete"

    print_header "Setting PHP Version"
    sudo update-alternatives --set php /usr/bin/php${PHP_VERSION}
    print_success "PHP version set to ${PHP_VERSION}"
else
    print_info "Skipping PHP installation - using existing PHP ${PHP_VERSION} from ${WEB_SERVER_TYPE}"

    # Still install required development packages
    print_status "Installing required development packages..."
    apt_install fail2ban ntpdate python3 python3-dev python3-pip
    apt_install coreutils pollinate unzip unattended-upgrades cron
    apt_install pwgen libgmp3-dev libmysqlclient-dev libcurl4-gnutls-dev
    apt_install libkrb5-dev libldap2-dev libidn11-dev gnutls-dev librtmp-dev
    apt_install build-essential libtool autotools-dev automake pkg-config libevent-dev bsdmainutils libssl-dev
    apt_install automake cmake gnupg2 ca-certificates lsb-release certbot libsodium-dev
    apt_install libnghttp2-dev librtmp-dev libssh2-1 libssh2-1-dev libldap2-dev libidn11-dev libpsl-dev libkrb5-dev memcached
    apt_install libssh-dev libbrotli-dev

    # Set PHP path for compatibility (adjust based on web server type)
    if [[ "${WEB_SERVER_TYPE}" == "openlitespeed" ]]; then
        # OpenLiteSpeed PHP path
        if [ -f "/usr/local/lsws/lsphp${PHP_VERSION//.}/bin/php" ]; then
            sudo ln -sf /usr/local/lsws/lsphp${PHP_VERSION//.}/bin/php /usr/bin/php
        fi
    fi

    print_success "Development packages installed"
fi

print_header "Cloning YiiMP Repository"
hide_output sudo git clone ${YiiMPRepo} $STORAGE_ROOT/yiimp/yiimp_setup/yiimp
print_success "YiiMP repository cloned successfully"

# Restart web server only if we installed it
if [[ "${SKIP_WEB_SERVER_INSTALL}" != "true" ]]; then
    hide_output sudo service nginx restart
    print_success "Nginx restarted"
else
    print_info "Skipping web server restart - using existing ${WEB_SERVER_TYPE}"
fi

set +eu +o pipefail
cd $HOME/Yiimpoolv1/yiimp_single
