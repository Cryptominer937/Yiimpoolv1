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

# Private repository configuration
USE_PRIVATE_WEB_REPO=${USE_PRIVATE_WEB_REPO:-"no"}
PRIVATE_WEB_REPO_URL=${PRIVATE_WEB_REPO_URL:-""}
SSH_PRIVATE_KEY_PATH=${SSH_PRIVATE_KEY_PATH:-""}
SSH_PRIVATE_KEY_CONTENT=${SSH_PRIVATE_KEY_CONTENT:-""}

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

    if [[ "${USE_AAPANEL}" == "yes" ]]; then
        print_header "aaPanel Configuration Verification Required"
        print_warning "IMPORTANT: Before continuing, verify these aaPanel configurations:"

        print_info "1. SSL Certificate Configuration:"
        print_info "   • Go to Website > SSL in aaPanel"
        print_info "   • Select your domain: ${DomainName}"
        print_info "   • Configure Let's Encrypt or upload certificates"
        print_info "   • Enable Force HTTPS if desired"
        print_info ""

        print_info "2. YiiMP Cron Jobs Setup (CRITICAL):"
        print_info "   • Go to Cron in aaPanel"
        print_info "   • Add these 3 cron jobs:"
        print_info ""
        print_info "   Main Processing (every minute):"
        print_info "   * * * * * cd ${AAPANEL_SITE_ROOT} && php runconsole.php cronjob/run"
        print_info ""
        print_info "   Loop2 Processing (every minute):"
        print_info "   * * * * * cd ${AAPANEL_SITE_ROOT} && php runconsole.php cronjob/runLoop2"
        print_info ""
        print_info "   Block Processing (every minute):"
        print_info "   * * * * * cd ${AAPANEL_SITE_ROOT} && php runconsole.php cronjob/runBlocks"
        print_info ""

        print_info "3. PHP Configuration:"
        print_info "   • Ensure PHP ${PHP_VERSION} is selected for your site"
        print_info "   • Verify memcache extension is installed (if using OpenLiteSpeed)"
        print_info "   • Check PHP error logs if issues occur"
        print_info ""

        print_info "4. Database Connection:"
        if [[ "$wireguard" == "true" ]]; then
            print_info "   • Multi-server: Database connection will be configured automatically"
        else
            print_info "   • Single-server: Ensure YiiMP database and user exist in aaPanel"
            print_info "   • Database: ${YiiMPDBName}"
            print_info "   • User: ${YiiMPPanelName}"
        fi
        print_info ""

        # Confirmation dialog
        dialog --title "aaPanel Configuration Confirmation" \
        --yesno "Have you completed the required aaPanel configurations?\n\nRequired:\n✓ SSL certificate configured\n✓ YiiMP cron jobs added (3 jobs)\n✓ PHP ${PHP_VERSION} selected for site\n✓ Database ready (single-server only)\n✓ Memcache extension installed (OpenLiteSpeed)\n\nSelect 'Yes' if all configurations are complete.\nSelect 'No' to exit and complete configurations." 16 80
        response=$?
        case $response in
           0)
               print_success "aaPanel configurations confirmed - continuing installation"
               ;;
           1)
               print_error "Please complete the required aaPanel configurations:"
               print_info ""
               print_info "1. Configure SSL certificate in aaPanel"
               print_info "2. Add YiiMP cron jobs in aaPanel (see above for exact commands)"
               print_info "3. Ensure PHP ${PHP_VERSION} is selected"
               print_info "4. Verify database setup (single-server only)"
               print_info "5. Install memcache extension (OpenLiteSpeed only)"
               print_info ""
               print_info "Re-run this installer after completing these steps."
               exit 1
               ;;
           255)
               print_error "Installation cancelled"
               exit 1
               ;;
        esac
    fi

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
    print_info "SSL Management: aaPanel Interface"
    print_warning "Remember to configure SSL certificate in aaPanel!"
else
    print_info "Web Server: nginx (standard installation)"
    print_info "Web Root: /var/www/${DomainName}/html"
    if [[ "${InstallSSL,,}" == "yes" ]]; then
        print_info "SSL: Configured via Let's Encrypt"
    else
        print_info "SSL: Not configured"
    fi
fi
print_info "YiiMP Root: ${STORAGE_ROOT}/yiimp/site"
print_info "Configuration: /etc/yiimp"
print_info "Backup Directory: ${STORAGE_ROOT}/yiimp/site/backup"

print_divider

# Final aaPanel reminder
if [[ "${USE_AAPANEL}" == "yes" ]]; then
    print_header "FINAL REMINDER: aaPanel Cron Jobs"
    print_warning "Don't forget to verify your YiiMP cron jobs are running in aaPanel!"
    print_info ""
    print_info "Check in aaPanel > Cron that these 3 jobs are active:"
    print_info "1. Main: cd ${AAPANEL_SITE_ROOT} && php runconsole.php cronjob/run"
    print_info "2. Loop2: cd ${AAPANEL_SITE_ROOT} && php runconsole.php cronjob/runLoop2"
    print_info "3. Blocks: cd ${AAPANEL_SITE_ROOT} && php runconsole.php cronjob/runBlocks"
    print_info ""
    print_info "These cron jobs are ESSENTIAL for mining pool operation!"
    print_info "Without them, shares won't be processed and payouts won't work."
    print_divider
fi

print_success "YiiMP installation completed successfully!"

set +eu +o pipefail

cd $HOME/Yiimpoolv1/yiimp_single