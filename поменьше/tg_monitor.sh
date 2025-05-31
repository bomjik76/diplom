#!/bin/bash
TELEGRAM_BOT_TOKEN="7756794651:AAHL4_Ow1I2fFMueeq5xCuMHRHvR4gh2SIY"
TELEGRAM_CHAT_ID="-4780810287"
CPU_THRESHOLD=80
MEMORY_THRESHOLD=85
DISK_THRESHOLD=90
dnf install curl bc -y
send_telegram() {
    local message="$1"
    response=$(curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        -d "chat_id=$TELEGRAM_CHAT_ID" \
        -d "text=$message" \
        -d "parse_mode=HTML")
    
    # Проверка успешности отправки
    if [[ $response == *"\"ok\":true"* ]]; then
        echo "Сообщение успешно отправлено"
    else
        echo "Ошибка отправки сообщения: $response"
    fi
}
get_system_info() {
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{printf "%.0f", $2}')
    memory_total=$(free -m | grep Mem | awk '{print $2}')
    memory_used=$(free -m | grep Mem | awk '{print $3}')
    memory_percent=$((memory_used * 100 / memory_total))
    disk_usage=$(df -h / | tail -1 | awk '{print $5}' | sed 's/%//' | awk '{printf "%.0f", $1}')
    echo "$cpu_usage $memory_percent $disk_usage"
}
echo "Отправка тестового сообщения..."
test_message="<b>🔄 Тестовое сообщение</b>
Скрипт мониторинга сервера успешно запущен.
Все каналы связи работают корректно."
send_telegram "$test_message"
echo "Тестовое сообщение отправлено."
echo "Отправка текущего состояния системы..."
read cpu memory disk <<< $(get_system_info)
message="<b>📊 Отчет о состоянии сервера</b>
"
message+="<b>🖥 CPU:</b> ${cpu}% "
if (( $(echo "$cpu > $CPU_THRESHOLD" | bc -l) )); then
    message+="⚠️"
else
    message+="✅"
fi
message+="
"
message+="<b>💾 Память:</b> ${memory}% "
if (( $(echo "$memory > $MEMORY_THRESHOLD" | bc -l) )); then
    message+="⚠️"
else
    message+="✅"
fi
message+="
"
message+="<b>💿 Диск:</b> ${disk}% "
if (( $(echo "$disk > $DISK_THRESHOLD" | bc -l) )); then
    message+="⚠️"
else
    message+="✅"
fi
message+="
"
message+="<b>⏰ Время:</b> $(date '+%d.%m.%Y %H:%M:%S')"
send_telegram "$message"
echo "Текущее состояние системы отправлено."
while true; do
    read cpu memory disk <<< $(get_system_info)
    message="<b>📊 Отчет о состоянии сервера</b>
"
    message+="<b>🖥 CPU:</b> ${cpu}% "
    if (( $(echo "$cpu > $CPU_THRESHOLD" | bc -l) )); then
        message+="⚠️"
    else
        message+="✅"
    fi
    message+="
"
    message+="<b>💾 Память:</b> ${memory}% "
    if (( $(echo "$memory > $MEMORY_THRESHOLD" | bc -l) )); then
        message+="⚠️"
    else
        message+="✅"
    fi
    message+="
"
    message+="<b>💿 Диск:</b> ${disk}% "
    if (( $(echo "$disk > $DISK_THRESHOLD" | bc -l) )); then
        message+="⚠️"
    else
        message+="✅"
    fi
    message+="
"
    message+="<b>⏰ Время:</b> $(date '+%d.%m.%Y %H:%M:%S')"
    if (( $(echo "$cpu > $CPU_THRESHOLD" | bc -l) )) || (( $(echo "$memory > $MEMORY_THRESHOLD" | bc -l) )) || (( $(echo "$disk > $DISK_THRESHOLD" | bc -l) )); then
        message+="
⚠️ <b>ВНИМАНИЕ!</b> Превышены критические значения:
"
        (( $(echo "$cpu > $CPU_THRESHOLD" | bc -l) )) && message+="- CPU превышает ${CPU_THRESHOLD}% (Текущее: ${cpu}%)
"
        (( $(echo "$memory > $MEMORY_THRESHOLD" | bc -l) )) && message+="- Память превышает ${MEMORY_THRESHOLD}% (Текущее: ${memory}%)
"
        (( $(echo "$disk > $DISK_THRESHOLD" | bc -l) )) && message+="- Диск превышает ${DISK_THRESHOLD}% (Текущее: ${disk}%)
"
        send_telegram "$message"
    fi
    if [ "$(date +%M)" = "00" ]; then
        send_telegram "$message"
    fi
    
    sleep 60
done 