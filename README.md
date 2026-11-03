# Nexus BBS Telnet & SSH Gateway Suite

[](https://www.python.org/)
[](https://wiki.mysticbbs.com/)
[](https://datatracker.ietf.org/doc/html/rfc854)
[](https://datatracker.ietf.org/doc/html/rfc4254)
[](https://en.wikipedia.org/wiki/Code_page_437)
[License](https://www.google.com/search?q=LICENSE)

> A Port 23 Telnet and SSH BBS gateway that greets callers with a custom `gateway.ans` screen and an interactive ANSI lightbar menu, routing connections seamlessly to local nodes or external Telnet/SSH BBSes. All routes, timeouts, and colors live in a human-readable `gateway.cfg` file editable in any text editor or inside Mystic BBS via an MPL script.

---

## Table of Contents

- [Overview](#overview)
- [System Architecture & Key Features](#system-architecture--key-features)
- [Repository Structure](#repository-structure)
- [Prerequisites & Installation](#prerequisites--installation)
- [Quick Start Guide](#quick-start-guide)
- [Mystic BBS Integration](#mystic-bbs-integration)
- [Configuration Reference (`gateway.cfg`)](#configuration-reference-gatewaycfg)
- [Terminal & Codec Compatibility](#terminal--codec-compatibility)
- [Keybindings & Controls](#keybindings--controls)
- [Troubleshooting & FAQ](#troubleshooting--faq)

---

## Overview

Modern BBS SysOps often run multiple services on a single server—such as a primary [Mystic BBS](https://wiki.mysticbbs.com/doku.php?id=introduction) installation, dedicated legacy door game nodes (e.g., DOSBox door servers, TradeWars 2002 game servers), and external community boards. Managing external access to multiple nodes traditionally required exposing multiple non-standard ports to callers or maintaining complex port-forwarding tables.

The **Nexus BBS Gateway Suite** solves this by establishing a single point of entry on standard Telnet Port 23 (and optionally SSH Port 2222). Callers are greeted with an authentic 80x25 CP437 ANSI art screen (`gateway.ans`), presented with a scrollable lightbar menu of available systems, and bridged directly to their selected local or remote destination without ever exposing internal node topology.

---

## System Architecture & Key Features

* **Standard Port 23 Telnet Server**: Implements RFC 854/856/857/858 Telnet option negotiation (`IAC WILL BINARY`, `IAC WILL ECHO`, `IAC WILL SGA`, and `IAC WONT LINEMODE`) as documented in [Mystic v1.10 Telnet Release Notes](https://wiki.mysticbbs.com/doku.php?id=whats_new_110), placing terminal clients (SyncTERM, NetRunner, mTelnet, PuTTY) immediately into unbuffered 8-bit character-at-a-time CP437 mode.
* **Dual Telnet & SSH Bridging**:
  * **Telnet Targets (`LOCAL` / `EXTERNAL`)**: Transparent, bidirectional TCP stream piping between the incoming caller and local IP ports (`127.0.0.1:2323`, LAN subnets) or remote FQDNs (`agency.bbs.nz:23`).
  * **SSH Targets (`SSH-LOC` / `SSH-EXT`)**: Connects to secure SSH-based BBSes using `asyncssh` or a zero-dependency POSIX pseudo-terminal (PTY) fallback wrapping the system `/usr/bin/ssh` client. Supports pre-configured credentials (`user:pass@host` or `user@host`) or prompts callers interactively for username and password.
* **Optional Inbound SSH Gateway**: An optional asynchronous SSH server (`SSH_ENABLED = TRUE`) that listens on a dedicated port (e.g. `2222`), auto-generates host keys, and serves the exact same ANSI lightbar gateway interface over encrypted SSH.
* **ANSI-BBS & CP437 Codec Fidelity**:
  * Emits strict 79-column rows with explicit `ESC[row;colH` cursor positioning, completely eliminating 80th-column auto-wrap double-spacing bugs in Mystic, SyncTERM, and NetRunner.
  * Uses pure 8-bit CP437 box-drawing codes (`╔═╗║╠╣╟─╢╚╝░▒▓█`) and pointer symbols (`»`, `0xAF`), avoiding non-standard VT220 private mode escapes (`ESC[?25l`) that display raw `25l`/`25h` visual noise on ANSI-BBS decoders.
  * Automatically strips trailing 128-byte SAUCE metadata headers and DOS `0x1A` EOF markers from `.ans` files.
  * Translates Mystic pipe color codes (`|00` through `|23`) and screen MCI codes (`|CL`, `|CR`, `|[X##`, `|[Y##`) into standard ANSI SGR sequences.
* **Interactive Lightbar Selector**: Arrow-key navigation (`UP`/`DOWN`/`HOME`/`END`/`PGUP`/`PGDN`), single-key hotkey activation (`1`–`9`, `A`–`Z`), live TCP ping latency probing (`[P]`), and dynamic description updating.
* **Mystic BBS MPL Integration**: Includes `gwconfig.mps`, an integrated [Mystic Programming Language](https://wiki.mysticbbs.com/doku.php?id=mpl) script utilizing Mystic's native file and terminal routines ([Mystic MPL Functions Reference](https://wiki.mysticbbs.com/doku.php?id=mpl_functions)) (`fAssign`, `fReset`, `fReWrite`, `WriteXYPipe`, `Input`, `AllowArrow`). SysOps can add, edit, reorder, delete listings, and adjust gateway parameters directly from Mystic's SysOp menu.
* **Human-Readable Configuration (`gateway.cfg`)**: Flat, structured key-value and pipe-delimited text configuration that can be edited in `nano`, `vi`, Notepad, or the Mystic MPL script without restarting the gateway daemon.

---

## Repository Structure

```
├── bbs_gateway.py     # Main asynchronous Telnet & SSH Gateway server engine
├── gwconfig.mps       # Mystic BBS MPL configuration script source code
├── gateway.cfg        # Human-readable configuration and BBS directory file
├── gateway.ans        # Default 79-column 8-bit CP437 ANSI header and frame
└── README.md          # Complete documentation and setup manual
```

---

## Prerequisites & Installation

### System Requirements
* **Operating System**: Linux, macOS, FreeBSD, or Windows 10/11 / Server.
* **Python Runtime**: Python 3.8 or higher (`asyncio` standard library).
* **Mystic BBS** (optional): Mystic BBS v1.12 A1 or newer to compile and run `gwconfig.mps`.

### Package Dependencies
Outbound Telnet and outbound SSH work out-of-the-box using the standard Python library and the system `/usr/bin/ssh` binary. If you wish to enable the **Inbound SSH Gateway Server** or prefer pure-Python outbound SSH sessions, install `asyncssh`:

```bash
pip install asyncssh
```

---

## Quick Start Guide

### 1. Validate the Configuration File
Before launching the service, verify that your `gateway.cfg` parses cleanly:

```bash
python3 bbs_gateway.py --check-config
```

Example output:
```text
Gateway Title : The Nexus BBS Telnet & SSH Gateway
SysOp Name    : SysOp
Telnet Socket : 0.0.0.0:23
Inbound SSH   : DISABLED (Port 2222)
ANSI File     : gateway.ans (Mode: BOTH)
BBS Listings  : 7 configured
  1. [1] Mystic Main (Telnet)   -> 127.0.0.1:2323 [LOCAL / TELNET] - Primary Mystic BBS Node
  2. [2] Mystic Secure (SSH)    -> 127.0.0.1:2222 [SSH-LOC / SSH] - Local Mystic BBS SSH Server
  3. [3] Agency BBS             -> agency.bbs.nz:23 [EXTERNAL / TELNET] - Official Mystic BBS Support
```

### 2. Test on an Unprivileged Port
Test the gateway locally on port `2323` without root permissions:

```bash
python3 bbs_gateway.py --port 2323
```

Connect using any standard Telnet or BBS client:
```bash
syncterm -t telnet://localhost:2323
# or
telnet localhost 2323
```

### 3. Deploy on Standard Port 23
To bind to privileged port `23` on Linux:

**Option A (Recommended — Grant non-root bind capabilities):**
```bash
sudo setcap 'cap_net_bind_service=+ep' $(readlink -f $(which python3))
python3 bbs_gateway.py -c /path/to/gateway.cfg
```

**Option B (Run with elevated privileges):**
```bash
sudo python3 bbs_gateway.py -c /path/to/gateway.cfg
```

### 4. Background Service (Systemd Unit)
Create `/etc/systemd/system/bbs-gateway.service`:

```ini
[Unit]
Description=Nexus Telnet & SSH BBS Gateway
After=network.target

[Service]
Type=simple
User=mystic
WorkingDirectory=/mystic/gateway
ExecStart=/usr/bin/python3 /mystic/gateway/bbs_gateway.py -c /mystic/gateway/gateway.cfg
Restart=always
RestartSec=5
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
```

Enable and start the service:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now bbs-gateway
```

---

## Mystic BBS Integration

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

## Keybindings & Controls

### Caller Controls (Gateway Menu)

| Key | Description |
| :--- | :--- |
| `UP` / `DOWN` / `LEFT` / `RIGHT` | Navigate the lightbar selector through listed BBS nodes. |
| `PGUP` / `PGDN` | Jump up or down by the number of visible rows (`MENU_ROWS`). |
| `HOME` / `END` | Jump directly to the first or last listing. |
| `ENTER` | Connect immediately to the currently highlighted BBS. |
| `1`–`9` / `A`–`Z` | Hotkey direct connect (connects instantly without moving lightbar). |
| `P` | **Ping All**: Sends an active TCP probe to each board and displays live latency (`UP 14ms` / `OFFLINE`). |
| `L` | Toggle between `ANSI_HOTKEY` full-screen art and interactive Lightbar mode. |
| `Q` or `ESC` | Exit the gateway cleanly. |

### SysOp Controls (`gwconfig.mpx` inside Mystic)

| Key | Description |
| :--- | :--- |
| `UP` / `DOWN` | Move the editor selector across BBS entries. |
| `A` | **Add**: Prompt for system name, host/IP, port, mode, and description. |
| `E` or `ENTER` | **Edit**: Modify parameters of the selected BBS entry. |
| `D` | **Delete**: Remove the selected BBS entry with confirmation. |
| `U` / `N` | **Move Up / Down**: Reorder BBS entries in the lightbar display. |
| `O` | **Options**: Edit titles, ports, timeouts, inbound SSH settings, and colors. |
| `V` | **View**: Display the configured `gateway.ans` inside Mystic. |
| `P` | **Path**: Switch active `gateway.cfg` file path. |
| `S` | **Save**: Write memory state back to `gateway.cfg`. |
| `Q` or `ESC` | Exit to Mystic BBS (prompts to save if modifications are unsaved). |

---

## Troubleshooting & FAQ

#### Q: The lightbar displays strange letters like `â”€` instead of border boxes.
**A:** Your client terminal is set to UTF-8 decoding instead of IBM Code Page 437 (CP437). In PuTTY, switch **Window > Translation** to **CP437**. In SyncTERM or NetRunner, ensure terminal emulation is set to **ANSI-BBS**.

#### Q: Mystic BBS prints `25l` or `25h` at the top of the screen.
**A:** Ensure you are using the latest `bbs_gateway.py`. Older builds contained VT220 private mode escapes (`ESC[?25l`) which have been replaced with standard CP437 cursor placement.

#### Q: Why can't I bind to port 23?
**A:** Ports under 1024 require elevated privileges on UNIX-like systems. Run with `sudo` or execute:
```bash
sudo setcap 'cap_net_bind_service=+ep' $(readlink -f $(which python3))
```

#### Q: Can I hide the caller's SSH password in `gateway.cfg`?
**A:** Yes. If you configure `Host` as `bbs.example.com` or `user@bbs.example.com` without a password, the gateway will securely prompt the caller for their password using masked asterisks (`*`) before opening the SSH connection.

---

## License

This project is licensed under the MIT License — see the [LICENSE](https://www.google.com/search?q=LICENSE) file for details.
