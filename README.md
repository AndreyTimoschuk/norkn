# Firewall Blacklist Auto-Installer

Automatic firewall blacklist management with interactive installation. Supports both UFW and iptables.

## Quick Install

```bash
wget https://raw.githubusercontent.com/YOUR_USERNAME/firewall-blacklist/main/install.sh -O install.sh && chmod +x install.sh && sudo bash install.sh
```

Or with curl:

```bash
curl -O https://raw.githubusercontent.com/YOUR_USERNAME/firewall-blacklist/main/install.sh && chmod +x install.sh && sudo bash install.sh
```

## Features

- 🔥 **Multi-Firewall Support** - Works with UFW and iptables
- ⚡ **Interactive Installation** - Easy setup with guided prompts
- ⏰ **Flexible Scheduling** - Choose when to update blacklist
- 🔄 **Auto Updates** - Automatic blacklist updates via cron
- 📊 **Progress Tracking** - Real-time progress display
- 📝 **Detailed Logging** - All operations logged
- 🛡️ **Smart Management** - Removes old rules before adding new ones

## What It Does

The installer will:

1. Ask you to choose between UFW or iptables
2. Install and configure your chosen firewall
3. Let you set update schedule (daily, weekly, or manual)
4. Install the blacklist management script
5. Optionally run the first update immediately

## Requirements

- Linux system (Debian/Ubuntu or RHEL/CentOS)
- Root/sudo access
- `curl` or `wget`
- Internet connection

## Manual Usage

After installation, you can manually run:

```bash
sudo /usr/local/bin/firewall-blacklist.sh
```

View logs:

```bash
sudo tail -f /var/log/firewall_blacklist.log
```

Check rules:

```bash
# For UFW
sudo ufw status | grep Blacklist

# For iptables
sudo iptables -L INPUT -n | grep BLACKLIST
```

## Uninstall

Remove the script:

```bash
sudo rm /usr/local/bin/firewall-blacklist.sh
```

Remove cron job:

```bash
sudo crontab -e
# Remove the line containing firewall-blacklist.sh
```

Remove rules (UFW):

```bash
sudo ufw status numbered | grep "Blacklist" | awk -F'[][]' '{print $2}' | sort -nr | while read n; do sudo ufw --force delete $n; done
```

Remove rules (iptables):

```bash
sudo iptables-save | grep "BLACKLIST" | while read -r line; do
    rule=$(echo "$line" | sed 's/-A /-D /')
    eval "sudo iptables $rule"
done
sudo netfilter-persistent save
```

## Default Blacklist Source

Uses: [C24Be/AS_Network_List](https://github.com/C24Be/AS_Network_List)

To change the source, edit `/usr/local/bin/firewall-blacklist.sh` and modify the `BLACKLIST_URL` variable.

## License

MIT License - See LICENSE file

