#!/bin/bash

# Сканер безопасности для RHEL/CentOS
# Скрипт для проверки системы на типичные уязвимости и ошибки конфигурации

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Глобальные переменные
LOG_FILE="security_scan_$(date +%Y%m%d_%H%M%S).log"
REPORT_DIR="security_reports_$(date +%Y%m%d_%H%M%S)"
TEMP_DIR="/tmp/security_scanner_$$"
ERROR_COUNT=0
WARNING_COUNT=0

# Функция очистки при выходе
cleanup() {
    local exit_code=$?
    echo -e "\n${BLUE}Выполняется очистка...${NC}"
    
    # Удаление временных файлов
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
    
    # Если скрипт завершился с ошибкой, сохраняем лог
    if [ $exit_code -ne 0 ]; then
        echo -e "${RED}Скрипт завершился с ошибкой. Лог сохранен в $LOG_FILE${NC}"
    fi
    
    exit $exit_code
}

# Установка обработчика очистки
trap cleanup EXIT
trap 'echo -e "\n${RED}Прервано пользователем${NC}"; exit 1' INT TERM

# Функция для проверки прав root
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}Этот скрипт должен быть запущен с правами root${NC}"
        exit 1
    fi
}

# Функция для обработки ошибок
handle_error() {
    local error_msg="$1"
    local error_code="${2:-1}"
    
    ERROR_COUNT=$((ERROR_COUNT + 1))
    echo -e "${RED}ОШИБКА: $error_msg${NC}" | tee -a "$LOG_FILE"
    return $error_code
}

# Функция для обработки предупреждений
handle_warning() {
    local warning_msg="$1"
    
    WARNING_COUNT=$((WARNING_COUNT + 1))
    echo -e "${YELLOW}ПРЕДУПРЕЖДЕНИЕ: $warning_msg${NC}" | tee -a "$LOG_FILE"
}

# Функция для экспорта результатов
export_results() {
    print_header "Экспорт результатов"
    
    mkdir -p "$REPORT_DIR"
    
    # Экспорт в HTML
    generate_report
    
    # Экспорт в JSON
    {
        echo "{"
        echo "  \"scan_date\": \"$(date)\","
        echo "  \"hostname\": \"$(hostname)\","
        echo "  \"os_version\": \"$(cat /etc/redhat-release 2>/dev/null)\","
        echo "  \"selinux_status\": \"$(getenforce 2>/dev/null)\","
        echo "  \"firewall_status\": \"$(systemctl is-active firewalld 2>/dev/null)\","
        echo "  \"errors\": $ERROR_COUNT,"
        echo "  \"warnings\": $WARNING_COUNT"
        echo "}"
    } > "$REPORT_DIR/scan_results.json"
    
    # Экспорт в CSV
    {
        echo "Параметр,Значение"
        echo "Дата сканирования,$(date)"
        echo "Имя хоста,$(hostname)"
        echo "Версия ОС,$(cat /etc/redhat-release 2>/dev/null)"
        echo "Статус SELinux,$(getenforce 2>/dev/null)"
        echo "Статус брандмауэра,$(systemctl is-active firewalld 2>/dev/null)"
        echo "Количество ошибок,$ERROR_COUNT"
        echo "Количество предупреждений,$WARNING_COUNT"
    } > "$REPORT_DIR/scan_results.csv"
    
    # Архивирование результатов
    tar -czf "${REPORT_DIR}.tar.gz" -C "$(dirname "$REPORT_DIR")" "$(basename "$REPORT_DIR")"
    rm -rf "$REPORT_DIR"
    
    echo -e "${GREEN}Результаты экспортированы в ${REPORT_DIR}.tar.gz${NC}" | tee -a "$LOG_FILE"
}

# Функция для вывода заголовков
print_header() {
    echo -e "${BLUE}=========================================${NC}" | tee -a "$LOG_FILE"
    echo -e "${BLUE}$1${NC}" | tee -a "$LOG_FILE"
    echo -e "${BLUE}=========================================${NC}" | tee -a "$LOG_FILE"
}

# Функция для вывода результатов проверки
print_result() {
    if [ "$2" -eq 0 ]; then
        echo -e "[${GREEN}OK${NC}] $1" | tee -a "$LOG_FILE"
    else
        echo -e "[${RED}ВНИМАНИЕ${NC}] $1" | tee -a "$LOG_FILE"
    fi
}

# Функция для проверки и установки зависимостей
check_dependencies() {
    print_header "Проверка зависимостей"
    
    # Массив необходимых пакетов
    local required_packages=(
        "bc"           # Для математических вычислений
        "policycoreutils" # Для работы с SELinux
        "firewalld"    # Брандмауэр
        "openssh-server" # SSH сервер
        "sudo"         # Для проверки настроек sudo
        "yum-utils"    # Утилиты для yum
    )
    
    local missing_packages=()
    
    # Проверка наличия каждого пакета
    for package in "${required_packages[@]}"; do
        if ! rpm -q "$package" &>/dev/null; then
            missing_packages+=("$package")
        fi
    done
    
    # Если есть отсутствующие пакеты, предлагаем установить их
    if [ ${#missing_packages[@]} -gt 0 ]; then
        echo -e "${YELLOW}Отсутствуют следующие пакеты:${NC}" | tee -a "$LOG_FILE"
        printf '%s\n' "${missing_packages[@]}" | tee -a "$LOG_FILE"
        
        echo -e "\n${YELLOW}Установить отсутствующие пакеты? (y/n)${NC}"
        read -r answer
        
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}Установка пакетов...${NC}" | tee -a "$LOG_FILE"
            
            # Определяем менеджер пакетов
            if command -v dnf &>/dev/null; then
                dnf install -y "${missing_packages[@]}" | tee -a "$LOG_FILE"
            else
                yum install -y "${missing_packages[@]}" | tee -a "$LOG_FILE"
            fi
            
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}Все пакеты успешно установлены.${NC}" | tee -a "$LOG_FILE"
            else
                echo -e "${RED}Ошибка при установке пакетов.${NC}" | tee -a "$LOG_FILE"
                return 1
            fi
        else
            echo -e "${YELLOW}Скрипт может работать некорректно без установленных пакетов.${NC}" | tee -a "$LOG_FILE"
            echo -e "${YELLOW}Продолжить выполнение? (y/n)${NC}"
            read -r continue_answer
            if [[ ! "$continue_answer" =~ ^[Yy]$ ]]; then
                return 1
            fi
        fi
    else
        echo -e "${GREEN}Все необходимые пакеты установлены.${NC}" | tee -a "$LOG_FILE"
    fi
    
    return 0
}

# Проверка версии ОС
check_os_version() {
    print_header "Проверка версии ОС"
    
    if [ -f /etc/redhat-release ]; then
        os_version=$(cat /etc/redhat-release)
        echo -e "Версия ОС: $os_version" | tee -a "$LOG_FILE"
        
        rhel_version=$(rpm -q --queryformat '%{VERSION}' redhat-release-server 2>/dev/null || rpm -q --queryformat '%{VERSION}' centos-release 2>/dev/null)
        
        if [[ -n "$rhel_version" ]]; then
            if (( $(echo "$rhel_version < 8" | bc -l) )); then
                echo -e "${YELLOW}ВНИМАНИЕ: Используется устаревшая версия RHEL/CentOS ($rhel_version).${NC}" | tee -a "$LOG_FILE"
                echo -e "${YELLOW}Рекомендуется обновление до более новой версии.${NC}" | tee -a "$LOG_FILE"
            else
                echo -e "${GREEN}Используется актуальная версия RHEL/CentOS.${NC}" | tee -a "$LOG_FILE"
            fi
        fi
    else
        echo -e "${RED}Система не является RHEL/CentOS.${NC}" | tee -a "$LOG_FILE"
    fi
}

# Проверка SELinux
check_selinux() {
    print_header "Проверка статуса SELinux"
    
    if command -v getenforce &> /dev/null; then
        selinux_status=$(getenforce)
        echo -e "Статус SELinux: $selinux_status" | tee -a "$LOG_FILE"
        
        if [ "$selinux_status" == "Disabled" ]; then
            echo -e "${RED}ВНИМАНИЕ: SELinux отключен! Рекомендуется включить SELinux в режиме Enforcing.${NC}" | tee -a "$LOG_FILE"
        elif [ "$selinux_status" == "Permissive" ]; then
            echo -e "${YELLOW}ВНИМАНИЕ: SELinux в режиме Permissive. Рекомендуется включить режим Enforcing.${NC}" | tee -a "$LOG_FILE"
        else
            echo -e "${GREEN}SELinux включен в режиме Enforcing.${NC}" | tee -a "$LOG_FILE"
        fi
        
        echo -e "\nПроверка конфигурации SELinux:" | tee -a "$LOG_FILE"
        if [ -f /etc/selinux/config ]; then
            grep -v "^#" /etc/selinux/config | grep -v "^$" | tee -a "$LOG_FILE"
        fi
    else
        echo -e "${RED}SELinux не установлен или не настроен.${NC}" | tee -a "$LOG_FILE"
    fi
}

# Проверка настроек firewalld
check_firewalld() {
    print_header "Проверка настроек firewalld"
    
    if systemctl is-active --quiet firewalld; then
        echo -e "${GREEN}Служба firewalld активна.${NC}" | tee -a "$LOG_FILE"
        
        echo -e "\nСтатус firewalld:" | tee -a "$LOG_FILE"
        firewall-cmd --state | tee -a "$LOG_FILE"
        
        echo -e "\nАктивная зона:" | tee -a "$LOG_FILE"
        firewall-cmd --get-active-zones | tee -a "$LOG_FILE"
        
        echo -e "\nНастройки зон:" | tee -a "$LOG_FILE"
        firewall-cmd --list-all | tee -a "$LOG_FILE"
        
        # Проверка сервисов в публичной зоне
        if firewall-cmd --get-active-zones | grep -q "public"; then
            echo -e "\nПроверка сервисов в публичной зоне:" | tee -a "$LOG_FILE"
            services=$(firewall-cmd --zone=public --list-services)
            echo "Активные сервисы: $services" | tee -a "$LOG_FILE"
            
            # Проверка потенциально опасных сервисов
            dangerous_services=("telnet" "rsh" "rlogin" "ftp")
            for service in "${dangerous_services[@]}"; do
                if echo "$services" | grep -q -w "$service"; then
                    echo -e "${RED}ВНИМАНИЕ: Обнаружен потенциально небезопасный сервис: $service${NC}" | tee -a "$LOG_FILE"
                fi
            done
        fi
    else
        echo -e "${RED}Служба firewalld не активна!${NC}" | tee -a "$LOG_FILE"
        
        # Проверка iptables
        if systemctl is-active --quiet iptables; then
            echo -e "${YELLOW}Используется iptables вместо firewalld.${NC}" | tee -a "$LOG_FILE"
            echo -e "\nПравила iptables:" | tee -a "$LOG_FILE"
            iptables -L -v | tee -a "$LOG_FILE"
        else
            echo -e "${RED}ВНИМАНИЕ: Ни firewalld, ни iptables не активны! Система не защищена брандмауэром.${NC}" | tee -a "$LOG_FILE"
        fi
    fi
}

# Проверка настроек паролей для RHEL/CentOS
check_password_policies() {
    print_header "Проверка политики паролей"
    
    # Проверка конфигурации PAM
    if [ -f /etc/security/pwquality.conf ]; then
        echo -e "Настройки качества паролей:" | tee -a "$LOG_FILE"
        grep -v "^#" /etc/security/pwquality.conf | grep -v "^$" | tee -a "$LOG_FILE"
        
        # Проверка минимальной длины пароля
        minlen=$(grep "^minlen" /etc/security/pwquality.conf | awk '{print $3}')
        if [[ -n "$minlen" && "$minlen" -lt 8 ]]; then
            echo -e "${YELLOW}ВНИМАНИЕ: Минимальная длина пароля ($minlen) меньше рекомендуемой (8).${NC}" | tee -a "$LOG_FILE"
        fi
    else
        echo -e "${YELLOW}Файл /etc/security/pwquality.conf не найден.${NC}" | tee -a "$LOG_FILE"
    fi
    
    # Проверка срока действия паролей
    if [ -f /etc/login.defs ]; then
        echo -e "\nНастройки срока действия паролей:" | tee -a "$LOG_FILE"
        grep "PASS_MAX_DAYS\|PASS_MIN_DAYS\|PASS_WARN_AGE" /etc/login.defs | tee -a "$LOG_FILE"
        
        # Проверка максимального срока действия пароля
        max_days=$(grep "^PASS_MAX_DAYS" /etc/login.defs | awk '{print $2}')
        if [[ -n "$max_days" && "$max_days" -gt 90 ]]; then
            echo -e "${YELLOW}ВНИМАНИЕ: Максимальный срок действия пароля ($max_days дней) превышает рекомендуемое значение (90 дней).${NC}" | tee -a "$LOG_FILE"
        fi
    else
        echo -e "${YELLOW}Файл /etc/login.defs не найден.${NC}" | tee -a "$LOG_FILE"
    fi
}

# Проверка служб SSH
check_ssh() {
    print_header "Проверка конфигурации SSH"
    
    if [ -f /etc/ssh/sshd_config ]; then
        # Проверка версии протокола
        if grep -q "^Protocol 1" /etc/ssh/sshd_config; then
            echo -e "${RED}ВНИМАНИЕ: Используется небезопасная версия протокола SSH 1.${NC}" | tee -a "$LOG_FILE"
        fi
        
        # Проверка разрешения входа для root
        permitrootlogin=$(grep "^PermitRootLogin" /etc/ssh/sshd_config | awk '{print $2}')
        if [[ "$permitrootlogin" == "yes" ]]; then
            echo -e "${RED}ВНИМАНИЕ: Разрешен вход для пользователя root через SSH.${NC}" | tee -a "$LOG_FILE"
        else
            echo -e "${GREEN}Вход для пользователя root через SSH запрещен.${NC}" | tee -a "$LOG_FILE"
        fi
        
        # Проверка аутентификации по паролю
        passauth=$(grep "^PasswordAuthentication" /etc/ssh/sshd_config | awk '{print $2}')
        if [[ "$passauth" == "yes" ]]; then
            echo -e "${YELLOW}Аутентификация по паролю разрешена. Рекомендуется использовать ключи SSH.${NC}" | tee -a "$LOG_FILE"
        else
            echo -e "${GREEN}Аутентификация по паролю отключена.${NC}" | tee -a "$LOG_FILE"
        fi
        
        # Проверка X11 forwarding
        x11forwarding=$(grep "^X11Forwarding" /etc/ssh/sshd_config | awk '{print $2}')
        if [[ "$x11forwarding" == "yes" ]]; then
            echo -e "${YELLOW}X11 Forwarding включен. Рекомендуется отключить, если не используется.${NC}" | tee -a "$LOG_FILE"
        else
            echo -e "${GREEN}X11 Forwarding отключен.${NC}" | tee -a "$LOG_FILE"
        fi
        
        # Проверка параметров безопасности SSH
        echo -e "\nРекомендуемые параметры безопасности SSH:" | tee -a "$LOG_FILE"
        echo "KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256" | tee -a "$LOG_FILE"
        echo "Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr" | tee -a "$LOG_FILE"
        echo "MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com" | tee -a "$LOG_FILE"
    else
        echo -e "${YELLOW}Файл конфигурации SSH не найден.${NC}" | tee -a "$LOG_FILE"
    fi
}

# Проверка настроек sudo
check_sudo() {
    print_header "Проверка настроек sudo"
    
    if [ -d /etc/sudoers.d ]; then
        echo -e "Содержимое каталога /etc/sudoers.d:" | tee -a "$LOG_FILE"
        ls -la /etc/sudoers.d/ | tee -a "$LOG_FILE"
    fi
    
    # Проверка конфигурации sudo
    if [ -f /etc/sudoers ]; then
        echo -e "\nПроверка важных настроек sudo:" | tee -a "$LOG_FILE"
        
        # Проверка на NOPASSWD
        if grep -r "NOPASSWD" /etc/sudoers /etc/sudoers.d/ 2>/dev/null; then
            echo -e "${YELLOW}ВНИМАНИЕ: Обнаружены настройки NOPASSWD. Это может быть небезопасно.${NC}" | tee -a "$LOG_FILE"
        else
            echo -e "${GREEN}Настройки NOPASSWD не обнаружены.${NC}" | tee -a "$LOG_FILE"
        fi
    else
        echo -e "${YELLOW}Файл /etc/sudoers не найден.${NC}" | tee -a "$LOG_FILE"
    fi
}

# Проверка запущенных служб
check_services() {
    print_header "Проверка запущенных служб"
    
    echo -e "Список запущенных служб:" | tee -a "$LOG_FILE"
    systemctl list-units --type=service --state=running | tee -a "$LOG_FILE"
}

# Проверка SUID/SGID файлов
check_setuid_files() {
    print_header "Проверка SUID/SGID файлов"
    
    echo -e "Поиск SUID файлов..." | tee -a "$LOG_FILE"
    find / -type f -perm -4000 -ls 2>/dev/null | tee -a "$LOG_FILE"
    
    echo -e "\nПоиск SGID файлов..." | tee -a "$LOG_FILE"
    find / -type f -perm -2000 -ls 2>/dev/null | tee -a "$LOG_FILE"
    
    echo -e "\n${YELLOW}ВНИМАНИЕ: Проверьте список SUID/SGID файлов на наличие необычных или подозрительных записей.${NC}" | tee -a "$LOG_FILE"
}

# Проверка пользователей с UID 0
check_uid_zero() {
    print_header "Проверка пользователей с UID 0"
    
    if grep -v "^root:" /etc/passwd | grep ":0:" &>/dev/null; then
        echo -e "${RED}ВНИМАНИЕ: Обнаружены пользователи с UID 0 (кроме root):${NC}" | tee -a "$LOG_FILE"
        grep -v "^root:" /etc/passwd | grep ":0:" | tee -a "$LOG_FILE"
    else
        echo -e "${GREEN}Пользователи с UID 0 (кроме root) не обнаружены.${NC}" | tee -a "$LOG_FILE"
    fi
}

# Проверка неиспользуемых учетных записей
check_unused_accounts() {
    print_header "Проверка неиспользуемых учетных записей"
    
    echo -e "Системные учетные записи с доступом к оболочке:" | tee -a "$LOG_FILE"
    awk -F: '($3 < 1000) && ($7 != "/usr/sbin/nologin" && $7 != "/sbin/nologin" && $7 != "/bin/false") {print $1 ":" $3 ":" $7}' /etc/passwd | tee -a "$LOG_FILE"
    
    echo -e "\nИстория входов пользователей:" | tee -a "$LOG_FILE"
    if command -v lastlog &> /dev/null; then
        lastlog | grep -v "Never logged in" | tee -a "$LOG_FILE"
        
        echo -e "\nПользователи, которые никогда не входили в систему:" | tee -a "$LOG_FILE"
        lastlog | grep "Never logged in" | tee -a "$LOG_FILE"
    else
        echo -e "${YELLOW}Команда lastlog недоступна.${NC}" | tee -a "$LOG_FILE"
    fi
}

# Проверка настроек yum.repos.d
check_repositories() {
    print_header "Проверка репозиториев"
    
    echo -e "Настроенные репозитории:" | tee -a "$LOG_FILE"
    if [ -d /etc/yum.repos.d ]; then
        ls -la /etc/yum.repos.d/ | tee -a "$LOG_FILE"
        
        echo -e "\nАктивные репозитории:" | tee -a "$LOG_FILE"
        yum repolist | tee -a "$LOG_FILE"
    else
        echo -e "${YELLOW}Каталог /etc/yum.repos.d не найден.${NC}" | tee -a "$LOG_FILE"
    fi
}

# Создание отчета с рекомендациями
generate_report() {
    print_header "Создание итогового отчета"
    
    report_file="security_report_$(hostname)_$(date +%Y%m%d_%H%M%S).html"
    
    echo "Создание HTML-отчета в файле $report_file..." | tee -a "$LOG_FILE"
    
    {
        echo "<!DOCTYPE html>"
        echo "<html lang='ru'>"
        echo "<head>"
        echo "  <meta charset='UTF-8'>"
        echo "  <meta name='viewport' content='width=device-width, initial-scale=1.0'>"
        echo "  <title>Отчет по безопасности системы $(hostname)</title>"
        echo "  <style>"
        echo "    body { font-family: Arial, sans-serif; margin: 20px; line-height: 1.6; }"
        echo "    h1, h2, h3 { color: #2c3e50; }"
        echo "    .warning { color: #e74c3c; }"
        echo "    .ok { color: #27ae60; }"
        echo "    .info { color: #3498db; }"
        echo "    .section { border-bottom: 1px solid #eee; padding: 20px 0; }"
        echo "    table { border-collapse: collapse; width: 100%; margin: 20px 0; }"
        echo "    table, th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }"
        echo "    th { background-color: #f5f5f5; }"
        echo "    tr:nth-child(even) { background-color: #f9f9f9; }"
        echo "    .summary { background-color: #f8f9fa; padding: 15px; border-radius: 5px; margin: 20px 0; }"
        echo "    .timestamp { color: #666; font-size: 0.9em; }"
        echo "    .recommendations { background-color: #fff3cd; padding: 15px; border-radius: 5px; margin: 20px 0; }"
        echo "  </style>"
        echo "</head>"
        echo "<body>"
        echo "  <h1>Отчет по безопасности системы $(hostname)</h1>"
        echo "  <p class='timestamp'>Дата проверки: $(date)</p>"
        
        # Общая информация о системе
        echo "  <div class='section'>"
        echo "    <h2>Общая информация о системе</h2>"
        echo "    <table>"
        echo "      <tr><th>Параметр</th><th>Значение</th></tr>"
        echo "      <tr><td>Имя хоста</td><td>$(hostname)</td></tr>"
        echo "      <tr><td>Версия ОС</td><td>$(cat /etc/redhat-release 2>/dev/null || echo 'Не RHEL/CentOS')</td></tr>"
        echo "      <tr><td>Ядро</td><td>$(uname -r)</td></tr>"
        echo "      <tr><td>Архитектура</td><td>$(uname -m)</td></tr>"
        echo "      <tr><td>Процессор</td><td>$(grep 'model name' /proc/cpuinfo | head -n1 | cut -d: -f2 | sed 's/^[ \t]*//')</td></tr>"
        echo "      <tr><td>Память</td><td>$(free -h | grep Mem | awk '{print $2}')</td></tr>"
        echo "      <tr><td>Дисковое пространство</td><td>$(df -h / | tail -n1 | awk '{print $4}') свободно</td></tr>"
        echo "    </table>"
        echo "  </div>"
        
        # Статус безопасности
        echo "  <div class='section'>"
        echo "    <h2>Статус безопасности</h2>"
        echo "    <table>"
        echo "      <tr><th>Компонент</th><th>Статус</th><th>Рекомендации</th></tr>"
        
        # SELinux
        selinux_status=$(getenforce 2>/dev/null || echo "Не установлен")
        if [ "$selinux_status" == "Enforcing" ]; then
            echo "      <tr><td>SELinux</td><td class='ok'>$selinux_status</td><td>Настроен правильно</td></tr>"
        else
            echo "      <tr><td>SELinux</td><td class='warning'>$selinux_status</td><td>Рекомендуется включить в режиме Enforcing</td></tr>"
        fi
        
        # Firewall
        if systemctl is-active --quiet firewalld; then
            echo "      <tr><td>Брандмауэр</td><td class='ok'>Активен (firewalld)</td><td>Настроен правильно</td></tr>"
        elif systemctl is-active --quiet iptables; then
            echo "      <tr><td>Брандмауэр</td><td class='info'>Активен (iptables)</td><td>Рекомендуется перейти на firewalld</td></tr>"
        else
            echo "      <tr><td>Брандмауэр</td><td class='warning'>Неактивен</td><td>Рекомендуется включить firewalld</td></tr>"
        fi
        
        # SSH
        if [ -f /etc/ssh/sshd_config ]; then
            if grep -q "^PermitRootLogin no" /etc/ssh/sshd_config; then
                echo "      <tr><td>SSH Root доступ</td><td class='ok'>Запрещен</td><td>Настроено правильно</td></tr>"
            else
                echo "      <tr><td>SSH Root доступ</td><td class='warning'>Разрешен</td><td>Рекомендуется запретить</td></tr>"
            fi
        fi
        
        # Обновления
        if command -v dnf-automatic &>/dev/null || command -v yum-cron &>/dev/null; then
            echo "      <tr><td>Автообновления</td><td class='ok'>Настроены</td><td>Настроено правильно</td></tr>"
        else
            echo "      <tr><td>Автообновления</td><td class='warning'>Не настроены</td><td>Рекомендуется настроить</td></tr>"
        fi
        
        echo "    </table>"
        echo "  </div>"
        
        # Сеть и порты
        echo "  <div class='section'>"
        echo "    <h2>Сеть и открытые порты</h2>"
        echo "    <h3>Открытые порты:</h3>"
        echo "    <pre>$(netstat -tuln 2>/dev/null | grep -v "127.0.0.1")</pre>"
        echo "    <h3>Активные соединения:</h3>"
        echo "    <pre>$(netstat -tun 2>/dev/null | grep ESTABLISHED)</pre>"
        echo "  </div>"
        
        # Пользователи и группы
        echo "  <div class='section'>"
        echo "    <h2>Пользователи и группы</h2>"
        echo "    <h3>Пользователи с UID 0:</h3>"
        echo "    <pre>$(grep ':0:' /etc/passwd)</pre>"
        echo "    <h3>Пользователи с правами sudo:</h3>"
        echo "    <pre>$(grep -Po '^sudo.+:\K.*$' /etc/group || echo 'Нет пользователей с правами sudo')</pre>"
        echo "    <h3>История входов пользователя root:</h3>"
        echo "    <pre>$(last root | head -n 20)</pre>"
        echo "  </div>"
        
        # Файловая система
        echo "  <div class='section'>"
        echo "    <h2>Файловая система</h2>"
        echo "    <h3>SUID файлы:</h3>"
        echo "    <pre>$(find / -type f -perm -4000 -ls 2>/dev/null | head -n 20)</pre>"
        echo "    <h3>SGID файлы:</h3>"
        echo "    <pre>$(find / -type f -perm -2000 -ls 2>/dev/null | head -n 20)</pre>"
        echo "  </div>"
        
        # Процессы
        echo "  <div class='section'>"
        echo "    <h2>Процессы</h2>"
        echo "    <h3>Запущенные службы:</h3>"
        echo "    <pre>$(systemctl list-units --type=service --state=running | head -n 20)</pre>"
        echo "  </div>"
        
        # Рекомендации
        echo "  <div class='section recommendations'>"
        echo "    <h2>Рекомендации по безопасности</h2>"
        echo "    <ul>"
        echo "      <li>Регулярно обновляйте систему</li>"
        echo "      <li>Используйте сложные пароли</li>"
        echo "      <li>Отключите неиспользуемые службы</li>"
        echo "      <li>Настройте брандмауэр</li>"
        echo "      <li>Включите SELinux в режиме Enforcing</li>"
        echo "      <li>Настройте аудит системы</li>"
        echo "      <li>Регулярно проверяйте журналы</li>"
        echo "      <li>Настройте резервное копирование</li>"
        echo "      <li>Используйте SSH ключи вместо паролей</li>"
        echo "      <li>Настройте мониторинг системы</li>"
        echo "    </ul>"
        echo "  </div>"
        
        # Статистика проверки
        echo "  <div class='section summary'>"
        echo "    <h2>Статистика проверки</h2>"
        echo "    <p>Всего проверок: $(($ERROR_COUNT + $WARNING_COUNT))</p>"
        echo "    <p>Ошибок: <span class='warning'>$ERROR_COUNT</span></p>"
        echo "    <p>Предупреждений: <span class='info'>$WARNING_COUNT</span></p>"
        echo "  </div>"
        
        echo "</body>"
        echo "</html>"
    } > "$report_file"
    
    echo -e "${GREEN}Отчет создан: $report_file${NC}" | tee -a "$LOG_FILE"
}

# Основная функция
main() {
    # Проверка прав root
    check_root
    
    print_header "Начало проверки безопасности"
    
    # Создание временной директории
    mkdir -p "$TEMP_DIR"
    
    # Проверка зависимостей перед началом работы
    check_dependencies || handle_error "Ошибка при проверке зависимостей"
    
    # Выполнение проверок
    check_os_version || handle_warning "Ошибка при проверке версии ОС"
    check_selinux || handle_warning "Ошибка при проверке SELinux"
    check_firewalld || handle_warning "Ошибка при проверке firewalld"
    check_password_policies || handle_warning "Ошибка при проверке политики паролей"
    check_ssh || handle_warning "Ошибка при проверке SSH"
    check_sudo || handle_warning "Ошибка при проверке sudo"
    check_services || handle_warning "Ошибка при проверке служб"
    check_setuid_files || handle_warning "Ошибка при проверке SUID/SGID файлов"
    check_uid_zero || handle_warning "Ошибка при проверке UID 0"
    check_unused_accounts || handle_warning "Ошибка при проверке неиспользуемых учетных записей"
    check_repositories || handle_warning "Ошибка при проверке репозиториев"
    
    # Экспорт результатов
    export_results || handle_error "Ошибка при экспорте результатов"
    
    print_header "Проверка безопасности завершена"
    echo -e "${BLUE}Статистика:${NC}"
    echo -e "Ошибок: ${RED}$ERROR_COUNT${NC}"
    echo -e "Предупреждений: ${YELLOW}$WARNING_COUNT${NC}"
}

# Запуск скрипта
main