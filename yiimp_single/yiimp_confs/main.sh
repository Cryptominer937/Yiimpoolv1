#!/usr/bin/env bash

#########################################
# Created by Afiniel for Yiimpool use...#
#########################################

source /etc/functions.sh
source /etc/yiimpool.conf
source $STORAGE_ROOT/yiimp/.yiimp.conf
source $HOME/Yiimpoolv1/yiimp_single/.wireguard.install.cnf

# Determine the correct web directory path
if [[ "${USE_AAPANEL}" == "yes" ]]; then
    WEB_DIR="${AAPANEL_SITE_ROOT}"
    print_info "Using aaPanel web directory: ${AAPANEL_SITE_ROOT}"
else
    WEB_DIR="${STORAGE_ROOT}/yiimp/site/web"
    print_info "Using standard web directory: ${STORAGE_ROOT}/yiimp/site/web"
fi

# Create main.sh
echo '#!/usr/bin/env bash
PHP_CLI='"'"''"php -d max_execution_time=120"''"'"'
DIR='""''"${WEB_DIR}"''""'/
cd ${DIR}
date
echo started in ${DIR}
while true; do
${PHP_CLI} runconsole.php cronjob/run
sleep 90
done
exec bash' | sudo -E tee $STORAGE_ROOT/yiimp/site/crons/main.sh >/dev/null 2>&1
sudo chmod +x $STORAGE_ROOT/yiimp/site/crons/main.sh

cd $HOME/Yiimpoolv1/yiimp_single
