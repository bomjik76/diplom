#!/bin/bash

# Цвета для лучшей читаемости
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # Без цвета

# Функция для вывода цветных сообщений
print_message() {
    echo -e "${2}${1}${NC}"
}

# Функция для проверки запуска от имени root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_message "Пожалуйста, запустите скрипт от имени root или с sudo" "$RED"
        exit 1
    fi
}

# Функция для проверки системных требований
check_requirements() {
    print_message "Проверка системных требований..." "$YELLOW"
    
    # Проверка, является ли система RedHat-based
    if [ ! -f /etc/redhat-release ]; then
        print_message "Этот скрипт предназначен только для систем на базе RedHat!" "$RED"
        exit 1
    fi
}

# Функция для установки необходимых пакетов
install_dependencies() {
    print_message "Установка необходимых пакетов..." "$YELLOW"
    
    dnf update -y
    dnf install -y epel-release
    dnf install -y httpd mariadb mariadb-server php php-mysqlnd php-gd php-xml php-mbstring \
        php-json php-intl php-pecl-zip php-process unzip wget php-opcache php-pecl-apcu \
        php-gmp php-zip firewalld
}

# Функция для настройки MariaDB
configure_database() {
    print_message "Настройка MariaDB..." "$YELLOW"
    
    # Запуск и включение MariaDB
    systemctl start mariadb
    systemctl enable mariadb
    
    # Запрос данных для базы данных
    read -p "Введите имя базы данных NextCloud [nextcloud]: " db_name
    db_name=${db_name:-nextcloud}
    
    read -p "Введите имя пользователя базы данных [nextcloud]: " db_user
    db_user=${db_user:-nextcloud}
    
    read -s -p "Введите пароль для базы данных: " db_pass
    echo
    
    # Создание базы данных и пользователя
    mysql -e "CREATE DATABASE ${db_name};"
    mysql -e "CREATE USER '${db_user}'@'localhost' IDENTIFIED BY '${db_pass}';"
    mysql -e "GRANT ALL PRIVILEGES ON ${db_name}.* TO '${db_user}'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
}

# Функция для настройки Apache
configure_apache() {
    print_message "Настройка Apache..." "$YELLOW"
    
    # Включение и запуск Apache
    systemctl enable httpd
    systemctl start httpd
    
    # Настройка файервола
    systemctl enable firewalld
    systemctl start firewalld
    firewall-cmd --permanent --add-service=http
    firewall-cmd --permanent --add-service=https
    firewall-cmd --reload
}

# Функция для загрузки и установки NextCloud
install_nextcloud() {
    print_message "Установка NextCloud..." "$YELLOW"
    
    # Загрузка последней версии NextCloud
    cd /var/www/html
    wget https://download.nextcloud.com/server/releases/latest.zip
    unzip latest.zip
    
    # Создание каталога данных
    mkdir -p /var/www/html/nextcloud/data
    
    # Установка корректных прав доступа
    chown -R apache:apache /var/www/html/nextcloud
    find /var/www/html/nextcloud/ -type d -exec chmod 750 {} \;
    find /var/www/html/nextcloud/ -type f -exec chmod 640 {} \;
    
    # Установка специальных прав для директорий, требующих запись
    chmod 770 /var/www/html/nextcloud/data
    chmod 770 /var/www/html/nextcloud/config
    chmod 770 /var/www/html/nextcloud/apps
    chmod 770 /var/www/html/nextcloud/assets
    
    # Создание конфигурации Apache
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

    # Перезапуск Apache
    systemctl restart httpd
}

# Функция для настройки SELinux
configure_selinux() {
    print_message "Настройка SELinux..." "$YELLOW"
    
    # Установка утилит SELinux
    dnf install -y policycoreutils-python-utils
    
    # Установка контекстов SELinux
    semanage fcontext -a -t httpd_sys_rw_content_t '/var/www/html/nextcloud/data(/.*)?'
    semanage fcontext -a -t httpd_sys_rw_content_t '/var/www/html/nextcloud/config(/.*)?'
    semanage fcontext -a -t httpd_sys_rw_content_t '/var/www/html/nextcloud/apps(/.*)?'
    semanage fcontext -a -t httpd_sys_rw_content_t '/var/www/html/nextcloud/assets(/.*)?'
    semanage fcontext -a -t httpd_sys_rw_content_t '/var/www/html/nextcloud/.htaccess'
    semanage fcontext -a -t httpd_sys_rw_content_t '/var/www/html/nextcloud/.user.ini'
    
    # Применение контекстов
    restorecon -R '/var/www/html/nextcloud/'
    
    # Дополнительные настройки SELinux
    setsebool -P httpd_can_network_connect on
    setsebool -P httpd_unified on
    
    # Разрешение Apache записи в каталог данных
    semanage fcontext -a -t httpd_sys_rw_content_t "/var/www/html/nextcloud/data(/.*)?"
    restorecon -R '/var/www/html/nextcloud/data'
}

# Основной процесс установки
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
    print_message "Пожалуйста, завершите настройку, перейдя по адресу http://$(hostname)" "$GREEN"
    print_message "Используйте следующие данные для базы данных:" "$YELLOW"
    print_message "База данных: ${db_name}" "$YELLOW"
    print_message "Пользователь БД: ${db_user}" "$YELLOW"
    print_message "Пароль БД: [Пароль, который вы ввели]" "$YELLOW"
}

# Запуск установки
main 