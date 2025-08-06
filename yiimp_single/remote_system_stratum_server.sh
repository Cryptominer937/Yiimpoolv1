#!/bin/env bash

##################################################################################
# This is the entry point for configuring the system.
# Source https://mailinabox.email/ https://github.com/mail-in-a-box/mailinabox
# Updated by Afiniel for yiimpool use...
##################################################################################

export TERM=xterm

source /etc/functions.sh
source /etc/yiimpool.conf

if [[ ! -e '$STORAGE_ROOT/yiimp/' ]]; then
sudo mkdir -p $STORAGE_ROOT/yiimp/
sudo cp -r /tmp/.yiimp.conf $STORAGE_ROOT/yiimp/
source $STORAGE_ROOT/yiimp/.yiimp.conf
else
sudo cp -r /tmp/.yiimp.conf $STORAGE_ROOT/yiimp/
source $STORAGE_ROOT/yiimp/.yiimp.conf
fi

# Set default PHP version if not defined
PHP_VERSION=${PHP_VERSION:-"8.1"}

# source $HOME/Yiimpoolv1/yiimp_single/.wireguard.install.cnf

set -eu -o pipefail

function print_error {
    read line file <<<$(caller)
    echo "An error occurred in line $line of file $file:" >&2
    sed "${line}q;d" "$file" >&2
}
trap print_error ERR

term_art
echo
echo -e "$YELLOW System Configuration Started!${NC}"
echo

# Set timezone to UTC
echo
echo -e "$YELLOW =>  Setting TimeZone to:$GREEN UTC <= ${NC}"
if [ ! -f /etc/timezone ]; then
    echo "Setting timezone to UTC."
    sudo bash -c 'echo "Etc/UTC" > /etc/timezone'
    restart_service rsyslog
fi
echo

hide_output sudo apt-get install -y software-properties-common build-essential

# CertBot
echo

if [[ "$DISTRO" == "16" || "$DISTRO" == "18" ]]; then
    echo -e "$MAGENTA => Installing CertBot PPA <= ${NC}"
    hide_output sudo add-apt-repository -y ppa:certbot/certbot
    hide_output sudo apt-get update
    echo -e "$GREEN => Complete${NC}"
elif [[ "$DISTRO" == "20" || "$DISTRO" == "22" || "$DISTRO" == "23" || "$DISTRO" == "24" ]]; then
    echo -e "$MAGENTA => Installing CertBot PPA <= ${NC}"
    hide_output sudo apt install -y snapd
    hide_output sudo snap install core
    hide_output sudo snap refresh core
    hide_output sudo snap install --classic certbot
    sudo ln -s /snap/bin/certbot /usr/bin/certbot
    echo -e "$GREEN => Complete${NC}"

elif [[ "$DISTRO" == "12" || "$DISTRO" == "11" ]]; then
    echo -e "$MAGENTA => Installing CertBot PPA <= ${NC}"
    hide_output sudo apt install -y certbot
    echo -e "$GREEN => Complete${NC}"
fi

#if [[ "$DISTRO" == "20" || "$DISTRO" == "22" || "$DISTRO" == "23" || "$DISTRO" == "24" ]]; then
#    echo
#    echo -e "$MAGENTA Detected$GREEN Distro $DISTRO $RED installing requirements.. ${NC}"
#    hide_output sudo apt install -y snapd
#    hide_output sudo snap install bitcoin-core
#    echo -e "$GREEN Completed${NC}"
#fi

echo
echo -e "$MAGENTA Installing MariaDB..${NC}"
hide_output sudo apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 0xF1656F24C74CD1D8

case "$DISTRO" in
    "16")  # Ubuntu 16.04
        sudo add-apt-repository -y 'deb [arch=amd64,arm64,i386,ppc64el] https://mirror.mariadb.org/repo/10.4/ubuntu xenial main' >/dev/null 2>&1
        ;;
    "18")  # Ubuntu 18.04
        sudo add-apt-repository  -y 'deb [arch=amd64,arm64,ppc64el] https://mirror.mariadb.org/repo/10.6/ubuntu bionic main' >/dev/null 2>&1
        ;;
    "20")   # Ubuntu 20.04
        sudo add-apt-repository -y 'deb [arch=amd64,arm64,ppc64el,s390x] https://mirror.mariadb.org/repo/10.6/ubuntu focal main' >/dev/null 2>&1
        ;;
    "22")   # Ubuntu 22.04
        sudo add-apt-repository -y 'deb [arch=amd64,arm64,ppc64el,s390x] https://mirror.mariadb.org/repo/10.6/ubuntu jammy main' >/dev/null 2>&1
        ;;
    "23")   # Ubuntu 23.04
        sudo add-apt-repository -y 'deb [arch=amd64,arm64,ppc64el,s390x] https://mirror.mariadb.org/repo/11.6/ubuntu lunar main' >/dev/null 2>&1
        ;;
    "24")   # Ubuntu 24.04
        sudo add-apt-repository -y 'deb [arch=amd64,arm64,ppc64el,s390x] https://mirror.mariadb.org/repo/11.6/ubuntu noble main' >/dev/null 2>&1
        ;;
    "12")   # Debian 12
        sudo add-apt-repository -y 'deb [arch=amd64,arm64,ppc64el,s390x] https://mirror.mariadb.org/repo/11.6/debian bookworm main' >/dev/null 2>&1
        ;;
    "11")   # Debian 11
        sudo add-apt-repository -y 'deb [arch=amd64,arm64,ppc64el,s390x] https://mirror.mariadb.org/repo/10.6/debian bullseye main' >/dev/null 2>&1
        ;;
    *)
        echo "Unsupported Ubuntu version: $DISTRO"
        exit 1
        ;;
esac
echo -e "$GREEN Complete...${NC}"
hide_output sudo apt-get update

if [ ! -f /boot/grub/menu.lst ]; then
    apt_get_quiet upgrade
else
    sudo rm /boot/grub/menu.lst
    sudo update-grub-legacy-ec2 -y
    apt_get_quiet upgrade
fi

apt_get_quiet dist-upgrade
apt_get_quiet autoremove

echo
echo -e "$MAGENTA => Installing Base system packages <= ${NC}"
apt_install python3 python3-dev python3-pip \
    wget curl git sudo coreutils bc \
    haveged pollinate unzip \
    unattended-upgrades cron ntp fail2ban screen rsyslog lolcat nginx

echo -e "$GREEN => Complete${NC}"
echo
echo -e "$YELLOW => Initializing system random number generator <= ${NC}"
hide_output dd if=/dev/random of=/dev/urandom bs=1 count=32 2>/dev/null
hide_output sudo pollinate -q -r
echo -e "$GREEN => Complete${NC}"

echo
echo -e "$YELLOW => Initializing UFW Firewall <= ${NC}"
set +eu +o pipefail
if [ -z "${DISABLE_FIREWALL:-}" ]; then
    hide_output sudo apt-get install -y ufw
    echo
    echo -e "$YELLOW => Allow incoming connections to SSH <= ${NC}"
    echo
    ufw_allow ssh
    sleep 0.5
    echo -e "$YELLOW ssh port:$GREEN OPEN ${NC}"
    echo
    sleep 0.5
    ufw_allow http
    echo -e "$YELLOW http port:$GREEN OPEN ${NC}"
    echo
    sleep 0.5
    ufw_allow https
    echo -e "$YELLOW https port:$GREEN OPEN ${NC}"
    echo

    SSH_PORT=$(sshd -T 2>/dev/null | grep "^port " | sed "s/port //")
    if [ ! -z "$SSH_PORT" ] && [ "$SSH_PORT" != "22" ]; then
        echo -e "$YELLOW => Allow incoming connections to SSH <= ${NC}"
        echo
        echo -e "$YELLOW Opening alternate SSH port:$GREEN $SSH_PORT ${NC}"
        echo
        ufw_allow $SSH_PORT
        sleep 0.5
        echo
        echo -e "$YELLOW http port:$GREEN OPEN ${NC}"
        ufw_allow http
        sleep 0.5
        echo
        echo -e "$YELLOW https port:$GREEN OPEN ${NC}"
        ufw_allow https
        sleep 0.5
        echo
    fi

    hide_output sudo ufw --force enable
fi
set -eu -o pipefail
echo
echo -e "$MAGENTA => Installing YiiMP Required system packages <= ${NC}"
if [ -f /usr/sbin/apache2 ]; then
    echo Removing apache...
    hide_output sudo apt-get -y purge apache2 apache2-*
    hide_output sudo apt-get -y --purge autoremove
fi

hide_output sudo apt-get update

echo
echo -e "$CYAN => Installing PHP <= ${NC}"
sleep 3

if [[ "$DISTRO" == "12" ]]; then
    apt_install python3-launchpadlib
fi

if [[ "$DISTRO" == "16" || "$DISTRO" == "18" || "$DISTRO" == "20" || "$DISTRO" == "22" || "$DISTRO" == "23" || "$DISTRO" == "24" ]]; then
    if [ ! -f /etc/apt/sources.list.d/ondrej-php-bionic.list ]; then
        hide_output sudo add-apt-repository -y ppa:ondrej/php
    fi
elif [[ "$DISTRO" == "12" || "$DISTRO" == "11" ]]; then
    if [ ! -f /etc/apt/sources.list.d/ondrej-php.list ]; then
        hide_output sudo apt-get install -y apt-transport-https lsb-release ca-certificates
        wget -qO - https://packages.sury.org/php/apt.gpg | sudo apt-key add -
        echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/php.list
        hide_output sudo apt-get update
    fi
fi

hide_output sudo apt-get update

if [[ "$DISTRO" == "16" || "$DISTRO" == "18" || "$DISTRO" == "20" || "$DISTRO" == "22" || "$DISTRO" == "23" || "$DISTRO" == "24" ]]; then

    apt_install php${PHP_VERSION}-fpm php${PHP_VERSION}-opcache php${PHP_VERSION} php${PHP_VERSION}-common php${PHP_VERSION}-gd
    apt_install php${PHP_VERSION}-mysql php${PHP_VERSION}-imap php${PHP_VERSION}-cli php${PHP_VERSION}-cgi
    apt_install php-pear php-auth-sasl mcrypt imagemagick libruby
    apt_install php${PHP_VERSION}-curl php${PHP_VERSION}-intl php${PHP_VERSION}-pspell php${PHP_VERSION}-sqlite3
    apt_install php${PHP_VERSION}-tidy php${PHP_VERSION}-xmlrpc php${PHP_VERSION}-xsl memcached php-memcache
    apt_install php-imagick php-gettext php${PHP_VERSION}-zip php${PHP_VERSION}-mbstring
    apt_install fail2ban ntpdate python3 python3-dev python3-pip
    apt_install curl git sudo coreutils pollinate unzip unattended-upgrades cron
    apt_install pwgen libgmp3-dev libmysqlclient-dev libcurl4-gnutls-dev
    apt_install libkrb5-dev libldap2-dev libidn11-dev gnutls-dev librtmp-dev
    apt_install build-essential libtool autotools-dev automake pkg-config libevent-dev bsdmainutils libssl-dev
    apt_install automake cmake gnupg2 ca-certificates lsb-release nginx certbot libsodium-dev
    apt_install libnghttp2-dev librtmp-dev libssh2-1 libssh2-1-dev libldap2-dev libidn11-dev libpsl-dev libkrb5-dev php${PHP_VERSION}-memcache php${PHP_VERSION}-memcached memcached
    apt_install php${PHP_VERSION}-mysql
    apt_install libssh-dev libbrotli-dev php${PHP_VERSION}-curl

elif [[ "$DISTRO" == "12" || "$DISTRO" == "11" ]]; then
    # Install packages specific to Debian 12
    apt_install php${PHP_VERSION}-fpm php${PHP_VERSION}-opcache php${PHP_VERSION} php${PHP_VERSION}-common php${PHP_VERSION}-gd
    apt_install php${PHP_VERSION}-mysql php${PHP_VERSION}-imap php${PHP_VERSION}-cli php${PHP_VERSION}-cgi
    apt_install php-pear php-auth-sasl mcrypt imagemagick libruby
    apt_install php${PHP_VERSION}-curl php${PHP_VERSION}-intl php${PHP_VERSION}-pspell php${PHP_VERSION}-sqlite3
    apt_install php${PHP_VERSION}-tidy php${PHP_VERSION}-xmlrpc php${PHP_VERSION}-xsl memcached php-memcache
    apt_install php-imagick php-gettext php${PHP_VERSION}-zip php${PHP_VERSION}-mbstring
    apt_install fail2ban ntpdate python3 python3-dev python3-pip
    apt_install curl git sudo coreutils pollinate unzip unattended-upgrades cron
    apt_install pwgen libgmp3-dev libmysqlclient-dev libcurl4-gnutls-dev
    apt_install libkrb5-dev libldap2-dev libidn11-dev gnutls-dev librtmp-dev
    apt_install build-essential libtool autotools-dev automake pkg-config libevent-dev bsdmainutils libssl-dev
    apt_install automake cmake gnupg2 ca-certificates lsb-release nginx certbot libsodium-dev
    apt_install libnghttp2-dev librtmp-dev libssh2-1 libssh2-1-dev libldap2-dev libidn11-dev libpsl-dev libkrb5-dev php${PHP_VERSION}-memcache php${PHP_VERSION}-memcached memcached
    apt_install php${PHP_VERSION}-mysql
    apt_install libssh-dev libbrotli-dev php${PHP_VERSION}-curl

fi

if [[ ("$DISTRO" == "20" ) || "$DISTRO" == "22" || "$DISTRO" == "23" || "$DISTRO" == "24" ]]; then

	apt_install php${PHP_VERSION}-fpm php${PHP_VERSION}-opcache php${PHP_VERSION} php${PHP_VERSION}-common php${PHP_VERSION}-gd php${PHP_VERSION}-mysql php${PHP_VERSION}-imap php${PHP_VERSION}-cli
	apt_install php${PHP_VERSION}-cgi php${PHP_VERSION}-curl php${PHP_VERSION}-intl php${PHP_VERSION}-pspell
	apt_install php${PHP_VERSION}-sqlite3 php${PHP_VERSION}-tidy php${PHP_VERSION}-xmlrpc php${PHP_VERSION}-xsl php${PHP_VERSION}-zip
	apt_install php${PHP_VERSION}-mbstring php${PHP_VERSION}-memcache php${PHP_VERSION}-memcached certbot
	apt_install libssh-dev libbrotli-dev
	sleep 2
	sudo systemctl start php${PHP_VERSION}-fpm
	sudo systemctl status php${PHP_VERSION}-fpm | sed -n "1,3p"

    elif [[ "$DISTRO" == "12" || "$DISTRO" == "11" ]]; then
    
    apt_install php${PHP_VERSION}-fpm php${PHP_VERSION}-opcache php${PHP_VERSION} php${PHP_VERSION}-common php${PHP_VERSION}-gd php${PHP_VERSION}-mysql php${PHP_VERSION}-imap php${PHP_VERSION}-cli
    apt_install php${PHP_VERSION}-cgi php${PHP_VERSION}-curl php${PHP_VERSION}-intl php${PHP_VERSION}-pspell
    apt_install php${PHP_VERSION}-sqlite3 php${PHP_VERSION}-tidy php${PHP_VERSION}-xmlrpc php${PHP_VERSION}-xsl php${PHP_VERSION}-zip
    apt_install php${PHP_VERSION}-mbstring php${PHP_VERSION}-memcache php${PHP_VERSION}-memcached certbot
    apt_install libssh-dev libbrotli-dev
    sleep 2
    sudo systemctl start php${PHP_VERSION}-fpm
    sudo systemctl status php${PHP_VERSION}-fpm | sed -n "1,3p"
fi

echo -e "$CYAN => Fixing DB connection issue... ${NC}"
sudo update-alternatives --set php /usr/bin/php${PHP_VERSION:-8.1}

echo
echo -e "$CYAN => Cloning Yiimp Repo <= ${NC}"
hide_output sudo git clone ${YiiMPRepo} $STORAGE_ROOT/yiimp/yiimp_setup/yiimp

hide_output sudo service nginx restart
sleep 0.5

set +eu +o pipefail
exit 0
