# Nexus BBS Telnet & SSH Gateway Suite

[![Python Version](https://img.shields.io/badge/Python-3.8%2B-blue.svg)](https://www.python.org/)
[![Mystic BBS](https://img.shields.io/badge/Mystic_BBS-MPL_1.12%2B-purple.svg)](https://wiki.mysticbbs.com/)
[![Telnet Protocol](https://img.shields.io/badge/Protocol-Telnet_%28RFC_854%29-green.svg)](https://datatracker.ietf.org/doc/html/rfc854)
[![SSH Protocol](https://img.shields.io/badge/Protocol-SSH_%28RFC_4254%29-red.svg)](https://datatracker.ietf.org/doc/html/rfc4254)
[![Terminal Standard](https://img.shields.io/badge/Encoding-CP437_%2F_ANSI--BBS-orange.svg)](https://en.wikipedia.org/wiki/Code_page_437)
[![Security Hardened](https://img.shields.io/badge/Security-Firewall_%26_Rate_Limited-brightgreen.svg)](#security--hardening-guide)
[![License](https://img.shields.io/badge/License-MIT-lightgrey.svg)](LICENSE)

> A Port 23 Telnet and SSH BBS gateway that greets callers with a custom `gateway.ans` screen and an interactive ANSI lightbar menu, routing connections seamlessly to local nodes or external Telnet/SSH BBSes. All routes, timeouts, and colors live in a human-readable `gateway.cfg` file editable in any text editor or inside Mystic BBS via an MPL script.

---

## Table of Contents

- [Overview](#overview)
- [System Architecture & Key Features](#system-architecture--key-features)
- [Repository Package Files](#repository-package-files)
- [Prerequisites & Quick Start](#prerequisites--quick-start)
- [Security & Hardening Guide](#security--hardening-guide)
  - [1. Built-in Application Security Engine](#1-built-in-application-security-engine)
  - [2. Linux Host Firewall (`gateway_firewall.sh`)](#2-linux-host-firewall-gateway_firewallsh)
  - [3. Fail2ban Integration](#3-fail2ban-integration)
  - [4. Anti-SSRF & Network Isolation](#4-anti-ssrf--network-isolation)
- [Mystic BBS Integration Walkthrough](#mystic-bbs-integration-walkthrough)
- [Configuration Reference (`gateway.cfg`)](#configuration-reference-gatewaycfg)
- [Terminal & Codec Compatibility](#terminal--codec-compatibility)
- [Keybindings & Controls Reference](#keybindings--controls-reference)
- [Troubleshooting & FAQ](#troubleshooting--faq)

---

## Overview

Modern BBS SysOps often run multiple services on a single server—such as a primary [Mystic BBS](https://wiki.mysticbbs.com/doku.php?id=introduction) installation, dedicated legacy door game nodes (e.g., DOSBox door servers, TradeWars 2002 game servers), and external community boards. Managing external access to multiple nodes traditionally required exposing multiple non-standard ports to callers or maintaining complex port-forwarding tables.

The **Nexus BBS Gateway Suite** establishes a single point of entry on standard Telnet Port 23 (and optionally SSH Port 2222). Callers are greeted with an authentic 80x25 CP437 ANSI art screen (`gateway.ans`), presented with a scrollable lightbar menu of available systems, and bridged directly to their selected local or remote destination without ever exposing internal node topology.

---

## System Architecture & Key Features

* **Standard Port 23 Telnet Server**: Implements RFC 854/856/857/858 Telnet option negotiation (`IAC WILL BINARY`, `IAC WILL ECHO`, `IAC WILL SGA`, and `IAC WONT LINEMODE`) as documented in [Mystic v1.10 Telnet Release Notes](https://wiki.mysticbbs.com/doku.php?id=whats_new_110), placing terminal clients (SyncTERM, NetRunner, mTelnet, PuTTY) immediately into unbuffered 8-bit character-at-a-time CP437 mode.
* **Dual Telnet & SSH Outbound Bridging**:
  * **Telnet Targets (`LOCAL` / `EXTERNAL`)**: Transparent, bidirectional TCP stream piping between the incoming caller and local IP ports (`127.0.0.1:2323`, LAN subnets) or remote FQDNs (`agency.bbs.nz:23`). Relays remote Telnet IAC options directly to the caller terminal so dynamic window sizes (RFC 1073 NAWS) and terminal types (RFC 1091 TTYPE) work transparently.
  * **SSH Targets (`SSH-LOC` / `SSH-EXT`)**: Connects to secure SSH-based BBSes using `asyncssh` or a zero-dependency POSIX pseudo-terminal (PTY) fallback wrapping the system `/usr/bin/ssh` client. Supports pre-configured credentials (`user:pass@host` or `user@host`) or prompts callers interactively for username and password.
* **Optional Inbound SSH Gateway**: An optional asynchronous SSH server (`SSH_ENABLED = TRUE`) that listens on a dedicated port (e.g. `2222`), auto-generates host keys, and serves the exact same ANSI lightbar gateway interface over encrypted SSH.
* **Multi-Tier Defense-in-Depth Security**:
  * Sliding-window connection rate limiting with automatic temporary IP bans (anti-hammering / anti-botnet protection).
  * Concurrency caps per IP (`MAX_CONNECTIONS_PER_IP`) to prevent node exhaustion and duplicate session flooding.
  * Global node capacity ceiling (`MAX_TOTAL_NODES`) preventing memory and socket exhaustion.
  * IP allowlisting and denylisting with support for exact IPs, CIDR subnets, and wildcard ranges (`192.168.1.*`), fully compatible with Mystic's `denylist.txt` and `allowlist.txt`.
  * Anti-SSRF destination guard blocking connections to link-local metadata endpoints (`169.254.169.254`) and preventing re-entrant loopback deadlocks.
* **Concurrent Parallel Ping Probing**: Probes all configured local and remote boards concurrently using `asyncio.gather()`, displaying clean latency measurements (e.g. `89ms`, `DOWN`) under the `SCOPE` column within ~1.5 seconds regardless of how many boards are unreachable.
* **ANSI-BBS & CP437 Codec Fidelity**:
  * Emits strict 79-column rows with explicit `ESC[row;colH` cursor positioning, completely eliminating 80th-column auto-wrap double-spacing bugs in Mystic, SyncTERM, and NetRunner.
  * Uses pure 8-bit CP437 box-drawing codes (`╔═╗║╠╣╟─╢╚╝░▒▓█`) and pointer symbols (`»`, `0xAF`), avoiding non-standard VT220 private mode escapes (`ESC[?25l`) that display raw `25l`/`25h` visual noise on ANSI-BBS decoders.
  * Automatically strips trailing 128-byte SAUCE metadata headers and DOS `0x1A` EOF markers from `.ans` files.
  * Translates Mystic pipe color codes (`|00` through `|23`) and screen MCI codes (`|CL`, `|CR`, `|[X##`, `|[Y##`) into standard ANSI SGR sequences.
* **Interactive Lightbar Selector**: Arrow-key navigation (`UP`/`DOWN`/`HOME`/`END`/`PGUP`/`PGDN`), single-key hotkey activation (`1`–`9`, `A`–`Z` with automated exclusion of reserved keys `L`, `P`, `Q`), live TCP ping latency probing (`[P]`), and dynamic description updating.
* **Mystic BBS MPL Integration**: Includes `gwconfig.mps`, an integrated [Mystic Programming Language](https://wiki.mysticbbs.com/doku.php?id=mpl) script utilizing Mystic's native file and terminal routines ([Mystic MPL Functions Reference](https://wiki.mysticbbs.com/doku.php?id=mpl_functions)) (`fAssign`, `fReset`, `fReWrite`, `WriteXYPipe`, `Input`, `AllowArrow`). SysOps can add, edit, reorder, delete listings, and adjust gateway parameters directly from Mystic's SysOp menu.
* **Human-Readable Configuration (`gateway.cfg`)**: Flat, structured key-value and pipe-delimited text configuration that can be edited in `nano`, `vi`, Notepad, or the Mystic MPL script without restarting the gateway daemon.

---

## Repository Package Files

| File | Type | Purpose |
| :--- | :--- | :--- |
| `bbs_gateway.py` | Python 3 Server | Main asynchronous Telnet & SSH server, CP437 ANSI engine, rate-limiting firewall, and Telnet/SSH proxy. |
| `gwconfig.mps` | Mystic MPL Script | Full-screen SysOp configuration manager compiled with [MPLC](https://wiki.mysticbbs.com/doku.php?id=introduction) (`gwconfig.mpx`) to maintain `gateway.cfg` inside Mystic. |
| `gateway.cfg` | Configuration File | Shared human-readable text configuration file defining gateway titles, ports, lightbar layout, security, and BBS listings. |
| `gateway.ans` | ANSI Art Screen | Default 79-column 8-bit CP437 ANSI header and menu frame displayed upon connection. |
| `gateway_firewall.sh` | Bash Script | Linux kernel TCP SYN flood hardening and `iptables` rate-limiting firewall script. |
| `denylist.txt` | Text File | Blocked IP addresses, CIDR subnets, and wildcard IP prefixes. |
| `allowlist.txt` | Text File | Whitelisted IP addresses exempt from rate-limits, connection caps, and bans. |
| `bbs_gateway_suite.zip` | ZIP Archive | Pre-packaged bundle containing all project source files, assets, and documentation. |
| `README.md` | Markdown File | Complete architecture, setup manual, and reference guide. |

---

## Prerequisites & Quick Start

### System Requirements
* **Python**: Python 3.8 or higher.
* **OS**: Linux, macOS, FreeBSD, or Windows.
* **Optional**: `pip install asyncssh` (required only if enabling the Inbound SSH Gateway server; outbound SSH works out-of-the-box via system `/usr/bin/ssh`).

### 1. Validate Configuration
Verify that `gateway.cfg` syntax parses cleanly:
```bash
python3 bbs_gateway.py --check-config
```

### 2. Test on Unprivileged Port
Run the gateway on port `2323` for local testing:
```bash
python3 bbs_gateway.py --port 2323
```
Connect using any terminal client:
```bash
syncterm -t telnet://localhost:2323
```

### 3. Deploy on Standard Port 23
Grant Python permission to bind to port 23 without running as root:
```bash
sudo setcap 'cap_net_bind_service=+ep' $(readlink -f $(which python3))
python3 bbs_gateway.py -c /path/to/gateway.cfg
```
Or run directly under root / systemd:
```bash
sudo python3 bbs_gateway.py -c /path/to/gateway.cfg
```

---

## Security & Hardening Guide

Because Port 23 is a frequent target for internet port scanners and automated botnets (e.g., Mirai), the Nexus Gateway implements **multi-tier defense-in-depth**:

```
+-------------------------------------------------------------+
|  Tier 1: OS Kernel & Packet Filter (gateway_firewall.sh)    |
|  - SYN Cookie protection (Anti-SYN flood)                   |
|  - iptables / nftables SYN connection rate throttling       |
+-------------------------------------------------------------+
                              |
+-------------------------------------------------------------+
|  Tier 2: Fail2ban Host Log Monitor (Optional)               |
|  - Scans bbs_gateway.log for [FIREWALL REJECT] events       |
|  - Drops repeat offender IPs at kernel firewall level       |
+-------------------------------------------------------------+
                              |
+-------------------------------------------------------------+
|  Tier 3: Built-in Application Security (bbs_gateway.py)     |
|  - Allowlist bypass / Denylist drops (CIDR, wildcard)       |
|  - Sliding-window connection frequency rate-limiter         |
|  - Automatic temporary IP bans (AUTO_BAN_DURATION)          |
|  - Max concurrent connections per IP (Anti-DupeIP)          |
|  - Global capacity cap (MAX_TOTAL_NODES)                    |
|  - Anti-SSRF & Loopback re-entrancy blocking                |
+-------------------------------------------------------------+
```

### 1. Built-in Application Security Engine

Configured in `gateway.cfg` and evaluated automatically for every incoming caller:

* **IP Denylist (`denylist.txt`)**: Rejects connections before Telnet option negotiation begins. Supports exact IPs (`203.0.113.5`), CIDR subnets (`203.0.113.0/24`), and wildcards (`198.51.100.*`). Callers receive an access-denied message and are immediately disconnected.
* **IP Allowlist (`allowlist.txt`)**: Trusted IPs (e.g. SysOp home IP, LAN subnets `192.168.0.0/16`, localhost `127.0.0.1`) bypass rate limiting, concurrency caps, and denylists.
* **Mystic BBS Integration (`MYSTIC_DATA_PATH`)**: If pointing to your Mystic data directory (e.g. `/mystic/data/`), the gateway automatically loads and inherits Mystic's existing `denylist.txt` and `allowlist.txt` files!
* **Connection Rate-Limiter & Auto-Ban**: If a single IP opens more than `RATE_LIMIT_CONNECTIONS` (default: 5) within `RATE_LIMIT_WINDOW` (default: 60 seconds), the gateway automatically issues a temporary ban for `AUTO_BAN_DURATION` (default: 900 seconds / 15 minutes) and logs `[FIREWALL REJECT] RATE_LIMIT`.
* **Per-IP Concurrency Guard (`MAX_CONNECTIONS_PER_IP = 2`)**: Prevents automated scripts or malicious users from opening dozens of simultaneous sockets to consume your BBS nodes. Excess connections receive `Connection Refused: Only 2 concurrent connection(s) allowed per IP` and are dropped.
* **Global Capacity Ceiling (`MAX_TOTAL_NODES = 32`)**: Protects server memory and file descriptors by enforcing a maximum active caller limit across the entire gateway. When full, callers receive a busy notice and are closed gracefully.

### 2. Linux Host Firewall (`gateway_firewall.sh`)

A dedicated firewall script is provided in the repository to harden Linux hosts:

```bash
sudo chmod +x gateway_firewall.sh
sudo ./gateway_firewall.sh apply
```

**Actions Performed by `gateway_firewall.sh`**:
1. Enables Linux kernel TCP SYN cookies (`net.ipv4.tcp_syncookies = 1`) to absorb SYN flood attacks.
2. Disables kernel IP forwarding (`net.ipv4.ip_forward = 0`) to prevent traffic routing abuse.
3. Configures an `iptables` rate-limiting chain on Port 23 and Port 2222 using the `recent` kernel module:
   * Tracks connection bursts per source IP.
   * Allows normal dialing while silently dropping rapid connection scans (exceeding 6 new connections per 30 seconds).
4. Provides commands to check status (`sudo ./gateway_firewall.sh status`) and remove rules (`sudo ./gateway_firewall.sh flush`).

### 3. Fail2ban Integration

To ban repeat abusers at the OS firewall level before packets reach Python:

**1. Create `/etc/fail2ban/filter.d/bbs-gateway.conf`**:
```ini
[Definition]
failregex = ^.*\[FIREWALL REJECT\] Caller <HOST> rejected: (RATE_LIMIT|BANNED|DENYLIST).*$
ignoreregex =
```

**2. Create `/etc/fail2ban/jail.d/bbs-gateway.local`**:
```ini
[bbs-gateway]
enabled = true
port = 23,2222
filter = bbs-gateway
logpath = /mystic/gateway/bbs_gateway.log
maxretry = 3
findtime = 300
bantime = 3600
```

### 4. Anti-SSRF & Network Isolation

* **Re-entrancy Loop Prevention**: `bbs_gateway.py` verifies destination addresses in `gateway.cfg` and actively blocks connections targeting `127.0.0.1`, `localhost`, or `0.0.0.0` on the gateway's own listen ports (`23` and `2222`), preventing infinite connection recursion.
* **Cloud Metadata Block**: Prohibits outbound proxy connections targeting link-local cloud metadata addresses (`169.254.169.254`), preventing AWS/GCP/Azure instance credential exfiltration.
* **Credential Masking**: For SSH targets where you do not wish to store a cleartext password in `gateway.cfg`, omit the password (`user@host`); the gateway will securely prompt the caller for their password using masked asterisks (`*`) over the encrypted channel.

---

## Mystic BBS Integration Walkthrough

The companion MPL script `gwconfig.mps` allows SysOps to maintain the gateway directory and server parameters directly from a Mystic BBS menu node.

### Step 1: Adjust Mystic's Internal Telnet Port
If Mystic runs on the same physical server as the gateway, Mystic's internal Telnet server must not collide on port 23:

1. Open Mystic Configuration:
   ```bash
   cd /mystic
   ./mystic -cfg
   ```
2. Navigate to **Servers > Configure Servers > Telnet**.
3. Change **Port** from `23` to `2323`.
4. Ensure Mystic's internal Telnet server is enabled and save.
5. In `gateway.cfg`, set your primary local BBS entry to:
   ```ini
   BBS = 1 | Mystic Main BBS | 127.0.0.1 | 2323 | LOCAL | Primary Mystic Node
   ```

### Step 2: Compile `gwconfig.mps`
1. Copy `gwconfig.mps` into your Mystic script directory:
   ```bash
   cp gwconfig.mps /mystic/themes/default/scripts/
   ```
2. Compile using the [Mystic MPL Compiler](https://wiki.mysticbbs.com/doku.php?id=introduction) (`mplc`):
   ```bash
   cd /mystic
   ./mplc /mystic/themes/default/scripts/gwconfig.mps
   ```
   This generates `gwconfig.mpx`.

### Step 3: Add to Mystic SysOp Menu
1. In `mystic -cfg`, navigate to **Visual Customization > Menus**.
2. Open your SysOp menu (e.g., `sysop.mnu`).
3. Add a new menu command:
   * **Hot Key**: `G`
   * **Command**: `GX` (Execute MPL Program)
   * **Data**: `gwconfig /mystic/gateway/gateway.cfg`
   * **Access ACS**: `s255` (or your SysOp security level)

---

## Configuration Reference (`gateway.cfg`)

`gateway.cfg` uses standard `KEY = VALUE` syntax. Blank lines and lines beginning with `#` or `;` are ignored.

```ini
# ===========================================================================
# GENERAL SETTINGS
# ===========================================================================
GATEWAY_TITLE = The Nexus BBS Telnet & SSH Gateway
SYSOP_NAME    = SysOp
LISTEN_HOST   = 0.0.0.0
LISTEN_PORT   = 23
ANSI_FILE     = gateway.ans

# ===========================================================================
# INBOUND SSH SERVER (Optional, requires 'asyncssh')
# ===========================================================================
SSH_ENABLED     = FALSE
SSH_LISTEN_PORT = 2222
SSH_HOST_KEY    = gateway_ssh_host_key

# ===========================================================================
# SECURITY, FIREWALL & ACCESS CONTROL
# ===========================================================================
SECURITY_ENABLED       = TRUE
MAX_CONNECTIONS_PER_IP = 2      # Anti-node-hogging limit per remote IP
MAX_TOTAL_NODES        = 32     # Total simultaneous caller capacity
RATE_LIMIT_CONNECTIONS = 5      # Max connection attempts before auto-ban
RATE_LIMIT_WINDOW      = 60     # Sliding window size in seconds
AUTO_BAN_DURATION      = 900    # Ban duration in seconds (15 minutes)
DENYLIST_FILE          = denylist.txt
ALLOWLIST_FILE         = allowlist.txt
MYSTIC_DATA_PATH       =        # Optional: path to /mystic/data to sync denylist

# ===========================================================================
# DISPLAY & LIGHTBAR LAYOUT
# ===========================================================================
# DISPLAY_MODE:
#   BOTH        - Displays gateway.ans background and overlays lightbar
#   LIGHTBAR    - Draws an auto-generated CP437 box-drawing lightbar frame
#   ANSI_HOTKEY - Displays gateway.ans only; waits for hotkeys (press L for lightbar)
DISPLAY_MODE = BOTH

# Screen Coordinates (79-column safe coordinates)
MENU_START_X = 3
MENU_START_Y = 7
MENU_WIDTH   = 75
MENU_ROWS    = 10

# ===========================================================================
# TIMEOUTS & SESSION CONTROLS
# ===========================================================================
IDLE_TIMEOUT            = 180    # Seconds before disconnecting inactive callers
CONNECT_TIMEOUT         = 15     # Seconds to wait for outbound TCP connect
RETURN_AFTER_DISCONNECT = TRUE   # Return caller to menu when target BBS closes

# ===========================================================================
# COLOR ATTRIBUTES (0-15 FG, 0-7 BG)
# ===========================================================================
COLOR_HEADER    = 15   # Bright White
COLOR_BORDER    = 11   # Light Cyan
COLOR_ITEM_FG   = 7    # Light Gray
COLOR_ITEM_BG   = 0    # Black
COLOR_HILITE_FG = 15   # Bright White
COLOR_HILITE_BG = 1    # Blue

# ===========================================================================
# DIRECTORY LISTINGS
# Format: BBS = Hotkey | Name | Host | Port | Mode | Description
#
# Supported Modes:
#   LOCAL    - Local Telnet node (127.0.0.1 or LAN IP)
#   EXTERNAL - Remote internet Telnet BBS
#   SSH-LOC  - Local SSH BBS (prompts caller for credentials if omitted)
#   SSH-EXT  - Remote internet SSH BBS (supports user:pass@host syntax)
# ===========================================================================
BBS = 1 | Mystic Main (Telnet) | 127.0.0.1             | 2323 | LOCAL    | Primary Mystic BBS Node (Local Port 2323)
BBS = 2 | Mystic Secure (SSH)  | 127.0.0.1             | 2222 | SSH-LOC  | Local Mystic BBS SSH Server
BBS = 3 | Retro Door Server    | 192.168.1.50          | 2023 | LOCAL    | Local LAN Classic Door Games & TW2002
BBS = 4 | Agency BBS           | agency.bbs.nz         | 23   | EXTERNAL | Official Mystic BBS Support & FSXNet Hub
BBS = 5 | Agency BBS (SSH)     | bbs:bbs@agency.bbs.nz | 22   | SSH-EXT  | Official Mystic BBS via Outbound SSH Tunnel
BBS = 6 | Distortion BBS       | d1st.org              | 23   | EXTERNAL | Underground ANSI Art, Mods & Cyberculture
BBS = 7 | Absinthe BBS         | absinthebbs.net       | 1940 | EXTERNAL | Amiga & Retro Computing Board
```

---

## Terminal & Codec Compatibility

| Terminal / Client | Platform | Recommended Settings | Compatibility Notes |
| :--- | :--- | :--- | :--- |
| **SyncTERM** | Windows / Linux / macOS | ANSI-BBS, Font: MS-DOS CP437 | Native arrow keys, 8-bit CP437 block characters, and clean color rendering. |
| **NetRunner** | Windows / Linux | ANSI-BBS, Baud: 57600+ | Supports authentic IBM font glyphs and high-intensity backgrounds. |
| **mTelnet** | Windows | ANSI-BBS, CP437 | Fully supported. |
| **PuTTY** | Windows / Linux | Connection > Data > Terminal-type: `ansi`<br>Window > Translation: `CP437` | Set character set translation to CP437 to prevent UTF-8 box distortion. |
| **Mystic NodeSpy / Internal** | Cross-platform | Native | 79-column restriction ensures zero auto-wrap double line feeds. |

---

## Keybindings & Controls Reference

### Caller Controls (Gateway Menu)

| Key | Description |
| :--- | :--- |
| `UP` / `DOWN` / `LEFT` / `RIGHT` | Navigate the lightbar selector through listed BBS nodes. |
| `PGUP` / `PGDN` | Jump up or down by the number of visible rows (`MENU_ROWS`). |
| `HOME` / `END` | Jump directly to the first or last listing. |
| `ENTER` | Connect immediately to the currently highlighted BBS. |
| `1`–`9` / `A`–`Z` | Hotkey direct connect (connects instantly without moving lightbar; skips reserved keys `L`, `P`, `Q`). |
| `P` | **Ping All**: Concurrent parallel TCP probe across all nodes with clean latency display (`89ms` / `DOWN`). |
| `L` | Toggle between `ANSI_HOTKEY` full-screen art and interactive Lightbar mode. |
| `Q` or `ESC` | Exit the gateway cleanly. |

### SysOp Controls (`gwconfig.mpx` inside Mystic)

| Key | Description |
| :--- | :--- |
| `UP` / `DOWN` | Move the editor selector across BBS entries. |
| `A` | **Add**: Prompt for system name, host/IP, port, mode, and description (auto-assigns next unreserved hotkey). |
| `E` or `ENTER` | **Edit**: Modify parameters of the selected BBS entry (validates against reserved keys `L`, `P`, `Q`). |
| `D` | **Delete**: Remove the selected BBS entry with confirmation. |
| `U` / `N` | **Move Up / Down**: Reorder BBS entries in the lightbar display. |
| `O` | **Options**: Edit titles, ports, timeouts, inbound SSH settings, and colors. |
| `V` | **View**: Display the configured `gateway.ans` inside Mystic. |
| `P` | **Path**: Switch active `gateway.cfg` file path. |
| `S` | **Save**: Write memory state back to `gateway.cfg`. |
| `Q` or `ESC` | Exit to Mystic BBS (prompts to save if modifications are unsaved). |

---

## Troubleshooting & FAQ

#### Q: How do I protect against Mirai and automated Telnet scanner spam?
**A:** Ensure `SECURITY_ENABLED = TRUE` in `gateway.cfg` (enabled by default) and run `sudo ./gateway_firewall.sh apply`. This activates dual-layer rate limiting: `iptables` throttles rapid SYN attempts at the network level, while `bbs_gateway.py` automatically bans IPs attempting rapid connections.

#### Q: How do I whitelist my own IP or remote friends from rate-limiting?
**A:** Add your IP or subnet to `allowlist.txt` (e.g. `192.168.1.0/24` or your static public IP). IPs in `allowlist.txt` bypass all concurrency limits, rate-limit counters, and ban checks.

#### Q: How do I share banned IPs with Mystic BBS?
**A:** In `gateway.cfg`, set `MYSTIC_DATA_PATH = /mystic/data/`. The gateway will automatically read Mystic's `denylist.txt` and `allowlist.txt` alongside its own local filter files.

#### Q: The lightbar displays strange letters like `â”€` instead of border boxes.
**A:** Your client terminal is set to UTF-8 decoding instead of IBM Code Page 437 (CP437). In PuTTY, switch **Window > Translation** to **CP437**. In SyncTERM or NetRunner, ensure terminal emulation is set to **ANSI-BBS**.

#### Q: Why can't I bind to port 23?
**A:** Ports under 1024 require elevated privileges on UNIX-like systems. Run with `sudo` or execute:
```bash
sudo setcap 'cap_net_bind_service=+ep' $(readlink -f $(which python3))
```

---

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
