#!/usr/bin/env bash
# ===========================================================================
# Nexus BBS Telnet & SSH Gateway - Linux Production Firewall Script
# ===========================================================================
# Hardens Linux hosts running public BBS Telnet (Port 23) and SSH (Port 2222)
# services against automated port scanners, Mirai botnets, SYN flood attacks,
# and brute-force connection hammering.
#
# USAGE:
#   sudo chmod +x gateway_firewall.sh
#   sudo ./gateway_firewall.sh [apply | status | flush]
# ===========================================================================

set -euo pipefail

TELNET_PORT="23"
SSH_GATEWAY_PORT="2222"
ADMIN_SSH_PORT="22"

# Rate limit thresholds: Max 6 new connection attempts per 30 seconds per IP
RATE_LIMIT_SECONDS="30"
RATE_LIMIT_HITS="6"

COLOR_RED="\033[1;31m"
COLOR_GREEN="\033[1;32m"
COLOR_YELLOW="\033[1;33m"
COLOR_CYAN="\033[1;36m"
COLOR_RESET="\033[0m"

require_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${COLOR_RED}[!] Error: This script must be run as root (sudo).${COLOR_RESET}"
        exit 1
    fi
}

enable_kernel_hardening() {
    echo -e "${COLOR_CYAN}[*] Applying Linux kernel TCP/IP hardening parameters...${COLOR_RESET}"
    
    # Enable TCP SYN Cookies (Protection against SYN flood attacks)
    sysctl -w net.ipv4.tcp_syncookies=1 >/dev/null
    
    # Ignore broadcast ICMP ping requests
    sysctl -w net.ipv4.icmp_echo_ignore_broadcasts=1 >/dev/null
    
    # Disable IP packet forwarding (Prevents gateway from being used as a network router)
    sysctl -w net.ipv4.ip_forward=0 >/dev/null
    
    # Enable reverse path filtering (Anti-IP spoofing)
    sysctl -w net.ipv4.conf.all.rp_filter=1 >/dev/null
    sysctl -w net.ipv4.conf.default.rp_filter=1 >/dev/null
    
    # Reduce TCP FIN timeout to quickly recycle closed sockets
    sysctl -w net.ipv4.tcp_fin_timeout=15 >/dev/null
    
    echo -e "${COLOR_GREEN}[+] Kernel hardening parameters applied.${COLOR_RESET}"
}

apply_firewall_rules() {
    require_root
    enable_kernel_hardening

    echo -e "${COLOR_CYAN}[*] Configuring iptables packet filtering rules for BBS Gateway...${COLOR_RESET}"

    # 1. Allow established and related connections
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    # 2. Allow all loopback traffic (localhost <-> internal BBS nodes)
    iptables -A INPUT -i lo -j ACCEPT

    # 3. Allow Admin Host SSH (Port 22)
    iptables -A INPUT -p tcp --dport "$ADMIN_SSH_PORT" -m conntrack --ctstate NEW -j ACCEPT

    # 4. Create dedicated rate-limiting chain for BBS Gateway Port 23
    iptables -N BBS_TELNET_LIMIT 2>/dev/null || iptables -F BBS_TELNET_LIMIT
    
    # Check if IP has hit rate limit within the time window
    iptables -A BBS_TELNET_LIMIT -m recent --name BBS_TELNET_SCAN --set
    iptables -A BBS_TELNET_LIMIT -m recent --name BBS_TELNET_SCAN --update --seconds "$RATE_LIMIT_SECONDS" --hitcount "$RATE_LIMIT_HITS" -j LOG --log-prefix "BBS_GATEWAY_THROTTLE: " --log-level 4
    iptables -A BBS_TELNET_LIMIT -m recent --name BBS_TELNET_SCAN --update --seconds "$RATE_LIMIT_SECONDS" --hitcount "$RATE_LIMIT_HITS" -j DROP
    iptables -A BBS_TELNET_LIMIT -j ACCEPT

    # Route new inbound connections on Telnet Port 23 to rate-limiting chain
    iptables -A INPUT -p tcp --dport "$TELNET_PORT" --syn -m conntrack --ctstate NEW -j BBS_TELNET_LIMIT

    # 5. Create dedicated rate-limiting chain for Inbound SSH Gateway (Port 2222)
    iptables -N BBS_SSH_LIMIT 2>/dev/null || iptables -F BBS_SSH_LIMIT
    iptables -A BBS_SSH_LIMIT -m recent --name BBS_SSH_SCAN --set
    iptables -A BBS_SSH_LIMIT -m recent --name BBS_SSH_SCAN --update --seconds "$RATE_LIMIT_SECONDS" --hitcount "$RATE_LIMIT_HITS" -j LOG --log-prefix "BBS_SSH_THROTTLE: " --log-level 4
    iptables -A BBS_SSH_LIMIT -m recent --name BBS_SSH_SCAN --update --seconds "$RATE_LIMIT_SECONDS" --hitcount "$RATE_LIMIT_HITS" -j DROP
    iptables -A BBS_SSH_LIMIT -j ACCEPT

    iptables -A INPUT -p tcp --dport "$SSH_GATEWAY_PORT" --syn -m conntrack --ctstate NEW -j BBS_SSH_LIMIT

    echo -e "${COLOR_GREEN}[+] Gateway firewall rules successfully activated!${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}[i] Port $TELNET_PORT (Telnet) & Port $SSH_GATEWAY_PORT (SSH) rate-limited to $RATE_LIMIT_HITS hits per ${RATE_LIMIT_SECONDS}s per IP.${COLOR_RESET}"
}

show_status() {
    require_root
    echo -e "${COLOR_CYAN}=== Current BBS Gateway Firewall Chains ===${COLOR_RESET}"
    iptables -L BBS_TELNET_LIMIT -n -v --line-numbers 2>/dev/null || echo "BBS_TELNET_LIMIT chain not active."
    echo ""
    iptables -L BBS_SSH_LIMIT -n -v --line-numbers 2>/dev/null || echo "BBS_SSH_LIMIT chain not active."
}

flush_rules() {
    require_root
    echo -e "${COLOR_YELLOW}[*] Flushing BBS Gateway custom firewall chains...${COLOR_RESET}"
    iptables -D INPUT -p tcp --dport "$TELNET_PORT" --syn -m conntrack --ctstate NEW -j BBS_TELNET_LIMIT 2>/dev/null || true
    iptables -D INPUT -p tcp --dport "$SSH_GATEWAY_PORT" --syn -m conntrack --ctstate NEW -j BBS_SSH_LIMIT 2>/dev/null || true
    iptables -F BBS_TELNET_LIMIT 2>/dev/null || true
    iptables -X BBS_TELNET_LIMIT 2>/dev/null || true
    iptables -F BBS_SSH_LIMIT 2>/dev/null || true
    iptables -X BBS_SSH_LIMIT 2>/dev/null || true
    echo -e "${COLOR_GREEN}[+] BBS Gateway firewall chains flushed.${COLOR_RESET}"
}

case "${1:-apply}" in
    apply)
        apply_firewall_rules
        ;;
    status)
        show_status
        ;;
    flush)
        flush_rules
        ;;
    *)
        echo "Usage: $0 [apply | status | flush]"
        exit 1
        ;;
esac
