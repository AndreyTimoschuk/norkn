#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_PATH="/usr/local/bin/firewall-blacklist.sh"
LOG_FILE="/var/log/firewall_blacklist.log"

# Check if running as root - multiple methods
ROOT_CHECK_FAILED=0

if [[ $EUID -ne 0 ]]; then
    ROOT_CHECK_FAILED=1
fi

if [[ $(id -u) -ne 0 ]]; then
    ROOT_CHECK_FAILED=1
fi

if ! touch /etc/.test_write 2>/dev/null; then
    ROOT_CHECK_FAILED=1
fi
rm -f /etc/.test_write 2>/dev/null

if [[ $ROOT_CHECK_FAILED -eq 1 ]]; then
   echo ""
   echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
   echo -e "${RED}║  ОШИБКА: Скрипт ДОЛЖЕН быть запущен от root!             ║${NC}"
   echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
   echo ""
   echo -e "${YELLOW}Используйте:${NC}"
   echo -e "  ${GREEN}sudo bash uninstall.sh${NC}"
   echo ""
   exit 1
fi

clear
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}              ${RED}Деинсталлятор NO, THANKS RKN${NC}              ${BLUE}║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Этот скрипт удалит:${NC}"
echo "  • Задания cron"
echo "  • Правила фаервола (помеченные как Blacklist)"
echo "  • Установленный скрипт"
echo "  • Лог-файлы"
echo ""
echo -e "${RED}ВНИМАНИЕ: Это действие нельзя отменить!${NC}"
echo ""
read -p "Продолжить деинсталляцию? [y/N]: " confirm

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Деинсталляция отменена${NC}"
    exit 0
fi

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

# Detect firewall type by checking which one has Blacklist rules
FIREWALL_TYPE=""
if command -v ufw &> /dev/null; then
    if ufw status 2>/dev/null | grep -q "Blacklist"; then
        FIREWALL_TYPE="ufw"
    fi
fi

if [ -z "$FIREWALL_TYPE" ] && command -v iptables &> /dev/null; then
    if iptables -L INPUT -n 2>/dev/null | grep -q "BLACKLIST"; then
        FIREWALL_TYPE="iptables"
    fi
fi

# Step 1: Remove cron job
echo -e "${YELLOW}[1/4] Удаление задания cron...${NC}"
if crontab -l 2>/dev/null | grep -q "firewall-blacklist.sh"; then
    crontab -l 2>/dev/null | grep -v "firewall-blacklist.sh" | crontab -
    echo -e "${GREEN}✓ Задание cron удалено${NC}"
else
    echo -e "${YELLOW}• Задание cron не найдено${NC}"
fi
echo ""

# Step 2: Remove firewall rules
echo -e "${YELLOW}[2/4] Удаление правил фаервола...${NC}"

if [ "$FIREWALL_TYPE" = "ufw" ]; then
    echo "Удаление правил UFW..."
    rules_file="/tmp/blacklist_rules_to_delete.txt"
    ufw status numbered | grep "Blacklist" | awk -F'[][]' '{print $2}' | sort -nr > "$rules_file"
    
    if [ -s "$rules_file" ]; then
        rules_count=$(wc -l < "$rules_file")
        echo "Найдено правил: $rules_count"
        
        while read -r rule_num; do
            if [ -n "$rule_num" ]; then
                ufw --force delete "$rule_num" >/dev/null 2>&1
                echo -ne "\rУдалено правил: $((++deleted_count))/$rules_count"
            fi
        done < "$rules_file"
        echo ""
        rm -f "$rules_file"
        echo -e "${GREEN}✓ Правила UFW удалены${NC}"
    else
        echo -e "${YELLOW}• Правила UFW не найдены${NC}"
    fi
    
elif [ "$FIREWALL_TYPE" = "iptables" ]; then
    echo "Удаление правил iptables..."
    
    # IPv4 rules
    if iptables -L INPUT -n 2>/dev/null | grep -q "BLACKLIST"; then
        iptables-save | grep "BLACKLIST" | while read -r line; do
            rule=$(echo "$line" | sed 's/-A /-D /')
            eval "iptables $rule" 2>/dev/null
        done
        echo "• IPv4 правила удалены"
    fi
    
    # IPv6 rules
    if ip6tables -L INPUT -n 2>/dev/null | grep -q "BLACKLIST"; then
        ip6tables-save | grep "BLACKLIST" | while read -r line; do
            rule=$(echo "$line" | sed 's/-A /-D /')
            eval "ip6tables $rule" 2>/dev/null
        done
        echo "• IPv6 правила удалены"
    fi
    
    # Delete ipsets
    if ipset list blacklist-v4 &>/dev/null; then
        ipset destroy blacklist-v4 2>/dev/null
        echo "• IPSet blacklist-v4 удален"
    fi
    
    if ipset list blacklist-v6 &>/dev/null; then
        ipset destroy blacklist-v6 2>/dev/null
        echo "• IPSet blacklist-v6 удален"
    fi
    
    # Save iptables rules
    if command -v netfilter-persistent &> /dev/null; then
        netfilter-persistent save >/dev/null 2>&1
    elif command -v iptables-save &> /dev/null; then
        if [[ -f /etc/debian_version ]]; then
            iptables-save > /etc/iptables/rules.v4 2>/dev/null
            ip6tables-save > /etc/iptables/rules.v6 2>/dev/null
        elif [[ -f /etc/redhat-release ]]; then
            service iptables save >/dev/null 2>&1
            service ip6tables save >/dev/null 2>&1
        fi
    fi
    
    echo -e "${GREEN}✓ Правила iptables удалены${NC}"
else
    echo -e "${YELLOW}• Правила фаервола не найдены${NC}"
fi
echo ""

# Step 3: Remove script
echo -e "${YELLOW}[3/4] Удаление скрипта...${NC}"
if [ -f "$SCRIPT_PATH" ]; then
    rm -f "$SCRIPT_PATH"
    echo -e "${GREEN}✓ Скрипт удален: $SCRIPT_PATH${NC}"
else
    echo -e "${YELLOW}• Скрипт не найден${NC}"
fi
echo ""

# Step 4: Remove logrotate config
echo -e "${YELLOW}[4/5] Удаление конфигурации logrotate...${NC}"
if [ -f "/etc/logrotate.d/firewall-blacklist" ]; then
    rm -f /etc/logrotate.d/firewall-blacklist
    echo -e "${GREEN}✓ Конфигурация logrotate удалена${NC}"
else
    echo -e "${YELLOW}• Конфигурация logrotate не найдена${NC}"
fi
echo ""

# Step 5: Clean up logs
echo -e "${YELLOW}[5/5] Очистка логов...${NC}"
read -p "Удалить лог-файлы? [y/N]: " clean_logs

if [[ "$clean_logs" =~ ^[Yy]$ ]]; then
    if [ -f "$LOG_FILE" ]; then
        rm -f "$LOG_FILE"
        # Remove rotated logs too
        rm -f "$LOG_FILE"*.gz 2>/dev/null
        rm -f "$LOG_FILE".1 2>/dev/null
        echo -e "${GREEN}✓ Лог-файлы удалены${NC}"
    else
        echo -e "${YELLOW}• Лог-файл не найден${NC}"
    fi
else
    echo -e "${YELLOW}• Лог-файлы сохранены${NC}"
fi
echo ""

# Summary
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Деинсталляция завершена!${NC}"
echo ""
echo -e "${YELLOW}Что было удалено:${NC}"
echo "  ✓ Задания cron"
if [ -n "$FIREWALL_TYPE" ]; then
    echo "  ✓ Правила фаервола ($FIREWALL_TYPE)"
else
    echo "  • Правила фаервола (не найдены)"
fi
echo "  ✓ Скрипт управления"
echo "  ✓ Конфигурация logrotate"
if [[ "$clean_logs" =~ ^[Yy]$ ]]; then
    echo "  ✓ Лог-файлы"
else
    echo "  • Лог-файлы (сохранены)"
fi
echo ""
echo -e "${GREEN}Спасибо за использование NO, THANKS RKN!${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

