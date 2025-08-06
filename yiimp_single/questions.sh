#!/bin/env bash

##################################################################################
# This is the entry point for configuring the system.                            #
# Source: https://mailinabox.email/ https://github.com/mail-in-a-box/mailinabox   #
# Updated by: Afiniel for Yiimpool use...                                         #
##################################################################################

# Load required functions and configurations
source /etc/functions.sh
source /etc/yiimpool.conf
source "$HOME/Yiimpoolv1/yiimp_single/.wireguard.install.cnf"

# Source wireguard configuration if enabled
if [[ ("$wireguard" == "true") ]]; then
    source "$STORAGE_ROOT/yiimp/.wireguard.conf"
fi

# aaPanel Configuration Variables
WEB_SERVER_TYPE="nginx"  # nginx, apache, openlitespeed
SKIP_WEB_SERVER_INSTALL="false"
SKIP_PHP_INSTALL="false"
SKIP_MYSQL_INSTALL="false"
USE_AAPANEL="false"
AAPANEL_SITE_ROOT=""
PHP_VERSION="8.1"
DEDICATED_DB_SERVER_IP=""

# Private Repository Configuration Variables
USE_PRIVATE_WEB_REPO="false"
PRIVATE_WEB_REPO_URL=""
SSH_PRIVATE_KEY_PATH=""
SSH_PRIVATE_KEY_CONTENT=""

# Display installation type based on wireguard setting
if [[ ("$wireguard" == "true") ]]; then
    message_box "Yiimpool Yiimp installer" \
    "You have chosen to install Yiimp with WireGuard!
    
    This option will install all components of YiiMP on a single server along with WireGuard so you can easily add additional servers in the future.
    
    Please make sure any domain name or subdomain names are pointed to this server's IP before running this installer.
    
    After answering the following questions, setup will be automated.
    
    NOTE: If installing on a system with less than 8 GB of RAM, you may experience system issues!"
else
    message_box "Yiimpool Yiimp installer" \
    "You have chosen to install Yiimp without WireGuard!
    
    This option will install all components of YiiMP on a single server.
    
    Please make sure any domain name or subdomain names are pointed to this server's IP before running this installer.
    
    After answering the following questions, setup will be automated.
    
    NOTE: If installing on a system with less than 8 GB of RAM, you may experience system issues!"
fi

# Prompt for using a domain name or IP
dialog --title "Using Domain Name" \
--yesno "Are you using a domain name? Example: example.com?\n\nMake sure the DNS is updated!" 7 60
response=$?
case $response in
   0) UsingDomain=yes;;
   1) UsingDomain=no;;
   255) echo "[ESC] key pressed.";;
esac

# If using a domain, further prompts for subdomain and domain name
if [[ "$UsingDomain" == "yes" ]]; then
    dialog --title "Using Sub-Domain" \
    --yesno "Are you using a sub-domain for the main website domain? Example: pool.example.com?\n\nMake sure the DNS is updated!" 7 60
    response=$?
    case $response in
       0) UsingSubDomain=yes;;
       1) UsingSubDomain=no;;
       255) echo "[ESC] key pressed.";;
    esac

    # Input box for domain name
    if [ -z "${DomainName:-}" ]; then
        DEFAULT_DomainName=example.com
        input_box "Domain Name" \
        "Enter your domain name. If using a subdomain, enter the full domain as in pool.example.com.\n\nDo not add www. to the domain name.\n\nMake sure the domain is pointed to this server before continuing!\n\nDomain Name:" \
        "${DEFAULT_DomainName}" \
        DomainName

        if [ -z "${DomainName}" ]; then
            exit
        fi
    fi

    # Input box for Stratum URL
    if [ -z "${StratumURL:-}" ]; then
        DEFAULT_StratumURL=${DomainName}
        input_box "Stratum URL" \
        "Enter your stratum URL. It is recommended to use another subdomain such as stratum.${DomainName}.\n\nDo not add www. to the domain name.\n\nStratum URL:" \
        "${DEFAULT_StratumURL}" \
        StratumURL

        if [ -z "${StratumURL}" ]; then
            exit
        fi
    fi

    # Prompt for automatic SSL installation
    dialog --title "Install SSL" \
    --yesno "Would you like the system to install SSL automatically?" 7 60
    response=$?
    case $response in
       0) InstallSSL=yes;;
       1) InstallSSL=no;;
       255) echo "[ESC] key pressed.";;
    esac
else
    # Set DomainName and StratumURL to server IP if not using a domain
    DomainName=$(get_publicip_from_web_service 4 || get_default_privateip 4)
    StratumURL=${DomainName}
    UsingSubDomain=no
    
    # Add SSL prompt even when using IP
    dialog --title "Install SSL" \
    --yesno "Would you like the system to install SSL automatically?\n\nNote: Self-signed SSL will be used when installing with IP address." 8 60
    response=$?
    case $response in
       0) InstallSSL=yes;;
       1) InstallSSL=no;;
       255) echo "[ESC] key pressed.";;
    esac
fi

# aaPanel Configuration Questions
dialog --title "Web Server Configuration" \
--yesno "Are you using aaPanel or do you have a web server already configured?\n\nSelect 'Yes' if you have aaPanel installed or want to skip web server installation.\nSelect 'No' for standard YiiMP installation with nginx." 10 70
response=$?
case $response in
   0) USE_AAPANEL=yes;;
   1) USE_AAPANEL=no;;
   255) echo "[ESC] key pressed.";;
esac

if [[ "$USE_AAPANEL" == "yes" ]]; then
    # Web Server Type Selection
    WEB_SERVER_TYPE=$(dialog --stdout --title "Web Server Type" --menu "Select your web server type:" 12 60 3 \
        "nginx" "Nginx (aaPanel default)" \
        "openlitespeed" "OpenLiteSpeed" \
        "apache" "Apache")

    if [ -z "$WEB_SERVER_TYPE" ]; then
        WEB_SERVER_TYPE="nginx"
    fi

    # PHP Version Selection
    PHP_VERSION=$(dialog --stdout --title "PHP Version" --menu "Select your PHP version:" 15 60 6 \
        "8.1" "PHP 8.1" \
        "8.2" "PHP 8.2" \
        "8.3" "PHP 8.3" \
        "8.4" "PHP 8.4" \
        "7.4" "PHP 7.4 (Legacy)" \
        "8.0" "PHP 8.0 (Legacy)")

    if [ -z "$PHP_VERSION" ]; then
        PHP_VERSION="8.1"
    fi

    # aaPanel Site Directory
    if [ -z "${AAPANEL_SITE_ROOT:-}" ]; then
        DEFAULT_AAPANEL_SITE_ROOT="/www/wwwroot/${DomainName}"
        input_box "aaPanel Site Directory" \
        "Enter the full path to your aaPanel site directory.\n\nThis is typically /www/wwwroot/yourdomain.com\n\nSite Directory:" \
        "${DEFAULT_AAPANEL_SITE_ROOT}" \
        AAPANEL_SITE_ROOT

        if [ -z "${AAPANEL_SITE_ROOT}" ]; then
            AAPANEL_SITE_ROOT="${DEFAULT_AAPANEL_SITE_ROOT}"
        fi
    fi

    # Skip all installations managed by aaPanel
    SKIP_WEB_SERVER_INSTALL="true"
    SKIP_PHP_INSTALL="true"

    # SSL will be managed by aaPanel
    InstallSSL="no"
    print_info "SSL certificates will be managed through aaPanel interface"

    # Important warnings for aaPanel + OpenLiteSpeed users
    if [[ "$WEB_SERVER_TYPE" == "openlitespeed" ]]; then
        print_warning "IMPORTANT: OpenLiteSpeed PHP Compatibility Notes:"
        print_warning "1. OpenLiteSpeed only supports PHP 8.1+ on Ubuntu/Debian"
        print_warning "2. LSPHP has 'memcached' but NOT 'memcache' extension"
        print_warning "3. LSPHP's memcached is NOT backwards compatible with memcache"
        print_warning "4. You may need to install memcache manually or modify YiiMP code"
        print_info ""
        print_info "To install memcache extension for LSPHP:"
        print_info "1. SSH into your server"
        print_info "2. Run: /usr/local/lsws/lsphp${PHP_VERSION//.}/bin/pecl install memcache"
        print_info "3. Add 'extension=memcache.so' to php.ini via aaPanel"
        print_info "4. Restart OpenLiteSpeed"
        print_info ""

        # Confirm user understands the limitations
        dialog --title "OpenLiteSpeed Compatibility Warning" \
        --yesno "Do you understand the OpenLiteSpeed PHP limitations?\n\n• Only PHP 8.1+ supported\n• Memcache extension needs manual installation\n• May require YiiMP code modifications\n\nContinue with OpenLiteSpeed setup?" 12 70
        response=$?
        case $response in
           1)
               print_error "OpenLiteSpeed setup cancelled by user"
               exit 1
               ;;
           255)
               print_error "Setup cancelled"
               exit 1
               ;;
        esac
    fi

    # Ask about MySQL installation
    dialog --title "MySQL Installation" \
    --yesno "Do you want to skip MySQL installation?\n\nSelect 'Yes' if you're using aaPanel's MySQL or a dedicated database server.\nSelect 'No' to install MySQL locally." 10 70
    response=$?
    case $response in
       0) SKIP_MYSQL_INSTALL="true";;
       1) SKIP_MYSQL_INSTALL="false";;
       255) echo "[ESC] key pressed.";;
    esac

    # If skipping MySQL, ask for dedicated DB server
    if [[ "$SKIP_MYSQL_INSTALL" == "true" ]]; then
        if [ -z "${DEDICATED_DB_SERVER_IP:-}" ]; then
            DEFAULT_DB_IP="localhost"
            input_box "Database Server IP" \
            "Enter the IP address of your database server.\n\nUse 'localhost' if using aaPanel's local MySQL.\nUse WireGuard IP if using dedicated database server.\n\nDatabase Server IP:" \
            "${DEFAULT_DB_IP}" \
            DEDICATED_DB_SERVER_IP

            if [ -z "${DEDICATED_DB_SERVER_IP}" ]; then
                DEDICATED_DB_SERVER_IP="localhost"
            fi
        fi
    fi
else
    # Standard installation - set defaults
    WEB_SERVER_TYPE="nginx"
    PHP_VERSION="8.1"
    SKIP_WEB_SERVER_INSTALL="false"
    SKIP_PHP_INSTALL="false"
    SKIP_MYSQL_INSTALL="false"
fi

# Private Repository Configuration Questions (only for multi-server setups)
if [[ "$wireguard" == "true" ]]; then
    dialog --title "YiiMP Web Repository (Multi-Server)" \
    --yesno "Do you want to use a private repository for the YiiMP web component?\n\nThis custom repository is designed for multi-server setups and includes\nmodifications specific to distributed mining pool architecture.\n\nStratum and database components will still use the public repository.\n\nSelect 'Yes' to configure private repository access.\nSelect 'No' to use the standard public repository." 14 70
    response=$?
    case $response in
       0) USE_PRIVATE_WEB_REPO=yes;;
       1) USE_PRIVATE_WEB_REPO=no;;
       255) echo "[ESC] key pressed.";;
    esac
else
    # Single-server setup - always use public repository
    USE_PRIVATE_WEB_REPO=no
    print_info "Single-server setup detected - using standard public repository"
fi

if [[ "$USE_PRIVATE_WEB_REPO" == "yes" ]]; then
    # Private Repository URL
    if [ -z "${PRIVATE_WEB_REPO_URL:-}" ]; then
        DEFAULT_PRIVATE_REPO="git@github.com:Cryptominer937/yiimp2.git"
        input_box "Private Repository URL" \
        "Enter the SSH URL for your private YiiMP repository.\n\nExample: git@github.com:username/repository.git\n\nRepository URL:" \
        "${DEFAULT_PRIVATE_REPO}" \
        PRIVATE_WEB_REPO_URL

        if [ -z "${PRIVATE_WEB_REPO_URL}" ]; then
            PRIVATE_WEB_REPO_URL="${DEFAULT_PRIVATE_REPO}"
        fi
    fi

    # SSH Private Key Configuration
    dialog --title "SSH Private Key Setup" \
    --yesno "How would you like to provide your SSH private key?\n\nSelect 'Yes' to paste the key content directly.\nSelect 'No' to specify a file path to an existing key." 10 70
    response=$?
    case $response in
       0)
           # Paste key content
           SSH_PRIVATE_KEY_CONTENT=$(dialog --stdout --title "SSH Private Key" --inputbox "Paste your SSH private key content here:\n\n(This will be securely stored and used for repository access)" 20 80)
           if [ -z "${SSH_PRIVATE_KEY_CONTENT}" ]; then
               print_error "SSH private key content is required for private repository access"
               exit 1
           fi
           ;;
       1)
           # File path
           if [ -z "${SSH_PRIVATE_KEY_PATH:-}" ]; then
               DEFAULT_KEY_PATH="$HOME/.ssh/id_rsa"
               input_box "SSH Private Key Path" \
               "Enter the full path to your SSH private key file.\n\nExample: /home/user/.ssh/id_rsa\n\nKey Path:" \
               "${DEFAULT_KEY_PATH}" \
               SSH_PRIVATE_KEY_PATH

               if [ -z "${SSH_PRIVATE_KEY_PATH}" ]; then
                   SSH_PRIVATE_KEY_PATH="${DEFAULT_KEY_PATH}"
               fi

               # Verify key file exists
               if [ ! -f "${SSH_PRIVATE_KEY_PATH}" ]; then
                   print_error "SSH private key file not found: ${SSH_PRIVATE_KEY_PATH}"
                   exit 1
               fi
           fi
           ;;
       255) echo "[ESC] key pressed.";;
    esac
else
    # Standard installation - use public repository
    USE_PRIVATE_WEB_REPO="no"
fi

# Further prompts for support email, admin panel location, auto-exchange, dedicated coin ports, and public IP
if [ -z "${SupportEmail:-}" ]; then
    DEFAULT_SupportEmail=root@localhost
    input_box "System Email" \
    "Enter an email address for the system to send alerts and other important messages.\n\nSystem Email:" \
    "${DEFAULT_SupportEmail}" \
    SupportEmail

    if [ -z "${SupportEmail}" ]; then
        exit
    fi
fi

# Automatically set PublicIP based on SSH client IP or default private IP
if [ -z "${PublicIP:-}" ]; then
    if pstree -p | egrep --quiet --extended-regexp ".*sshd.*\($$\)"; then
        DEFAULT_PublicIP=$(echo "$SSH_CLIENT" | awk '{ print $1}')
    else
        DEFAULT_PublicIP=192.168.0.1
    fi

    input_box "Your Public IP" \
    "Enter your public IP from the remote system you will access your admin panel from.\n\nWe have guessed your public IP from the IP used to access this system.\n\nGo to whatsmyip.org if you are unsure if this is your public IP.\n\nYour Public IP:" \
    "${DEFAULT_PublicIP}" \
    PublicIP

    if [ -z "${PublicIP}" ]; then
        exit
    fi
fi

# Function for secure password handling for database
generate_random_password_database() {
    local default_value=$1
    local variable_name=$2
    if [ -z "${!variable_name:-}" ]; then
        local default_password=$(openssl rand -base64 29 | tr -d "=+/")
        input_box "Database Password" \
        "Enter your desired database password.\n\nYou may use the system generated password shown.\n\nDesired Database Password:" \
        "${default_password}" \
        "${variable_name}"

        if [ -z "${!variable_name}" ]; then
            exit
        fi
    fi
}

# Function for secure password handling for YiiMP admin panel
generate_random_password_yiimp_admin() {
    local default_value=$1
    local variable_name=$2
    if [ -z "${!variable_name:-}" ]; then
        local default_password=$(openssl rand -base64 29 | tr -d "=+/")
        input_box "Admin Password" \
        "Enter your desired admin password for YiiMP panel.\n\nYou may use the system generated password shown.\n\nThis will be used to login to your admin panel.\n\nDesired Admin Password:" \
        "${default_password}" \
        "${variable_name}"

        if [ -z "${!variable_name}" ]; then
            exit
        fi
    fi
}

# Function for secure password handling for blocknotify
generate_random_password_blocknotify() {
    local default_value=$1
    local variable_name=$2
    if [ -z "${!variable_name:-}" ]; then
        local default_password=$(openssl rand -base64 29 | tr -d "=+/")
        input_box "Blocknotify Password" \
        "Enter your desired blocknotify password.\n\nYou may use the system generated password shown.\n\nThis will be used for coin blocknotify.\n\nDesired Blocknotify Password:" \
        "${default_password}" \
        "${variable_name}"

        if [ -z "${!variable_name}" ]; then
            exit
        fi
    fi
}

# Function for YiiMP admin username
generate_yiimp_admin_user() {
    local default_value=$1
    local variable_name=$2
    if [ -z "${!variable_name:-}" ]; then
        local default_username="admin"
        input_box "Admin Username" \
        "Enter your desired admin username for YiiMP panel.\n\nThis will be used to login to your admin panel.\n\nDefault username is 'admin'.\n\nDesired Admin Username:" \
        "${default_username}" \
        "${variable_name}"

        if [ -z "${!variable_name}" ]; then
            exit
        fi
    fi
}

# Function for phpMyAdmin username
generate_phpmyadmin_user() {
    local default_value=$1
    local variable_name=$2
    if [ -z "${!variable_name:-}" ]; then
        local default_username="phpmyadmin"
        input_box "phpMyAdmin Username" \
        "Enter your desired username for phpMyAdmin.\n\nThis will be used to login to phpMyAdmin.\n\nDefault username is 'phpmyadmin'.\n\nDesired phpMyAdmin Username:" \
        "${default_username}" \
        "${variable_name}"

        if [ -z "${!variable_name}" ]; then
            exit
        fi
    fi
}

# Function for phpMyAdmin password
generate_random_password_phpmyadmin() {
    local default_value=$1
    local variable_name=$2
    if [ -z "${!variable_name:-}" ]; then
        local default_password=$(openssl rand -base64 29 | tr -d "=+/")
        input_box "phpMyAdmin Password" \
        "Enter your desired password for phpMyAdmin.\n\nYou may use the system generated password shown.\n\nThis will be used to login to phpMyAdmin.\n\nDesired phpMyAdmin Password:" \
        "${default_password}" \
        "${variable_name}"

        if [ -z "${!variable_name}" ]; then
            exit
        fi
    fi
}

# Generate database passwords
generate_random_password_database "${DEFAULT_DBRootPassword}" "DBRootPassword"
generate_random_password_database "${DEFAULT_PanelUserDBPassword}" "PanelUserDBPassword"
generate_random_password_database "${DEFAULT_StratumUserDBPassword}" "StratumUserDBPassword"

# Generate YiiMP admin credentials
generate_yiimp_admin_user "${DEFAULT_AdminUser}" "AdminUser"
generate_random_password_yiimp_admin "${DEFAULT_AdminPassword}" "AdminPassword"

# Generate phpMyAdmin credentials
generate_phpmyadmin_user "${DEFAULT_PHPMyAdminUser}" "PHPMyAdminUser"
generate_random_password_phpmyadmin "${DEFAULT_PHPMyAdminPassword}" "PHPMyAdminPassword"

# Generate blocknotify password
generate_random_password_blocknotify "${DEFAULT_BlocknotifyPassword}" "BlocknotifyPassword"

# Generate unique names for YiiMP DB and users for increased security
YiiMPDBName=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13)
YiiMPPanelName=Panel$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13)
StratumDBUser=Stratum$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13)

clear

# Display confirmation dialog for user to verify inputs
dialog --title "Verify Your Responses" \
--yesno "Please verify your input before continuing:
Using Domain          : ${UsingDomain}
Using Sub-Domain      : ${UsingSubDomain}
Domain Name           : ${DomainName}
Stratum URL          : ${StratumURL}
Install SSL           : ${InstallSSL}
System Email          : ${SupportEmail}
Your Public IP        : ${PublicIP}
phpMyAdmin Username   : ${PHPMyAdminUser}" 17 60

# Get exit status of confirmation dialog
# 0 means user confirmed, 1 means user canceled
response=$?
case $response in
    0)
        # Save configuration to .yiimp.conf
        if [[ ("$wireguard" == "true") ]]; then
            echo "STORAGE_USER=${STORAGE_USER}
                  STORAGE_ROOT=${STORAGE_ROOT}
                  PRIMARY_HOSTNAME=${DomainName}
                  UsingDomain=${UsingDomain}
                  UsingSubDomain=${UsingSubDomain}
                  DomainName=${DomainName}
                  StratumURL=${StratumURL}
                  InstallSSL=${InstallSSL}
                  SupportEmail=${SupportEmail}
                  PublicIP=${PublicIP}
                  AutoExchange=${AutoExchange}
                  DBInternalIP=${DBInternalIP}
                  YiiMPDBName=${YiiMPDBName}
                  DBRootPassword='${DBRootPassword}'
                  YiiMPPanelName=${YiiMPPanelName}
                  PanelUserDBPassword='${PanelUserDBPassword}'
                  StratumDBUser=${StratumDBUser}
                  StratumUserDBPassword='${StratumUserDBPassword}'
                  AdminPassword='${AdminPassword}'
                  AdminUser='${AdminUser}'
                  PHPMyAdminUser='${PHPMyAdminUser}'
                  PHPMyAdminPassword='${PHPMyAdminPassword}'
                  BlocknotifyPassword='${BlocknotifyPassword}'
                  USE_AAPANEL='${USE_AAPANEL}'
                  WEB_SERVER_TYPE='${WEB_SERVER_TYPE}'
                  SKIP_WEB_SERVER_INSTALL='${SKIP_WEB_SERVER_INSTALL}'
                  SKIP_PHP_INSTALL='${SKIP_PHP_INSTALL}'
                  SKIP_MYSQL_INSTALL='${SKIP_MYSQL_INSTALL}'
                  AAPANEL_SITE_ROOT='${AAPANEL_SITE_ROOT}'
                  PHP_VERSION='${PHP_VERSION}'
                  DEDICATED_DB_SERVER_IP='${DEDICATED_DB_SERVER_IP}'
                  USE_PRIVATE_WEB_REPO='${USE_PRIVATE_WEB_REPO}'
                  PRIVATE_WEB_REPO_URL='${PRIVATE_WEB_REPO_URL}'
                  SSH_PRIVATE_KEY_PATH='${SSH_PRIVATE_KEY_PATH}'
                  SSH_PRIVATE_KEY_CONTENT='${SSH_PRIVATE_KEY_CONTENT}'
                  YiiMPRepo='https://github.com/Kudaraidee/yiimp.git'" | sudo -E tee "$STORAGE_ROOT/yiimp/.yiimp.conf" >/dev/null 2>&1
        else
            echo "STORAGE_USER=${STORAGE_USER}
                  STORAGE_ROOT=${STORAGE_ROOT}
                  PRIMARY_HOSTNAME=${DomainName}
                  UsingDomain=${UsingDomain}
                  UsingSubDomain=${UsingSubDomain}
                  DomainName=${DomainName}
                  StratumURL=${StratumURL}
                  InstallSSL=${InstallSSL}
                  SupportEmail=${SupportEmail}
                  PublicIP=${PublicIP}
                  AutoExchange=${AutoExchange}
                  YiiMPDBName=${YiiMPDBName}
                  DBRootPassword='${DBRootPassword}'
                  YiiMPPanelName=${YiiMPPanelName}
                  PanelUserDBPassword='${PanelUserDBPassword}'
                  StratumDBUser=${StratumDBUser}
                  StratumUserDBPassword='${StratumUserDBPassword}'
                  AdminPassword='${AdminPassword}'
                  AdminUser='${AdminUser}'
                  PHPMyAdminUser='${PHPMyAdminUser}'
                  PHPMyAdminPassword='${PHPMyAdminPassword}'
                  BlocknotifyPassword='${BlocknotifyPassword}'
                  USE_AAPANEL='${USE_AAPANEL}'
                  WEB_SERVER_TYPE='${WEB_SERVER_TYPE}'
                  SKIP_WEB_SERVER_INSTALL='${SKIP_WEB_SERVER_INSTALL}'
                  SKIP_PHP_INSTALL='${SKIP_PHP_INSTALL}'
                  SKIP_MYSQL_INSTALL='${SKIP_MYSQL_INSTALL}'
                  AAPANEL_SITE_ROOT='${AAPANEL_SITE_ROOT}'
                  PHP_VERSION='${PHP_VERSION}'
                  DEDICATED_DB_SERVER_IP='${DEDICATED_DB_SERVER_IP}'
                  USE_PRIVATE_WEB_REPO='${USE_PRIVATE_WEB_REPO}'
                  PRIVATE_WEB_REPO_URL='${PRIVATE_WEB_REPO_URL}'
                  SSH_PRIVATE_KEY_PATH='${SSH_PRIVATE_KEY_PATH}'
                  SSH_PRIVATE_KEY_CONTENT='${SSH_PRIVATE_KEY_CONTENT}'
                  YiiMPRepo='https://github.com/Kudaraidee/yiimp.git'" | sudo -E tee "$STORAGE_ROOT/yiimp/.yiimp.conf" >/dev/null 2>&1
        fi
        ;;
    1)
        # Restart script if user cancels
        clear
        bash "$(basename "$0")" && exit
        ;;
    255)
        clear
        echo "User canceled installation"
        exit 0
        ;;
esac

cd $HOME/Yiimpoolv1/yiimp_single