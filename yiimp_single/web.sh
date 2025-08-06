#!/usr/bin/env bash

#####################################################
# Source https://mailinabox.email/ https://github.com/mail-in-a-box/mailinabox
# Updated by afiniel for crypto use...
#####################################################

# Load configuration files
source /etc/functions.sh
source /etc/yiimpool.conf
source $STORAGE_ROOT/yiimp/.yiimp.conf
source $HOME/Yiimpoolv1/yiimp_single/.wireguard.install.cnf

# Set default values if not defined (for backward compatibility)
USE_AAPANEL=${USE_AAPANEL:-"no"}
WEB_SERVER_TYPE=${WEB_SERVER_TYPE:-"nginx"}
SKIP_WEB_SERVER_INSTALL=${SKIP_WEB_SERVER_INSTALL:-"false"}
AAPANEL_SITE_ROOT=${AAPANEL_SITE_ROOT:-"/var/www/${DomainName}/html"}
PHP_VERSION=${PHP_VERSION:-"8.1"}

set -eu -o pipefail

function print_error {
  read line file <<<$(caller)
  echo "An error occurred in line $line of file $file:" >&2
  sed "${line}q;d" "$file" >&2
}
trap print_error ERR
term_art

print_header "YiiMP Web Configuration"

# Load WireGuard configuration if enabled
if [[ ("$wireguard" == "true") ]]; then
    source $STORAGE_ROOT/yiimp/.wireguard.conf
fi

print_header "Web File Structure Setup"

if [[ "${USE_AAPANEL}" == "yes" ]]; then
    print_status "Setting up YiiMP for aaPanel (${WEB_SERVER_TYPE})..."

    # Ensure aaPanel site directory exists
    if [ ! -d "${AAPANEL_SITE_ROOT}" ]; then
        print_error "aaPanel site directory does not exist: ${AAPANEL_SITE_ROOT}"
        print_info "Please create the site in aaPanel first or check the path"
        exit 1
    fi

    # Copy YiiMP web files to aaPanel site directory
    print_status "Copying YiiMP files to aaPanel site directory..."
    cd $STORAGE_ROOT/yiimp/yiimp_setup/yiimp
    sudo cp -r $STORAGE_ROOT/yiimp/yiimp_setup/yiimp/web/* ${AAPANEL_SITE_ROOT}/

    # Create YiiMP site directory structure for compatibility
    sudo mkdir -p $STORAGE_ROOT/yiimp/site/

    # Create symlink for easier management
    sudo ln -sf ${AAPANEL_SITE_ROOT} $STORAGE_ROOT/yiimp/site/web

    print_success "YiiMP files copied to aaPanel site directory"
else
    print_status "Setting up YiiMP for standard installation..."

    # Standard YiiMP installation
    cd $STORAGE_ROOT/yiimp/yiimp_setup/yiimp
    sudo cp -r $STORAGE_ROOT/yiimp/yiimp_setup/yiimp/web $STORAGE_ROOT/yiimp/site/

    print_status "Creating standard directory structure..."
    sudo mkdir -p /var/www/${DomainName}/html

    print_success "Standard YiiMP directory structure created"
fi

print_status "Installing Yiimp binary files..."
cd $STORAGE_ROOT/yiimp/yiimp_setup/
sudo cp -r $STORAGE_ROOT/yiimp/yiimp_setup/yiimp/bin/. /bin/

print_status "Creating required directories..."
sudo mkdir -p /etc/yiimp
sudo mkdir -p $STORAGE_ROOT/yiimp/site/backup/

print_status "Updating YiiMP configuration..."
sudo sed -i "s|ROOTDIR=/data/yiimp|ROOTDIR=${STORAGE_ROOT}/yiimp/site|g" /bin/yiimp

print_header "Web Server Configuration"

if [[ "${SKIP_WEB_SERVER_INSTALL}" == "true" ]]; then
    print_info "Skipping web server configuration - using existing ${WEB_SERVER_TYPE}"

    # Configure based on web server type
    case "${WEB_SERVER_TYPE}" in
        "openlitespeed")
            print_status "Configuring OpenLiteSpeed..."
            cd $HOME/Yiimpoolv1/yiimp_single
            source openlitespeed_config.sh
            ;;
        "nginx")
            print_info "Using existing nginx configuration"
            print_info "Please ensure your nginx configuration includes YiiMP rewrite rules"
            ;;
        "apache")
            print_info "Using existing Apache configuration"
            print_info "Please ensure your Apache configuration includes YiiMP rewrite rules"
            ;;
        *)
            print_warning "Unknown web server type: ${WEB_SERVER_TYPE}"
            print_info "Please configure your web server manually for YiiMP"
            ;;
    esac
else
    print_header "NGINX Configuration"
    if [[ "${UsingSubDomain,,}" == "yes" ]]; then
        print_status "Configuring subdomain setup..."
        cd $HOME/Yiimpoolv1/yiimp_single
        source nginx_subdomain_nonssl.sh
        if [[ "${InstallSSL,,}" == "yes" ]]; then
            print_status "Configuring SSL for subdomain..."
            cd $HOME/Yiimpoolv1/yiimp_single
            source nginx_subdomain_ssl.sh
        fi
    else
        print_status "Configuring main domain setup..."
        cd $HOME/Yiimpoolv1/yiimp_single
        source nginx_domain_nonssl.sh
        if [[ "${InstallSSL,,}" == "yes" ]]; then
            print_status "Configuring SSL for main domain..."
            cd $HOME/Yiimpoolv1/yiimp_single
            source nginx_domain_ssl.sh
        fi
    fi
fi

print_header "YiiMP Configuration"
print_status "Creating configuration files..."
cd $HOME/Yiimpoolv1/yiimp_single
source yiimp_confs/keys.sh
source yiimp_confs/yiimpserverconfig.sh
source yiimp_confs/main.sh
source yiimp_confs/loop2.sh
source yiimp_confs/blocks.sh

print_header "Permission Setup"
print_status "Setting folder permissions..."
whoami=$(whoami)
sudo usermod -aG www-data $whoami
sudo usermod -a -G www-data $whoami
sudo usermod -a -G crypto-data $whoami
sudo usermod -a -G crypto-data www-data

print_status "Setting directory permissions..."
sudo find $STORAGE_ROOT/yiimp/site/ -type d -exec chmod 775 {} +
sudo find $STORAGE_ROOT/yiimp/site/ -type f -exec chmod 664 {} +

sudo chgrp www-data $STORAGE_ROOT -R
sudo chmod g+w $STORAGE_ROOT -R

print_header "YiiMP Customization"
print_status "Applying YiimPool customizations..."

sudo sed -i 's/YII MINING POOLS/'${DomainName}' Mining Pool/g' $STORAGE_ROOT/yiimp/site/web/yaamp/modules/site/index.php
sudo sed -i 's/domain/'${DomainName}'/g' $STORAGE_ROOT/yiimp/site/web/yaamp/modules/site/index.php
sudo sed -i 's/Notes/AddNodes/g' $STORAGE_ROOT/yiimp/site/web/yaamp/models/db_coinsModel.php

print_status "Creating configuration symlinks..."
sudo ln -s ${STORAGE_ROOT}/yiimp/site/configuration/serverconfig.php /etc/yiimp/serverconfig.php

print_status "Updating PHP version references..."

# Update nginx configuration files to use the correct PHP version
if [[ "${SKIP_WEB_SERVER_INSTALL}" != "true" && "${WEB_SERVER_TYPE}" == "nginx" ]]; then
    print_status "Updating nginx PHP-FPM socket references..."

    # Update php_fastcgi.conf
    sudo sed -i "s|php8\.1-fpm\.sock|php${PHP_VERSION}-fpm.sock|g" $HOME/Yiimpoolv1/yiimp_single/nginx_confs/php_fastcgi.conf

    # Update phpmyadmin.conf
    sudo sed -i "s|php8\.1-fpm\.sock|php${PHP_VERSION}-fpm.sock|g" $HOME/Yiimpoolv1/yiimp_single/nginx_confs/phpmyadmin.conf

    # Update any other nginx configuration files that might have PHP version references
    find $HOME/Yiimpoolv1/yiimp_single/nginx_confs/ -name "*.conf" -exec sudo sed -i "s|php8\.1-fpm\.sock|php${PHP_VERSION}-fpm.sock|g" {} \;
    find $HOME/Yiimpoolv1/yiimp_single/nginx_confs/ -name "*.conf" -exec sudo sed -i "s|php7\.2-fpm\.sock|php${PHP_VERSION}-fpm.sock|g" {} \;

    print_success "Nginx PHP version references updated to ${PHP_VERSION}"
fi

print_status "Updating configuration paths..."

# Determine the correct web root path
if [[ "${USE_AAPANEL}" == "yes" ]]; then
    WEB_ROOT_PATH="${AAPANEL_SITE_ROOT}"
else
    WEB_ROOT_PATH="$STORAGE_ROOT/yiimp/site/web"
fi

# Update configuration paths in YiiMP files
sudo sed -i "s|${STORAGE_ROOT}/yiimp/site/configuration/serverconfig.php|/etc/yiimp/serverconfig.php|g" ${WEB_ROOT_PATH}/index.php
sudo sed -i "s|${STORAGE_ROOT}/yiimp/site/configuration/serverconfig.php|/etc/yiimp/serverconfig.php|g" ${WEB_ROOT_PATH}/runconsole.php
sudo sed -i "s|${STORAGE_ROOT}/yiimp/site/configuration/serverconfig.php|/etc/yiimp/serverconfig.php|g" ${WEB_ROOT_PATH}/run.php
sudo sed -i "s|${STORAGE_ROOT}/yiimp/site/configuration/serverconfig.php|/etc/yiimp/serverconfig.php|g" ${WEB_ROOT_PATH}/yaamp/yiic.php
sudo sed -i "s|${STORAGE_ROOT}/yiimp/site/configuration/serverconfig.php|/etc/yiimp/serverconfig.php|g" ${WEB_ROOT_PATH}/yaamp/modules/thread/CronjobController.php

sudo sed -i "s|require_once('serverconfig.php')|require_once('/etc/yiimp/serverconfig.php')|g" ${WEB_ROOT_PATH}/yaamp/yiic.php

sudo sed -i "s|/root/backup|${STORAGE_ROOT}/yiimp/site/backup|g" ${WEB_ROOT_PATH}/yaamp/core/backend/system.php

# Update service management commands based on web server type
case "${WEB_SERVER_TYPE}" in
    "openlitespeed")
        sudo sed -i 's/service $webserver start/sudo systemctl start lsws/g' ${WEB_ROOT_PATH}/yaamp/modules/thread/CronjobController.php
        sudo sed -i 's/service nginx stop/sudo systemctl stop lsws/g' ${WEB_ROOT_PATH}/yaamp/modules/thread/CronjobController.php
        sudo sed -i 's/service nginx start/sudo systemctl start lsws/g' ${WEB_ROOT_PATH}/yaamp/modules/thread/CronjobController.php
        ;;
    "apache")
        sudo sed -i 's/service $webserver start/sudo systemctl start apache2/g' ${WEB_ROOT_PATH}/yaamp/modules/thread/CronjobController.php
        sudo sed -i 's/service nginx stop/sudo systemctl stop apache2/g' ${WEB_ROOT_PATH}/yaamp/modules/thread/CronjobController.php
        sudo sed -i 's/service nginx start/sudo systemctl start apache2/g' ${WEB_ROOT_PATH}/yaamp/modules/thread/CronjobController.php
        ;;
    *)
        # Default nginx commands
        sudo sed -i 's/service $webserver start/sudo service nginx start/g' ${WEB_ROOT_PATH}/yaamp/modules/thread/CronjobController.php
        sudo sed -i 's/service nginx stop/sudo service nginx stop/g' ${WEB_ROOT_PATH}/yaamp/modules/thread/CronjobController.php
        ;;
esac

if [[ ("$wireguard" == "true") ]]; then
    print_status "Configuring WireGuard internal network..."
    internalrpcip=$DBInternalIP
    internalrpcip="${DBInternalIP::-1}"
    internalrpcip="${internalrpcip::-1}"
    internalrpcip=$internalrpcip.0/26
    sudo sed -i '/# onlynet=ipv4/i\        echo "rpcallowip='${internalrpcip}'\\n";' $STORAGE_ROOT/yiimp/site/web/yaamp/modules/site/coin_form.php
fi

print_header "Keys Configuration"
print_status "Setting up unified keys configuration..."
sudo ln -s /home/crypto-data/yiimp/site/configuration/keys.php /etc/yiimp/keys.php

print_status "Updating exchange configuration paths..."
sudo find $STORAGE_ROOT/yiimp/site/web/yaamp/core/exchange/ -type f -name "*.php" -exec sed -i 's|require_once.*keys.php.*|if (!defined('\''EXCH_POLONIEX_KEY'\'')) {\n    require_once('\''/etc/yiimp/keys.php'\'');\n}|g' {} +

print_status "Updating trading configuration paths..."
sudo find $STORAGE_ROOT/yiimp/site/web/yaamp/core/trading/ -type f -name "*.php" -exec sed -i 's|require_once.*keys.php.*|if (!defined('\''EXCH_POLONIEX_KEY'\'')) {\n    require_once('\''/etc/yiimp/keys.php'\'');\n}|g' {} +

print_success "YiiMP web configuration completed successfully"

print_header "Configuration Summary"
print_info "Domain: ${DomainName}"
if [[ "${USE_AAPANEL}" == "yes" ]]; then
    print_info "Web Server: ${WEB_SERVER_TYPE} (via aaPanel)"
    print_info "Web Root: ${AAPANEL_SITE_ROOT}"
    print_info "PHP Version: ${PHP_VERSION}"
else
    print_info "Web Server: nginx (standard installation)"
    print_info "Web Root: /var/www/${DomainName}/html"
fi
print_info "YiiMP Root: ${STORAGE_ROOT}/yiimp/site"
print_info "Configuration: /etc/yiimp"
print_info "Backup Directory: ${STORAGE_ROOT}/yiimp/site/backup"

print_divider

set +eu +o pipefail

cd $HOME/Yiimpoolv1/yiimp_single