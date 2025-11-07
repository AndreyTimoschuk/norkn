#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BLACKLIST_URL="https://raw.githubusercontent.com/C24Be/AS_Network_List/main/blacklists/blacklist.txt"
SCRIPT_PATH="/usr/local/bin/firewall-blacklist.sh"
LOG_FILE="/var/log/firewall_blacklist.log"
TEMP_FILE="/tmp/blacklist_subnets.txt"

# Check if running as root
if [[ $EUID -ne 0 ]] || [[ $(id -u) -ne 0 ]]; then
   echo ""
   echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
   echo -e "${RED}║  ОШИБКА: Скрипт должен быть запущен от имени root!       ║${NC}"
   echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
   echo ""
   echo -e "${YELLOW}Используйте:${NC}"
   echo -e "  ${GREEN}sudo bash install.sh${NC}"
   echo ""
   exit 1
fi

# Additional verification - try to write to system directory
if ! touch /usr/local/bin/.test_write 2>/dev/null; then
   echo ""
   echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
   echo -e "${RED}║  ОШИБКА: Нет прав на запись в системные каталоги!        ║${NC}"
   echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
   echo ""
   echo -e "${YELLOW}Скрипт ДОЛЖЕН быть запущен с sudo:${NC}"
   echo -e "  ${GREEN}sudo bash install.sh${NC}"
   echo ""
   exit 1
fi
rm -f /usr/local/bin/.test_write 2>/dev/null

clear
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}              ${GREEN}NO, THANKS RKN${NC}                           ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}  ${YELLOW}Спасибо РКН, но не надо меня сканировать${NC}         ${BLUE}║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Этот скрипт установит автоматическое управление блеклистом${NC}"
echo -e "${YELLOW}для вашего фаервола с запланированными обновлениями.${NC}"
echo ""

# Function to show progress
show_progress() {
    local current=$1
    local total=$2
    local percent=$((current * 100 / total))
    printf "\r${YELLOW}Прогресс: %d%%${NC}" "$percent"
}

# Step 1: Choose firewall
echo -e "${GREEN}[1/4] Выбор типа фаервола${NC}"
echo ""
echo "  1) UFW (Uncomplicated Firewall)"
echo "  2) iptables (прямое управление iptables)"
echo ""
read -p "Выберите фаервол [1-2]: " fw_choice

case $fw_choice in
    1)
        FIREWALL_TYPE="ufw"
        echo -e "${GREEN}✓ Выбрано: UFW${NC}"
        ;;
    2)
        FIREWALL_TYPE="iptables"
        echo -e "${GREEN}✓ Выбрано: iptables${NC}"
        ;;
    *)
        echo -e "${RED}Неверный выбор. Выход.${NC}"
        exit 1
        ;;
esac
echo ""

# Step 2: Install firewall if needed
echo -e "${GREEN}[2/4] Установка фаервола${NC}"

install_firewall() {
    if [[ "$FIREWALL_TYPE" == "ufw" ]]; then
        if ! command -v ufw &> /dev/null; then
            echo "Установка UFW..."
            if [[ -f /etc/debian_version ]]; then
                apt-get update && apt-get install -y ufw
            elif [[ -f /etc/redhat-release ]]; then
                yum install -y ufw
            else
                echo -e "${RED}Неподдерживаемая ОС. Установите UFW вручную.${NC}"
                exit 1
            fi
        else
            echo "UFW уже установлен"
        fi
        
        # Enable UFW if not active
        if ! ufw status | grep -q "Status: active"; then
            echo "Включение UFW..."
            ufw --force enable
        fi
        echo -e "${GREEN}✓ UFW готов к работе${NC}"
        
    elif [[ "$FIREWALL_TYPE" == "iptables" ]]; then
        if ! command -v iptables &> /dev/null; then
            echo "Установка iptables..."
            if [[ -f /etc/debian_version ]]; then
                apt-get update && apt-get install -y iptables iptables-persistent
            elif [[ -f /etc/redhat-release ]]; then
                yum install -y iptables iptables-services
                systemctl enable iptables
                systemctl start iptables
            else
                echo -e "${RED}Неподдерживаемая ОС. Установите iptables вручную.${NC}"
                exit 1
            fi
        else
            echo "iptables уже установлен"
        fi
        echo -e "${GREEN}✓ iptables готов к работе${NC}"
    fi
}

install_firewall
echo ""

# Step 3: Choose schedule
echo -e "${GREEN}[3/4] Настройка расписания обновлений${NC}"
echo ""
echo "  1) Ежедневно в 03:00"
echo "  2) Ежедневно в 04:00"
echo "  3) Ежедневно в 05:00"
echo "  4) Еженедельно (понедельник в 03:00)"
echo "  5) Свое время"
echo "  6) Только вручную (без автообновлений)"
echo ""
read -p "Выберите расписание [1-6]: " schedule_choice

case $schedule_choice in
    1)
        CRON_TIME="0 3 * * *"
        SCHEDULE_DESC="Ежедневно в 03:00"
        ;;
    2)
        CRON_TIME="0 4 * * *"
        SCHEDULE_DESC="Ежедневно в 04:00"
        ;;
    3)
        CRON_TIME="0 5 * * *"
        SCHEDULE_DESC="Ежедневно в 05:00"
        ;;
    4)
        CRON_TIME="0 3 * * 1"
        SCHEDULE_DESC="Еженедельно в понедельник в 03:00"
        ;;
    5)
        read -p "Введите час (0-23): " hour
        read -p "Введите минуты (0-59): " minute
        CRON_TIME="$minute $hour * * *"
        SCHEDULE_DESC="Ежедневно в $hour:$minute"
        ;;
    6)
        CRON_TIME=""
        SCHEDULE_DESC="Только вручную"
        ;;
    *)
        echo -e "${RED}Неверный выбор. Используется по умолчанию: Ежедневно в 03:00${NC}"
        CRON_TIME="0 3 * * *"
        SCHEDULE_DESC="Ежедневно в 03:00"
        ;;
esac

if [[ -n "$CRON_TIME" ]]; then
    echo -e "${GREEN}✓ Расписание установлено: $SCHEDULE_DESC${NC}"
else
    echo -e "${GREEN}✓ Ручной режим (без автообновлений)${NC}"
fi
echo ""

# Step 4: Create the main script
echo -e "${GREEN}[4/4] Установка скрипта блеклиста${NC}"

cat > "$SCRIPT_PATH" << 'SCRIPT_EOF'
#!/bin/bash

# Configuration
BLACKLIST_URL="__BLACKLIST_URL__"
TEMP_FILE="__TEMP_FILE__"
LOG_FILE="__LOG_FILE__"
FIREWALL_TYPE="__FIREWALL_TYPE__"

# Progress function
show_progress() {
    local current=$1
    local total=$2
    local percent=$((current * 100 / total))
    printf "\rПрогресс: %d%%" "$percent"
}

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Check root
[[ $EUID -ne 0 ]] && { log "ОШИБКА: Необходимо запускать от root"; exit 1; }

log "Запуск обновления блеклиста фаервола..."

# Cleanup old rules
cleanup_old_rules() {
    log "Очистка старых правил блеклиста..."
    
    if [[ "$FIREWALL_TYPE" == "ufw" ]]; then
        local current_rules_file="/tmp/current_blacklist_rules.txt"
        ufw status numbered | grep "Blacklist" | awk -F'[][]' '{print $2}' | sort -nr > "$current_rules_file"
        
        if [[ -s "$current_rules_file" ]]; then
            while read -r rule_num; do
                if [[ -n "$rule_num" ]]; then
                    if ufw status numbered | grep "\[$rule_num\]" | grep -q "Blacklist"; then
                        ufw --force delete $rule_num >> "$LOG_FILE" 2>&1
                    fi
                fi
            done < "$current_rules_file"
        fi
        rm -f "$current_rules_file"
        
    elif [[ "$FIREWALL_TYPE" == "iptables" ]]; then
        # Remove existing blacklist rules
        iptables-save | grep "BLACKLIST" | while read -r line; do
            rule=$(echo "$line" | sed 's/-A /-D /')
            eval "iptables $rule" 2>> "$LOG_FILE"
        done
    fi
}

# Apply rules
apply_firewall_rules() {
    log "Скачивание блеклиста с $BLACKLIST_URL..."
    
    if ! curl -s "$BLACKLIST_URL" -o "$TEMP_FILE"; then
        log "ОШИБКА: Не удалось скачать блеклист"
        exit 1
    fi
    
    if [[ ! -s "$TEMP_FILE" ]]; then
        log "ОШИБКА: Скачанный файл пуст"
        exit 1
    fi
    
    log "Чтение подсетей..."
    subnets=$(cat "$TEMP_FILE")
    
    if [[ -z "$subnets" ]]; then
        log "ОШИБКА: Подсети не найдены"
        exit 1
    fi
    
    total=$(echo "$subnets" | wc -l)
    current=0
    added_count=0
    skipped_count=0
    
    log "Применение правил фаервола..."
    
    while IFS= read -r subnet; do
        [[ -z "$subnet" ]] && continue
        
        if [[ "$FIREWALL_TYPE" == "ufw" ]]; then
            if ! ufw status | grep "$subnet" | grep -q "Blacklist"; then
                ufw insert 1 deny from "$subnet" comment "Blacklist" >> "$LOG_FILE" 2>&1
                ((added_count++))
            else
                ((skipped_count++))
            fi
            
        elif [[ "$FIREWALL_TYPE" == "iptables" ]]; then
            # Check if rule exists
            if ! iptables -C INPUT -s "$subnet" -j DROP -m comment --comment "BLACKLIST" 2>/dev/null; then
                iptables -I INPUT -s "$subnet" -j DROP -m comment --comment "BLACKLIST"
                ((added_count++))
            else
                ((skipped_count++))
            fi
        fi
        
        ((current++))
        show_progress "$current" "$total"
    done <<< "$subnets"
    printf "\n"
    
    log "Добавлено новых правил: $added_count"
    log "Пропущено существующих правил: $skipped_count"
    
    # Save iptables rules if using iptables
    if [[ "$FIREWALL_TYPE" == "iptables" ]]; then
        if command -v netfilter-persistent &> /dev/null; then
            netfilter-persistent save >> "$LOG_FILE" 2>&1
        elif command -v iptables-save &> /dev/null; then
            if [[ -f /etc/debian_version ]]; then
                iptables-save > /etc/iptables/rules.v4
            elif [[ -f /etc/redhat-release ]]; then
                service iptables save >> "$LOG_FILE" 2>&1
            fi
        fi
        log "Правила iptables сохранены"
    fi
}

# Main execution
cleanup_old_rules
apply_firewall_rules
rm -f "$TEMP_FILE"
log "Обновление блеклиста фаервола успешно завершено"
SCRIPT_EOF

# Replace placeholders
sed -i.bak "s|__BLACKLIST_URL__|$BLACKLIST_URL|g" "$SCRIPT_PATH"
sed -i.bak "s|__TEMP_FILE__|$TEMP_FILE|g" "$SCRIPT_PATH"
sed -i.bak "s|__LOG_FILE__|$LOG_FILE|g" "$SCRIPT_PATH"
sed -i.bak "s|__FIREWALL_TYPE__|$FIREWALL_TYPE|g" "$SCRIPT_PATH"
rm -f "$SCRIPT_PATH.bak"

chmod +x "$SCRIPT_PATH"
echo -e "${GREEN}✓ Скрипт установлен в $SCRIPT_PATH${NC}"
echo ""

# Setup logrotate
echo -e "${YELLOW}Настройка ротации логов...${NC}"
cat > /etc/logrotate.d/firewall-blacklist << 'LOGROTATE_EOF'
/var/log/firewall_blacklist.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    maxsize 10M
}
LOGROTATE_EOF

echo -e "${GREEN}✓ Ротация логов настроена (7 дней, макс 10MB)${NC}"
echo ""

# Setup cron if needed
if [[ -n "$CRON_TIME" ]]; then
    echo -e "${YELLOW}Настройка автоматических обновлений...${NC}"
    
    # Remove existing cron job
    crontab -l 2>/dev/null | grep -v "firewall-blacklist.sh" | crontab -
    
    # Add new cron job
    (crontab -l 2>/dev/null; echo "$CRON_TIME $SCRIPT_PATH >> $LOG_FILE 2>&1") | crontab -
    
    echo -e "${GREEN}✓ Задание cron добавлено: $SCHEDULE_DESC${NC}"
    echo ""
fi

# Ask to run now
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Установка успешно завершена!${NC}"
echo ""
echo -e "${YELLOW}Хотите запустить обновление блеклиста сейчас?${NC}"
read -p "Запустить? [Y/n]: " run_now

if [[ "$run_now" =~ ^[Yy]$ ]] || [[ -z "$run_now" ]]; then
    echo ""
    echo -e "${YELLOW}Запуск обновления блеклиста...${NC}"
    echo ""
    "$SCRIPT_PATH"
    echo ""
fi

# Show summary
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Сводка:${NC}"
echo -e "  Фаервол:      ${YELLOW}$FIREWALL_TYPE${NC}"
echo -e "  Скрипт:       ${YELLOW}$SCRIPT_PATH${NC}"
echo -e "  Лог-файл:     ${YELLOW}$LOG_FILE${NC}"
if [[ -n "$CRON_TIME" ]]; then
    echo -e "  Расписание:   ${YELLOW}$SCHEDULE_DESC${NC}"
else
    echo -e "  Расписание:   ${YELLOW}Только вручную${NC}"
fi
echo ""
echo -e "${YELLOW}Ручной запуск:${NC}"
echo -e "  sudo $SCRIPT_PATH"
echo ""
echo -e "${YELLOW}Просмотр логов:${NC}"
echo -e "  sudo tail -f $LOG_FILE"
echo ""
echo -e "${YELLOW}Просмотр правил:${NC}"
if [[ "$FIREWALL_TYPE" == "ufw" ]]; then
    echo -e "  sudo ufw status | grep Blacklist"
else
    echo -e "  sudo iptables -L INPUT -n | grep BLACKLIST"
fi
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Для удаления используйте:${NC}"
echo "  wget https://raw.githubusercontent.com/AndreyTimoschuk/norkn/main/uninstall.sh && sudo bash uninstall.sh"
echo ""
echo -e "${GREEN}NO, THANKS RKN!${NC}"
echo ""

