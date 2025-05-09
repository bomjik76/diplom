#!/bin/bash
#
# Универсальный скрипт резервного копирования для Red Hat Linux
# Выполняет резервное копирование и позволяет настраивать автоматический запуск

# Автоматическая установка прав на исполнение
if [ ! -x "$0" ]; then
    chmod +x "$0"
    echo "Установлены права на исполнение для скрипта"
fi

# Конфигурационные переменные
BACKUP_DIR="/var/backups"
SOURCE_DIRS=("/etc" "/home" "/var/www")
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
BACKUP_FILENAME="backup-${TIMESTAMP}.tar.gz"
LOG_FILE="/var/log/backup.log"
RETENTION_DAYS=30

# Цвета для красивого вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функция для отображения заголовка
show_header() {
    clear
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                                                               ║${NC}"
    echo -e "${BLUE}║${GREEN}             СИСТЕМА РЕЗЕРВНОГО КОПИРОВАНИЯ                    ${BLUE}║${NC}"
    echo -e "${BLUE}║${GREEN}                  ДЛЯ RED HAT LINUX                            ${BLUE}║${NC}"
    echo -e "${BLUE}║                                                               ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Функция для отображения главного меню
show_main_menu() {
    show_header
    echo -e "Выберите действие:\n"
    echo -e "${GREEN}1${NC}. Выполнить резервное копирование"
    echo -e "${GREEN}2${NC}. Управление планировщиком заданий (crontab)"
    echo -e "${GREEN}3${NC}. Просмотреть текущее расписание crontab"
    echo -e "${GREEN}4${NC}. Изменить настройки копирования"
    echo -e "${GREEN}5${NC}. Просмотреть лог резервного копирования"
    echo -e "${GREEN}6${NC}. Справка"
    echo -e "${GREEN}0${NC}. Выход"
    echo ""
    read -p "Введите номер опции: " main_choice
    
    case $main_choice in
        1) perform_backup; show_end_screen ;;
        2) crontab_management_menu ;;
        3) show_crontab ;;
        4) configure_settings_menu ;;
        5) show_log ;;
        6) show_help ;;
        0) exit 0 ;;
        *) 
            echo -e "${RED}Некорректный выбор!${NC}"
            sleep 2
            show_main_menu
            ;;
    esac
}

# Функция управления заданиями crontab
crontab_management_menu() {
    show_header
    echo -e "${BLUE}УПРАВЛЕНИЕ ПЛАНИРОВЩИКОМ ЗАДАНИЙ (CRONTAB)${NC}\n"
    
    echo -e "Выберите действие:\n"
    echo -e "${GREEN}1${NC}. Настроить новое расписание резервного копирования"
    echo -e "${GREEN}2${NC}. Отключить задание резервного копирования"
    echo -e "${GREEN}3${NC}. Редактировать существующее задание"
    echo -e "${GREEN}4${NC}. Удалить все задания crontab"
    echo -e "${GREEN}5${NC}. Проверить статус cron сервиса"
    echo -e "${GREEN}0${NC}. Вернуться в главное меню"
    echo ""
    read -p "Введите номер опции: " crontab_choice
    
    case $crontab_choice in
        1) configure_schedule_menu ;;
        2) disable_backup_task ;;
        3) edit_crontab ;;
        4) clear_all_crontab ;;
        5) check_cron_status ;;
        0) show_main_menu ;;
        *) 
            echo -e "${RED}Некорректный выбор!${NC}"
            sleep 2
            crontab_management_menu
            ;;
    esac
}

# Функция для проверки статуса cron сервиса
check_cron_status() {
    show_header
    echo -e "${BLUE}ПРОВЕРКА СТАТУСА CRON СЕРВИСА${NC}\n"
    
    echo "Проверка статуса cron сервиса..."
    
    # Проверяем статус службы cron
    if systemctl status crond &>/dev/null || systemctl status cron &>/dev/null; then
        echo -e "${GREEN}Сервис cron активен и работает.${NC}"
        
        if systemctl is-enabled crond &>/dev/null || systemctl is-enabled cron &>/dev/null; then
            echo -e "${GREEN}Сервис cron настроен на автоматический запуск при загрузке системы.${NC}"
        else
            echo -e "${YELLOW}Сервис cron работает, но не настроен на автоматический запуск при загрузке системы.${NC}"
        fi
    else
        echo -e "${RED}Сервис cron не запущен или не установлен!${NC}"
        echo -e "Рекомендуется установить и запустить сервис cron с помощью команд:"
        echo "sudo yum install cronie (для RHEL/CentOS)"
        echo "sudo systemctl enable crond"
        echo "sudo systemctl start crond"
    fi
    
    echo ""
    read -p "Нажмите Enter для возврата в меню управления crontab..." 
    crontab_management_menu
}

# Функция для удаления всех заданий crontab
clear_all_crontab() {
    show_header
    echo -e "${BLUE}УДАЛЕНИЕ ВСЕХ ЗАДАНИЙ CRONTAB${NC}\n"
    
    echo -e "${YELLOW}ВНИМАНИЕ: Это действие удалит ВСЕ задания crontab для текущего пользователя!${NC}"
    echo -e "${YELLOW}Будут удалены не только задания резервного копирования, но и все остальные задания.${NC}"
    echo ""
    read -p "Вы уверены, что хотите продолжить? (y/n): " confirm
    
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        crontab -r
        echo -e "${GREEN}Все задания crontab успешно удалены.${NC}"
    else
        echo -e "Операция отменена."
    fi
    
    echo ""
    read -p "Нажмите Enter для возврата в меню управления crontab..." 
    crontab_management_menu
}

# Функция для редактирования существующего расписания
edit_crontab() {
    show_header
    echo -e "${BLUE}РЕДАКТИРОВАНИЕ ФАЙЛА CRONTAB${NC}\n"
    
    echo "Текущие задания crontab:"
    echo ""
    crontab -l
    echo ""
    
    echo -e "${YELLOW}Сейчас будет открыт редактор для редактирования файла crontab.${NC}"
    echo -e "${YELLOW}После внесения изменений сохраните файл и закройте редактор.${NC}"
    echo ""
    read -p "Нажмите Enter для продолжения..." 
    
    # Открываем crontab в редакторе
    crontab -e
    
    echo -e "${GREEN}Файл crontab успешно обновлен.${NC}"
    echo ""
    read -p "Нажмите Enter для возврата в меню управления crontab..." 
    crontab_management_menu
}

# Функция для отключения задания резервного копирования
disable_backup_task() {
    show_header
    echo -e "${BLUE}ОТКЛЮЧЕНИЕ ЗАДАНИЯ РЕЗЕРВНОГО КОПИРОВАНИЯ${NC}\n"
    
    script_path=$(readlink -f "$0")
    
    # Получаем текущий crontab
    crontab -l 2>/dev/null > /tmp/current_crontab
    
    # Проверяем, есть ли задание для этого скрипта
    if grep -q "$script_path" /tmp/current_crontab; then
        # Удаляем строки, содержащие путь к скрипту
        grep -v "$script_path" /tmp/current_crontab > /tmp/new_crontab
        
        # Устанавливаем новый crontab
        crontab /tmp/new_crontab
        
        echo -e "${GREEN}Задания резервного копирования успешно отключены.${NC}"
    else
        echo -e "${YELLOW}Задания резервного копирования не найдены в crontab.${NC}"
    fi
    
    # Удаляем временные файлы
    rm -f /tmp/current_crontab /tmp/new_crontab
    
    echo ""
    read -p "Нажмите Enter для возврата в меню управления crontab..." 
    crontab_management_menu
}

# Функция для отображения экрана завершения операции
show_end_screen() {
    echo ""
    echo -e "${GREEN}Операция успешно выполнена!${NC}"
    echo ""
    read -p "Нажмите Enter для возврата в главное меню..." 
    show_main_menu
}

# Функция для просмотра записей лога
show_log() {
    show_header
    echo -e "${BLUE}ПРОСМОТР ЛОГА РЕЗЕРВНОГО КОПИРОВАНИЯ${NC}\n"
    
    if [ -f "$LOG_FILE" ]; then
        echo "Последние 20 записей журнала $LOG_FILE:"
        echo ""
        tail -n 20 "$LOG_FILE"
        echo ""
    else
        echo -e "${YELLOW}Файл журнала $LOG_FILE не найден!${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}1${NC}. Просмотреть весь лог"
    echo -e "${GREEN}2${NC}. Очистить лог"
    echo -e "${GREEN}0${NC}. Вернуться в главное меню"
    echo ""
    read -p "Введите номер опции: " log_choice
    
    case $log_choice in
        1) 
            if [ -f "$LOG_FILE" ]; then
                less "$LOG_FILE"
            else
                echo -e "${YELLOW}Файл журнала $LOG_FILE не найден!${NC}"
                sleep 2
            fi
            show_log
            ;;
        2) 
            if [ -f "$LOG_FILE" ]; then
                echo "" > "$LOG_FILE"
                echo -e "${GREEN}Лог успешно очищен!${NC}"
                sleep 2
            else
                echo -e "${YELLOW}Файл журнала $LOG_FILE не найден!${NC}"
                sleep 2
            fi
            show_log
            ;;
        0) show_main_menu ;;
        *) 
            echo -e "${RED}Некорректный выбор!${NC}"
            sleep 2
            show_log
            ;;
    esac
}

# Функция для просмотра текущего расписания crontab
show_crontab() {
    show_header
    echo -e "${BLUE}ТЕКУЩЕЕ РАСПИСАНИЕ CRONTAB${NC}\n"
    
    echo "Текущие задания crontab для пользователя $(whoami):"
    echo ""
    
    if ! crontab -l 2>/dev/null; then
        echo -e "${YELLOW}Нет настроенных заданий crontab или возникла ошибка при выполнении crontab -l${NC}"
    fi
    
    echo ""
    read -p "Нажмите Enter для возврата в главное меню..." 
    show_main_menu
}

# Функция для настройки параметров копирования
configure_settings_menu() {
    show_header
    echo -e "${BLUE}НАСТРОЙКА ПАРАМЕТРОВ РЕЗЕРВНОГО КОПИРОВАНИЯ${NC}\n"
    
    echo -e "Текущие настройки:\n"
    echo -e "1. Директория для резервных копий: ${GREEN}$BACKUP_DIR${NC}"
    echo -e "2. Директории для копирования: ${GREEN}${SOURCE_DIRS[@]}${NC}"
    echo -e "3. Срок хранения резервных копий: ${GREEN}$RETENTION_DAYS дней${NC}"
    echo -e "4. Файл журнала: ${GREEN}$LOG_FILE${NC}"
    echo -e "0. Вернуться в главное меню\n"
    
    read -p "Выберите параметр для изменения (0-4): " settings_choice
    
    case $settings_choice in
        1) 
            read -p "Введите новый путь для сохранения резервных копий: " new_backup_dir
            if [ ! -z "$new_backup_dir" ]; then
                BACKUP_DIR="$new_backup_dir"
                echo -e "${GREEN}Путь для резервных копий успешно изменен!${NC}"
                sleep 2
            fi
            configure_settings_menu
            ;;
        2) 
            echo "Введите директории для копирования, разделенные пробелом (например: /etc /home /var/www)"
            read -p "> " new_dirs
            if [ ! -z "$new_dirs" ]; then
                SOURCE_DIRS=($new_dirs)
                echo -e "${GREEN}Список директорий для копирования успешно изменен!${NC}"
                sleep 2
            fi
            configure_settings_menu
            ;;
        3) 
            read -p "Введите новый срок хранения резервных копий (в днях): " new_retention
            if [[ "$new_retention" =~ ^[0-9]+$ ]]; then
                RETENTION_DAYS=$new_retention
                echo -e "${GREEN}Срок хранения резервных копий успешно изменен!${NC}"
                sleep 2
            else
                echo -e "${RED}Ошибка: введите целое число!${NC}"
                sleep 2
            fi
            configure_settings_menu
            ;;
        4) 
            read -p "Введите новый путь для журнала: " new_log_file
            if [ ! -z "$new_log_file" ]; then
                LOG_FILE="$new_log_file"
                echo -e "${GREEN}Путь для журнала успешно изменен!${NC}"
                sleep 2
            fi
            configure_settings_menu
            ;;
        0) show_main_menu ;;
        *) 
            echo -e "${RED}Некорректный выбор!${NC}"
            sleep 2
            configure_settings_menu
            ;;
    esac
}

# Функция для отображения справки
show_help() {
    show_header
    echo -e "${BLUE}СПРАВКА ПО ИСПОЛЬЗОВАНИЮ${NC}\n"
    
    echo "Этот скрипт предназначен для резервного копирования системных и пользовательских директорий."
    echo ""
    echo "Основные возможности:"
    echo "  - Создание сжатых архивов выбранных директорий"
    echo "  - Проверка наличия достаточного места на диске"
    echo "  - Автоматическое удаление устаревших резервных копий"
    echo "  - Настройка автоматического запуска по расписанию"
    echo ""
    echo "Расписание в формате crontab:"
    echo ""
    echo "* * * * * - команда для выполнения"
    echo "| | | | |"
    echo "| | | | +-- День недели (0-6, где 0=воскресенье)"
    echo "| | | +---- Месяц (1-12)"
    echo "| | +------ День месяца (1-31)"
    echo "| +-------- Час (0-23)"
    echo "+---------- Минута (0-59)"
    echo ""
    echo "Примеры расписаний:"
    echo "  0 3 * * *     - каждый день в 3:00 утра"
    echo "  0 */4 * * *   - каждые 4 часа"
    echo "  0 3 * * 1-5   - в 3:00 утра с понедельника по пятницу"
    echo ""
    
    read -p "Нажмите Enter для возврата в главное меню..." 
    show_main_menu
}

# Функция для настройки расписания
configure_schedule_menu() {
    show_header
    echo -e "${BLUE}НАСТРОЙКА РАСПИСАНИЯ РЕЗЕРВНОГО КОПИРОВАНИЯ${NC}\n"
    
    echo -e "Выберите расписание для автоматического запуска резервного копирования:\n"
    echo -e "${GREEN}1${NC}. Ежедневно в 3:00 ночи"
    echo -e "${GREEN}2${NC}. Еженедельно (каждое воскресенье в 2:00 ночи)"
    echo -e "${GREEN}3${NC}. Ежемесячно (1-го числа каждого месяца в 4:00 утра)"
    echo -e "${GREEN}4${NC}. Дважды в день (в 12:00 и 00:00)"
    echo -e "${GREEN}5${NC}. Указать собственное расписание в формате crontab"
    echo -e "${GREEN}0${NC}. Вернуться в меню управления crontab"
    echo ""
    read -p "Выберите опцию (0-5): " choice
    
    case $choice in
        1)
            schedule="0 3 * * *"
            description="Ежедневно в 3:00 ночи"
            ;;
        2)
            schedule="0 2 * * 0"
            description="Еженедельно (каждое воскресенье в 2:00 ночи)"
            ;;
        3)
            schedule="0 4 1 * *"
            description="Ежемесячно (1-го числа каждого месяца в 4:00 утра)"
            ;;
        4)
            schedule="0 0,12 * * *"
            description="Дважды в день (в 12:00 и 00:00)"
            ;;
        5)
            echo ""
            echo "Введите расписание в формате crontab."
            echo "Например: '*/15 * * * *' для запуска каждые 15 минут."
            echo "Формат: минуты(0-59) часы(0-23) день_месяца(1-31) месяц(1-12) день_недели(0-6,0=воскресенье)"
            echo ""
            read -p "Расписание: " schedule
            description="Пользовательское расписание: $schedule"
            ;;
        0) crontab_management_menu; return ;;
        *)
            echo -e "${RED}Неправильный выбор!${NC}"
            sleep 2
            configure_schedule_menu
            return
            ;;
    esac
    
    echo ""
    echo -e "Выбрано расписание: ${GREEN}$description${NC}"
    echo -e "Формат crontab: ${GREEN}$schedule${NC}"
    echo ""
    read -p "Продолжить настройку? (y/n): " confirm
    
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "Настройка отменена."
        sleep 2
        configure_schedule_menu
        return
    fi
    
    # Настраиваем crontab
    setup_cron "$schedule"
    
    echo ""
    echo -e "${GREEN}Настройка завершена. Скрипт будет запускаться автоматически по выбранному расписанию.${NC}"
    echo "Вы можете просмотреть текущие задания crontab, выбрав соответствующий пункт в главном меню."
    echo ""
    read -p "Нажмите Enter для возврата в меню управления crontab..." 
    crontab_management_menu
}

# Функция для настройки автоматического запуска по расписанию
setup_cron() {
    local schedule=$1
    local script_path=$(readlink -f "$0")
    
    echo "Настройка запуска по расписанию: $schedule"
    
    # Проверяем и устанавливаем права на исполнение для скрипта
    if [ ! -x "$script_path" ]; then
        chmod +x "$script_path"
        echo -e "Установлены права на исполнение для скрипта: ${GREEN}$script_path${NC}"
    fi
    
    # Проверяем, существует ли уже задание cron для этого скрипта
    crontab -l 2>/dev/null | grep -v "$script_path" > /tmp/current_crontab
    
    # Добавляем новое задание
    echo "$schedule $script_path --backup" >> /tmp/current_crontab
    
    # Устанавливаем новый crontab
    crontab /tmp/current_crontab
    rm /tmp/current_crontab
    
    echo -e "${GREEN}Скрипт успешно добавлен в планировщик заданий crontab${NC}"
    echo "Расписание: $schedule"
    echo "Путь к скрипту: $script_path"
}

# Функция для выполнения резервного копирования
perform_backup() {
    show_header
    echo -e "${BLUE}ВЫПОЛНЕНИЕ РЕЗЕРВНОГО КОПИРОВАНИЯ${NC}\n"
    
    # Создаем директорию для резервных копий, если она не существует
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
        echo -e "Создана директория для резервных копий: ${GREEN}$BACKUP_DIR${NC}" | tee -a "$LOG_FILE"
    fi
    
    # Записываем начало резервного копирования
    echo -e "Начало резервного копирования: ${GREEN}$(date)${NC}" | tee -a "$LOG_FILE"
    
    # Проверка размера директорий для резервного копирования
    echo -e "Расчет размера директорий для копирования..."
    ESTIMATED_SIZE=$(du -sm "${SOURCE_DIRS[@]}" 2>/dev/null | awk '{sum += $1} END {print sum}')
    echo -e "Приблизительный размер резервной копии: ${GREEN}${ESTIMATED_SIZE} MB${NC}" | tee -a "$LOG_FILE"
    
    # Проверка доступного места на диске
    AVAILABLE_SPACE=$(df -m "$BACKUP_DIR" | awk 'NR==2 {print $4}')
    echo -e "Доступное место на диске: ${GREEN}${AVAILABLE_SPACE} MB${NC}" | tee -a "$LOG_FILE"
    
    # Проверяем достаточно ли места для резервной копии
    if [ $AVAILABLE_SPACE -lt $((ESTIMATED_SIZE * 2)) ]; then
        echo -e "${RED}ОШИБКА: Недостаточно места на диске для создания резервной копии!${NC}" | tee -a "$LOG_FILE"
        echo -e "Требуется минимум: ${RED}$((ESTIMATED_SIZE * 2)) MB${NC}, доступно: ${RED}${AVAILABLE_SPACE} MB${NC}" | tee -a "$LOG_FILE"
        echo ""
        read -p "Нажмите Enter для возврата в главное меню..." 
        show_main_menu
        return
    fi
    
    # Создаем резервную копию
    echo -e "Создание резервной копии ${GREEN}$BACKUP_FILENAME${NC}..." | tee -a "$LOG_FILE"
    tar -czf "$BACKUP_DIR/$BACKUP_FILENAME" "${SOURCE_DIRS[@]}" 2>&1 | tee -a "$LOG_FILE"
    
    # Проверяем успешность создания резервной копии
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Резервное копирование успешно завершено: $BACKUP_DIR/$BACKUP_FILENAME${NC}" | tee -a "$LOG_FILE"
        local backup_size=$(du -h "$BACKUP_DIR/$BACKUP_FILENAME" | cut -f1)
        echo -e "Размер резервной копии: ${GREEN}$backup_size${NC}" | tee -a "$LOG_FILE"
    else
        echo -e "${RED}Ошибка резервного копирования!${NC}" | tee -a "$LOG_FILE"
        echo ""
        read -p "Нажмите Enter для возврата в главное меню..." 
        show_main_menu
        return
    fi
    
    # Удаляем старые резервные копии
    echo -e "Удаление резервных копий старше ${GREEN}$RETENTION_DAYS${NC} дней..." | tee -a "$LOG_FILE"
    find "$BACKUP_DIR" -name "backup-*.tar.gz" -type f -mtime +$RETENTION_DAYS -delete -print | tee -a "$LOG_FILE"
    
    echo -e "${GREEN}Процесс резервного копирования завершен: $(date)${NC}" | tee -a "$LOG_FILE"
    echo "-----------------------------------" | tee -a "$LOG_FILE"
    echo ""
}

# Обработка аргументов командной строки (для поддержки автоматического запуска из crontab)
if [ "$1" = "--backup" ]; then
    perform_backup > /dev/null 2>&1
    exit 0
fi

# Запуск главного меню
show_main_menu 