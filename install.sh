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
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root (use sudo)${NC}"
   exit 1
fi

clear
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}           ${GREEN}Firewall Blacklist Installer${NC}                 ${BLUE}║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}This script will install automatic blacklist management${NC}"
echo -e "${YELLOW}for your firewall with scheduled updates.${NC}"
echo ""

# Function to show progress
show_progress() {
    local current=$1
    local total=$2
    local percent=$((current * 100 / total))
    printf "\r${YELLOW}Progress: %d%%${NC}" "$percent"
}

# Step 1: Choose firewall
echo -e "${GREEN}[1/4] Select Firewall Type${NC}"
echo ""
echo "  1) UFW (Uncomplicated Firewall)"
echo "  2) iptables (Direct iptables management)"
echo ""
read -p "Choose firewall [1-2]: " fw_choice

case $fw_choice in
    1)
        FIREWALL_TYPE="ufw"
        echo -e "${GREEN}✓ Selected: UFW${NC}"
        ;;
    2)
        FIREWALL_TYPE="iptables"
        echo -e "${GREEN}✓ Selected: iptables${NC}"
        ;;
    *)
        echo -e "${RED}Invalid choice. Exiting.${NC}"
        exit 1
        ;;
esac
echo ""

# Step 2: Install firewall if needed
echo -e "${GREEN}[2/4] Installing Firewall${NC}"

install_firewall() {
    if [[ "$FIREWALL_TYPE" == "ufw" ]]; then
        if ! command -v ufw &> /dev/null; then
            echo "Installing UFW..."
            if [[ -f /etc/debian_version ]]; then
                apt-get update && apt-get install -y ufw
            elif [[ -f /etc/redhat-release ]]; then
                yum install -y ufw
            else
                echo -e "${RED}Unsupported OS. Please install UFW manually.${NC}"
                exit 1
            fi
        else
            echo "UFW is already installed"
        fi
        
        # Enable UFW if not active
        if ! ufw status | grep -q "Status: active"; then
            echo "Enabling UFW..."
            ufw --force enable
        fi
        echo -e "${GREEN}✓ UFW is ready${NC}"
        
    elif [[ "$FIREWALL_TYPE" == "iptables" ]]; then
        if ! command -v iptables &> /dev/null; then
            echo "Installing iptables..."
            if [[ -f /etc/debian_version ]]; then
                apt-get update && apt-get install -y iptables iptables-persistent
            elif [[ -f /etc/redhat-release ]]; then
                yum install -y iptables iptables-services
                systemctl enable iptables
                systemctl start iptables
            else
                echo -e "${RED}Unsupported OS. Please install iptables manually.${NC}"
                exit 1
            fi
        else
            echo "iptables is already installed"
        fi
        echo -e "${GREEN}✓ iptables is ready${NC}"
    fi
}

install_firewall
echo ""

# Step 3: Choose schedule
echo -e "${GREEN}[3/4] Configure Update Schedule${NC}"
echo ""
echo "  1) Daily at 03:00"
echo "  2) Daily at 04:00"
echo "  3) Daily at 05:00"
echo "  4) Weekly (Monday at 03:00)"
echo "  5) Custom time"
echo "  6) Manual only (no automatic updates)"
echo ""
read -p "Choose schedule [1-6]: " schedule_choice

case $schedule_choice in
    1)
        CRON_TIME="0 3 * * *"
        SCHEDULE_DESC="Daily at 03:00"
        ;;
    2)
        CRON_TIME="0 4 * * *"
        SCHEDULE_DESC="Daily at 04:00"
        ;;
    3)
        CRON_TIME="0 5 * * *"
        SCHEDULE_DESC="Daily at 05:00"
        ;;
    4)
        CRON_TIME="0 3 * * 1"
        SCHEDULE_DESC="Weekly on Monday at 03:00"
        ;;
    5)
        read -p "Enter hour (0-23): " hour
        read -p "Enter minute (0-59): " minute
        CRON_TIME="$minute $hour * * *"
        SCHEDULE_DESC="Daily at $hour:$minute"
        ;;
    6)
        CRON_TIME=""
        SCHEDULE_DESC="Manual only"
        ;;
    *)
        echo -e "${RED}Invalid choice. Using default: Daily at 03:00${NC}"
        CRON_TIME="0 3 * * *"
        SCHEDULE_DESC="Daily at 03:00"
        ;;
esac

if [[ -n "$CRON_TIME" ]]; then
    echo -e "${GREEN}✓ Schedule set: $SCHEDULE_DESC${NC}"
else
    echo -e "${GREEN}✓ Manual mode (no automatic updates)${NC}"
fi
echo ""

# Step 4: Create the main script
echo -e "${GREEN}[4/4] Installing Blacklist Script${NC}"

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
    printf "\rProgress: %d%%" "$percent"
}

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Check root
[[ $EUID -ne 0 ]] && { log "ERROR: Must be run as root"; exit 1; }

log "Starting firewall blacklist update..."

# Cleanup old rules
cleanup_old_rules() {
    log "Cleaning up old blacklist rules..."
    
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
    log "Downloading blacklist from $BLACKLIST_URL..."
    
    if ! curl -s "$BLACKLIST_URL" -o "$TEMP_FILE"; then
        log "ERROR: Failed to download blacklist"
        exit 1
    fi
    
    if [[ ! -s "$TEMP_FILE" ]]; then
        log "ERROR: Downloaded file is empty"
        exit 1
    fi
    
    log "Reading subnets..."
    subnets=$(cat "$TEMP_FILE")
    
    if [[ -z "$subnets" ]]; then
        log "ERROR: No subnets found"
        exit 1
    fi
    
    total=$(echo "$subnets" | wc -l)
    current=0
    added_count=0
    skipped_count=0
    
    log "Applying firewall rules..."
    
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
    
    log "Added new rules: $added_count"
    log "Skipped existing rules: $skipped_count"
    
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
        log "iptables rules saved"
    fi
}

# Main execution
cleanup_old_rules
apply_firewall_rules
rm -f "$TEMP_FILE"
log "Firewall blacklist update completed successfully"
SCRIPT_EOF

# Replace placeholders
sed -i.bak "s|__BLACKLIST_URL__|$BLACKLIST_URL|g" "$SCRIPT_PATH"
sed -i.bak "s|__TEMP_FILE__|$TEMP_FILE|g" "$SCRIPT_PATH"
sed -i.bak "s|__LOG_FILE__|$LOG_FILE|g" "$SCRIPT_PATH"
sed -i.bak "s|__FIREWALL_TYPE__|$FIREWALL_TYPE|g" "$SCRIPT_PATH"
rm -f "$SCRIPT_PATH.bak"

chmod +x "$SCRIPT_PATH"
echo -e "${GREEN}✓ Script installed to $SCRIPT_PATH${NC}"
echo ""

# Setup cron if needed
if [[ -n "$CRON_TIME" ]]; then
    echo -e "${YELLOW}Setting up automatic updates...${NC}"
    
    # Remove existing cron job
    crontab -l 2>/dev/null | grep -v "firewall-blacklist.sh" | crontab -
    
    # Add new cron job
    (crontab -l 2>/dev/null; echo "$CRON_TIME $SCRIPT_PATH >> $LOG_FILE 2>&1") | crontab -
    
    echo -e "${GREEN}✓ Cron job added: $SCHEDULE_DESC${NC}"
    echo ""
fi

# Ask to run now
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Installation completed successfully!${NC}"
echo ""
echo -e "${YELLOW}Would you like to run the blacklist update now?${NC}"
read -p "Run now? [Y/n]: " run_now

if [[ "$run_now" =~ ^[Yy]$ ]] || [[ -z "$run_now" ]]; then
    echo ""
    echo -e "${YELLOW}Running blacklist update...${NC}"
    echo ""
    "$SCRIPT_PATH"
    echo ""
fi

# Show summary
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Summary:${NC}"
echo -e "  Firewall:     ${YELLOW}$FIREWALL_TYPE${NC}"
echo -e "  Script:       ${YELLOW}$SCRIPT_PATH${NC}"
echo -e "  Log file:     ${YELLOW}$LOG_FILE${NC}"
if [[ -n "$CRON_TIME" ]]; then
    echo -e "  Schedule:     ${YELLOW}$SCHEDULE_DESC${NC}"
else
    echo -e "  Schedule:     ${YELLOW}Manual only${NC}"
fi
echo ""
echo -e "${YELLOW}Manual usage:${NC}"
echo -e "  sudo $SCRIPT_PATH"
echo ""
echo -e "${YELLOW}View logs:${NC}"
echo -e "  sudo tail -f $LOG_FILE"
echo ""
echo -e "${YELLOW}View current rules:${NC}"
if [[ "$FIREWALL_TYPE" == "ufw" ]]; then
    echo -e "  sudo ufw status | grep Blacklist"
else
    echo -e "  sudo iptables -L INPUT -n | grep BLACKLIST"
fi
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}Thank you for using Firewall Blacklist!${NC}"
echo ""

