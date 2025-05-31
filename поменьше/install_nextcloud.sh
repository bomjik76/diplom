#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
print_message() {
    echo -e "${2}${1}${NC}"
}
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_message "Пожалуйста, запустите скрипт от имени root или с sudo" "$RED"
        exit 1
    fi
}
check_requirements() {
    print_message "Проверка системных требований..." "$YELLOW"
    if [ ! -f /etc/redhat-release ]; then
        print_message "Этот скрипт предназначен только для систем на базе RedHat!" "$RED"
        exit 1
    fi
}
install_dependencies() {
    print_message "Установка необходимых пакетов..." "$YELLOW"
    dnf update -y
    dnf install -y epel-release
    dnf install -y httpd mariadb mariadb-server php php-mysqlnd php-gd php-xml php-mbstring \
        php-json php-intl php-pecl-zip php-process unzip wget php-opcache php-pecl-apcu \
        php-gmp php-zip firewalld
}
configure_database() {
    print_message "Настройка MariaDB..." "$YELLOW"
    systemctl start mariadb
    systemctl enable mariadb
    read -p "Введите имя базы данных NextCloud [nextcloud]: " db_name
    db_name=${db_name:-nextcloud}
    read -p "Введите имя пользователя базы данных [nextcloud]: " db_user
    db_user=${db_user:-nextcloud}
    read -s -p "Введите пароль для базы данных: " db_pass
    echo
    mysql -e "CREATE DATABASE ${db_name};"
    mysql -e "CREATE USER '${db_user}'@'localhost' IDENTIFIED BY '${db_pass}';"
    mysql -e "GRANT ALL PRIVILEGES ON ${db_name}.* TO '${db_user}'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
}
configure_apache() {
    print_message "Настройка Apache..." "$YELLOW"
    systemctl enable httpd
    systemctl start httpd
    systemctl enable firewalld
    systemctl start firewalld
    firewall-cmd --permanent --add-service=http
    firewall-cmd --permanent --add-service=https
    firewall-cmd --reload
}
install_nextcloud() {
    print_message "Установка NextCloud..." "$YELLOW"
    cd /var/www/html
    wget https://download.nextcloud.com/server/releases/latest.zip
    unzip latest.zip
    mkdir -p /var/www/html/nextcloud/data
    chown -R apache:apache /var/www/html/nextcloud
    find /var/www/html/nextcloud/ -type d -exec chmod 750 {} \;
    find /var/www/html/nextcloud/ -type f -exec chmod 640 {} \;
    chmod 770 /var/www/html/nextcloud/data
    chmod 770 /var/www/html/nextcloud/config
    chmod 770 /var/www/html/nextcloud/apps
    chmod 770 /var/www/html/nextcloud/assets
    cat > /etc/httpd/conf.d/nextcloud.conf << EOF
<VirtualHost *:80>
    DocumentRoot /var/www/html/nextcloud
    ServerName $(hostname)
    <Directory /var/www/html/nextcloud/>
        Options +FollowSymlinks
        AllowOverride All
        Require all granted
        SetEnv HOME /var/www/html/nextcloud
        SetEnv HTTP_HOME /var/www/html/nextcloud
    </Directory>
</VirtualHost>
EOF
    systemctl restart httpd
}
configure_selinux() {
    print_message "Настройка SELinux..." "$YELLOW"
    dnf install -y policycoreutils-python-utils
    semanage fcontext -a -t httpd_sys_rw_content_t '/var/www/html/nextcloud/data(/.*)?'
    semanage fcontext -a -t httpd_sys_rw_content_t '/var/www/html/nextcloud/config(/.*)?'
    semanage fcontext -a -t httpd_sys_rw_content_t '/var/www/html/nextcloud/apps(/.*)?'
    semanage fcontext -a -t httpd_sys_rw_content_t '/var/www/html/nextcloud/assets(/.*)?'
    semanage fcontext -a -t httpd_sys_rw_content_t '/var/www/html/nextcloud/.htaccess'
    semanage fcontext -a -t httpd_sys_rw_content_t '/var/www/html/nextcloud/.user.ini'
    restorecon -R '/var/www/html/nextcloud/'
    setsebool -P httpd_can_network_connect on
    setsebool -P httpd_unified on
    semanage fcontext -a -t httpd_sys_rw_content_t "/var/www/html/nextcloud/data(/.*)?"
    restorecon -R '/var/www/html/nextcloud/data'
}
main() {
    print_message "Начало установки NextCloud..." "$GREEN"
    check_root
    check_requirements
    install_dependencies
    configure_database
    configure_apache
    install_nextcloud
    configure_selinux
    print_message "\nУстановка NextCloud завершена!" "$GREEN"
    print_message "Пожалуйста, завершите настройку, перейдя по адресу http://$(hostname)/nextcloud" "$GREEN"
    print_message "Используйте следующие данные для базы данных:" "$YELLOW"
    print_message "База данных: ${db_name}" "$YELLOW"
    print_message "Пользователь БД: ${db_user}" "$YELLOW"
    print_message "Пароль БД: [Пароль, который вы ввели]" "$YELLOW"
}
main