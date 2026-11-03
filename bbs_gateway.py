#!/usr/bin/env python3
"""
BBS Telnet & SSH Gateway Server (bbs_gateway.py)
================================================
Listens on Telnet Port 23 (and optionally an inbound SSH port via `asyncssh`),
negotiates 8-bit binary CP437 character-mode options, displays `gateway.ans`
and/or an interactive CP437 ANSI lightbar menu, and bridges callers seamlessly
to:
  - Local or External Telnet BBS nodes (`LOCAL`, `EXTERNAL`)
  - Local or External SSH BBS nodes (`SSH-LOC`, `SSH-EXT`), using either
    `asyncssh` or a zero-dependency POSIX PTY + system `/usr/bin/ssh` bridge.

Designed for Mystic BBS / ANSI-BBS terminal codecs:
  - Transmits pure 8-bit IBM CP437 bytes (auto-converting UTF-8 .ans files)
  - Avoids unsupported VT220 private mode sequences (such as ESC[?25l)
  - Uses 79-column lines and explicit ESC[y;xH positioning to prevent 80-col wrap
  - Supports Mystic BBS pipe color codes (|00-|23) and screen MCI codes (|CL, |CR)
"""

from __future__ import annotations

import argparse
import asyncio
from dataclasses import dataclass, field
import errno
import fcntl
import logging
import os
import pty
import re
import shutil
import signal
import struct
import sys
import termios
import time
from typing import Dict, List, Optional, Tuple

try:
    import asyncssh  # Optional: enables native Python SSH client + Inbound SSH Server
    HAS_ASYNCSSH = True
except ImportError:
    HAS_ASYNCSSH = False

# Telnet Protocol Constants (RFC 854 / RFC 856 / RFC 857 / RFC 858)
IAC  = 255
DONT = 254
DO   = 253
WONT = 252
WILL = 251
SB   = 250
SE   = 240

OPT_BINARY   = 0
OPT_ECHO     = 1
OPT_SGA      = 3
OPT_TTYPE    = 24
OPT_NAWS     = 31
OPT_LINEMODE = 34

ESC = "\x1b"

DOS_FG_SGR = {
    0:  (0, 30),  # Black
    1:  (0, 34),  # Blue
    2:  (0, 32),  # Green
    3:  (0, 36),  # Cyan
    4:  (0, 31),  # Red
    5:  (0, 35),  # Magenta
    6:  (0, 33),  # Brown
    7:  (0, 37),  # Light Gray
    8:  (1, 30),  # Dark Gray
    9:  (1, 34),  # Light Blue
    10: (1, 32),  # Light Green
    11: (1, 36),  # Light Cyan
    12: (1, 31),  # Light Red
    13: (1, 35),  # Light Magenta
    14: (1, 33),  # Yellow
    15: (1, 37),  # White
}

DOS_BG_SGR = {
    0: 40,  # Black
    1: 44,  # Blue
    2: 42,  # Green
    3: 46,  # Cyan
    4: 41,  # Red
    5: 45,  # Magenta
    6: 43,  # Brown
    7: 47,  # Light Gray
}


def dos_color_to_ansi(fg: int, bg: int = 0) -> str:
    """Build a strict ANSI-BBS SGR escape sequence for DOS foreground (0-15) and background (0-7)."""
    bold, fg_code = DOS_FG_SGR.get(fg % 16, (0, 37))
    bg_code = DOS_BG_SGR.get(bg % 8, 40)
    if bold:
        return f"{ESC}[0;1;{fg_code};{bg_code}m"
    return f"{ESC}[0;{fg_code};{bg_code}m"


def mystic_pipe_to_ansi(text: str) -> str:
    """Convert Mystic BBS pipe color codes (|00 to |23) and MCI codes (|CL, |CR) into ANSI-BBS sequences."""
    text = text.replace("|CL", f"{ESC}[0m{ESC}[2J{ESC}[1;1H")
    text = text.replace("|CR", "\r\n")
    text = re.sub(r"\|\[X([0-9]{2})", lambda m: f"{ESC}[{int(m.group(1))}G", text)
    text = re.sub(r"\|\[Y([0-9]{2})", lambda m: f"{ESC}[{int(m.group(1))};1H", text)

    cur_fg = 7
    cur_bg = 0
    out: List[str] = []
    i = 0
    n = len(text)
    while i < n:
        if text[i] == "|" and i + 2 < n and text[i + 1:i + 3].isdigit():
            code = int(text[i + 1:i + 3])
            if 0 <= code <= 15:
                cur_fg = code
                out.append(dos_color_to_ansi(cur_fg, cur_bg))
                i += 3
                continue
            if 16 <= code <= 23:
                cur_bg = code - 16
                out.append(dos_color_to_ansi(cur_fg, cur_bg))
                i += 3
                continue
        out.append(text[i])
        i += 1
    return "".join(out)


@dataclass
class BBSEntry:
    """Represents a single target BBS (Telnet or SSH) in the gateway directory."""
    hotkey: str
    name: str
    host: str
    port: int
    scope: str = "EXTERNAL"  # LOCAL, EXTERNAL, SSH-LOC, or SSH-EXT
    description: str = ""

    @property
    def is_ssh(self) -> bool:
        return "SSH" in self.scope.upper() or self.host.lower().startswith("ssh://")

    def parse_target(self) -> Tuple[Optional[str], Optional[str], str]:
        """
        Extract optional (ssh_user, ssh_password, clean_hostname) from `host`.
        Supports `host`, `user@host`, `user:pass@host`, or `ssh://user:pass@host`.
        """
        raw = self.host.strip()
        if raw.lower().startswith("ssh://"):
            raw = raw[6:]
        if "@" in raw:
            creds, clean_host = raw.rsplit("@", 1)
            if ":" in creds:
                user, pw = creds.split(":", 1)
                return user, pw, clean_host
            return creds, None, clean_host
        return None, None, raw


@dataclass
class GatewayConfig:
    """Holds all human-readable settings loaded from gateway.cfg."""
    gateway_title: str = "The Nexus BBS Telnet & SSH Gateway"
    sysop_name: str = "SysOp"
    listen_host: str = "0.0.0.0"
    listen_port: int = 23
    ansi_file: str = "gateway.ans"
    ssh_enabled: bool = False
    ssh_listen_port: int = 2222
    ssh_host_key: str = "gateway_ssh_host_key"
    display_mode: str = "BOTH"  # BOTH, LIGHTBAR, or ANSI_HOTKEY
    menu_start_x: int = 3
    menu_start_y: int = 7
    menu_width: int = 75
    menu_rows: int = 10
    idle_timeout: int = 180
    connect_timeout: int = 15
    return_after_disconnect: bool = True
    color_header: int = 15
    color_border: int = 11
    color_item_fg: int = 7
    color_item_bg: int = 0
    color_hilite_fg: int = 15
    color_hilite_bg: int = 1
    bbs_list: List[BBSEntry] = field(default_factory=list)


def parse_bool(val: str) -> bool:
    return val.strip().upper() in ("TRUE", "YES", "1", "ON")


def load_gateway_config(cfg_path: str) -> GatewayConfig:
    """Load and parse the human-readable gateway.cfg file."""
    cfg = GatewayConfig()
    if not os.path.exists(cfg_path):
        logging.warning("Config file %s not found; using built-in defaults.", cfg_path)
        return cfg

    with open(cfg_path, "r", encoding="utf-8", errors="replace") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line or line.startswith("#") or line.startswith(";"):
                continue
            if "=" not in line:
                continue

            key, val = line.split("=", 1)
            key = key.strip().upper()
            val = val.strip()

            if key == "BBS":
                parts = [p.strip() for p in val.split("|")]
                if len(parts) >= 4:
                    hotkey = parts[0][:1].upper() if parts[0] else str(len(cfg.bbs_list) + 1)
                    name = parts[1]
                    host = parts[2]
                    try:
                        port = int(parts[3])
                    except ValueError:
                        port = 23
                    scope = parts[4].upper() if len(parts) >= 5 and parts[4] else (
                        "LOCAL" if host in ("127.0.0.1", "localhost") or host.startswith("192.168.") or host.startswith("10.") else "EXTERNAL"
                    )
                    desc = parts[5] if len(parts) >= 6 else ""
                    cfg.bbs_list.append(
                        BBSEntry(
                            hotkey=hotkey,
                            name=name,
                            host=host,
                            port=port,
                            scope=scope,
                            description=desc,
                        )
                    )
            elif key == "GATEWAY_TITLE":
                cfg.gateway_title = val
            elif key == "SYSOP_NAME":
                cfg.sysop_name = val
            elif key == "LISTEN_HOST":
                cfg.listen_host = val
            elif key == "LISTEN_PORT":
                try:
                    cfg.listen_port = int(val)
                except ValueError:
                    pass
            elif key == "ANSI_FILE":
                cfg.ansi_file = val
            elif key == "SSH_ENABLED":
                cfg.ssh_enabled = parse_bool(val)
            elif key == "SSH_LISTEN_PORT":
                try:
                    cfg.ssh_listen_port = int(val)
                except ValueError:
                    pass
            elif key == "SSH_HOST_KEY":
                cfg.ssh_host_key = val
            elif key == "DISPLAY_MODE":
                mode = val.upper()
                if mode in ("BOTH", "LIGHTBAR", "ANSI_HOTKEY"):
                    cfg.display_mode = mode
            elif key == "MENU_START_X":
                cfg.menu_start_x = max(1, int(val))
            elif key == "MENU_START_Y":
                cfg.menu_start_y = max(1, int(val))
            elif key == "MENU_WIDTH":
                cfg.menu_width = max(40, min(77, int(val)))
            elif key == "MENU_ROWS":
                cfg.menu_rows = max(3, min(18, int(val)))
            elif key == "IDLE_TIMEOUT":
                cfg.idle_timeout = max(10, int(val))
            elif key == "CONNECT_TIMEOUT":
                cfg.connect_timeout = max(3, int(val))
            elif key == "RETURN_AFTER_DISCONNECT":
                cfg.return_after_disconnect = parse_bool(val)
            elif key == "COLOR_HEADER":
                cfg.color_header = int(val)
            elif key == "COLOR_BORDER":
                cfg.color_border = int(val)
            elif key == "COLOR_ITEM_FG":
                cfg.color_item_fg = int(val)
            elif key == "COLOR_ITEM_BG":
                cfg.color_item_bg = int(val)
            elif key == "COLOR_HILITE_FG":
                cfg.color_hilite_fg = int(val)
            elif key == "COLOR_HILITE_BG":
                cfg.color_hilite_bg = int(val)

    return cfg


def read_ansi_file_cp437(ansi_path: str) -> bytes:
    """
    Read an ANSI art file (.ans), strip SAUCE metadata and 0x1A EOF markers,
    and ensure output is pure 8-bit CP437 bytes for ANSI-BBS terminals.
    """
    if not os.path.exists(ansi_path):
        return b""

    with open(ansi_path, "rb") as f:
        data = f.read()

    if len(data) >= 128 and data[-128:-123] == b"SAUCE":
        sauce_comments = data[-128 + 104]
        data = data[:-128]
        if sauce_comments > 0:
            comnt_len = 5 + (sauce_comments * 64)
            if len(data) >= comnt_len and data[-comnt_len:-comnt_len + 5] == b"COMNT":
                data = data[:-comnt_len]

    eof_idx = data.find(b"\x1a")
    if eof_idx != -1:
        data = data[:eof_idx]

    if b"\xe2\x94" in data or b"\xe2\x95" in data or b"\xe2\x96" in data:
        try:
            text = data.decode("utf-8")
            text = mystic_pipe_to_ansi(text)
            return text.encode("cp437", errors="replace")
        except UnicodeDecodeError:
            pass

    text = data.decode("cp437")
    if "|" in text:
        text = mystic_pipe_to_ansi(text)
    return text.encode("cp437", errors="replace")


class TelnetSession:
    """Manages an incoming Telnet (or SSH) caller, CP437 lightbar UI, and Telnet/SSH outbound proxy."""

    def __init__(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
        cfg_path: str,
        is_inbound_ssh: bool = False,
    ) -> None:
        self.reader = reader
        self.writer = writer
        self.cfg_path = cfg_path
        self.is_inbound_ssh = is_inbound_ssh
        self.cfg = load_gateway_config(cfg_path)
        peer = writer.get_extra_info("peername")
        self.client_ip = peer[0] if peer else "unknown"
        self.client_port = peer[1] if peer else 0
        self.selected_idx = 0
        self.scroll_offset = 0
        self.ping_status: Dict[int, str] = {}

    async def send_raw(self, data: bytes) -> None:
        """Write raw bytes to the caller stream."""
        self.writer.write(data)
        await self.writer.drain()

    async def send_ansi(self, text: str) -> None:
        """Convert Mystic pipe codes and encode as pure 8-bit CP437 for ANSI-BBS terminals."""
        parsed = mystic_pipe_to_ansi(text)
        await self.send_raw(parsed.encode("cp437", errors="replace"))

    async def negotiate_telnet_char_mode(self) -> None:
        """Negotiate 8-bit binary transmission and character-at-a-time mode for Telnet callers."""
        if self.is_inbound_ssh:
            return
        negotiation = bytes([
            IAC, WILL, OPT_BINARY,
            IAC, DO,   OPT_BINARY,
            IAC, WILL, OPT_ECHO,
            IAC, WILL, OPT_SGA,
            IAC, DO,   OPT_SGA,
            IAC, WONT, OPT_LINEMODE,
        ])
        await self.send_raw(negotiation)
        await asyncio.sleep(0.15)
        try:
            while True:
                chunk = await asyncio.wait_for(self.reader.read(256), timeout=0.05)
                if not chunk:
                    break
                _ = self._strip_telnet_iac(chunk)
        except asyncio.TimeoutError:
            pass

    @staticmethod
    def _strip_telnet_iac(data: bytes) -> bytes:
        """Filter out Telnet IAC (0xFF) command sequences from user keyboard input."""
        out = bytearray()
        i = 0
        n = len(data)
        while i < n:
            b = data[i]
            if b == IAC:
                if i + 1 < n and data[i + 1] == IAC:
                    out.append(IAC)
                    i += 2
                elif i + 1 < n and data[i + 1] in (WILL, WONT, DO, DONT):
                    i += 3
                elif i + 1 < n and data[i + 1] == SB:
                    i += 2
                    while i < n and data[i] != SE:
                        i += 1
                    i += 1
                else:
                    i += 2
            else:
                out.append(b)
                i += 1
        return bytes(out)

    async def read_key(self, timeout: Optional[float] = None) -> Optional[str]:
        """Read a single keypress or ANSI-BBS / VT100 / Doorway arrow key from the caller."""
        wait_timeout = timeout or self.cfg.idle_timeout
        while True:
            try:
                raw = await asyncio.wait_for(self.reader.read(64), timeout=wait_timeout)
            except asyncio.TimeoutError:
                return "TIMEOUT"

            if not raw:
                return None

            clean = raw if self.is_inbound_ssh else self._strip_telnet_iac(raw)
            if not clean:
                continue

            if clean.startswith(b"\x1b"):
                if clean in (b"\x1b[A", b"\x1bOA"):
                    return "UP"
                if clean in (b"\x1b[B", b"\x1bOB"):
                    return "DOWN"
                if clean in (b"\x1b[C", b"\x1bOC"):
                    return "RIGHT"
                if clean in (b"\x1b[D", b"\x1bOD"):
                    return "LEFT"
                if clean in (b"\x1b[H", b"\x1b[1~", b"\x1bOH"):
                    return "HOME"
                if clean in (b"\x1b[F", b"\x1b[4~", b"\x1bOF", b"\x1b[K"):
                    return "END"
                if clean in (b"\x1b[5~", b"\x1b[V"):
                    return "PGUP"
                if clean in (b"\x1b[6~", b"\x1b[U"):
                    return "PGDN"
                if clean == b"\x1b":
                    return "ESC"
                continue

            if clean[0] in (0x00, 0xE0) and len(clean) >= 2:
                scan = clean[1]
                if scan == 72:
                    return "UP"
                if scan == 80:
                    return "DOWN"
                if scan == 71:
                    return "HOME"
                if scan == 79:
                    return "END"
                if scan == 73:
                    return "PGUP"
                if scan == 81:
                    return "PGDN"

            ch = clean[0]
            if ch in (13, 10):
                return "ENTER"
            if ch in (8, 127):
                return "BACKSPACE"
            if ch == 27:
                return "ESC"
            if 32 <= ch <= 126:
                return chr(ch)

    async def prompt_line(self, prompt_text: str, default: str = "", mask: bool = False, max_len: int = 32) -> Optional[str]:
        """Interactive single-line input prompt for SSH username/password when not pre-configured."""
        await self.send_ansi(prompt_text)
        buf: List[str] = []
        while True:
            k = await self.read_key(timeout=60)
            if k is None or k == "TIMEOUT" or k == "ESC":
                return None
            if k == "ENTER":
                await self.send_ansi("\r\n")
                res = "".join(buf).strip()
                return res if res else default
            if k == "BACKSPACE":
                if buf:
                    buf.pop()
                    await self.send_raw(b"\x08 \x08")
                continue
            if len(k) == 1 and len(buf) < max_len:
                buf.append(k)
                echo_ch = "*" if mask else k
                await self.send_raw(echo_ch.encode("cp437"))

    def _resolve_ansi_path(self) -> str:
        if os.path.isabs(self.cfg.ansi_file):
            return self.cfg.ansi_file
        base_dir = os.path.dirname(os.path.abspath(self.cfg_path))
        return os.path.join(base_dir, self.cfg.ansi_file)

    async def render_generated_frame(self) -> None:
        """Render a standalone 79-column CP437 box-drawing frame using explicit ESC[y;1H positioning."""
        border_c = dos_color_to_ansi(self.cfg.color_border, 0)
        head_c = dos_color_to_ansi(self.cfg.color_header, 1)
        sub_c = dos_color_to_ansi(11, 0)
        col_c = dos_color_to_ansi(14, 0)
        norm_c = dos_color_to_ansi(7, 0)
        dim_c = dos_color_to_ansi(8, 0)
        hi_c = dos_color_to_ansi(15, 0)

        title = f" {self.cfg.gateway_title} (SysOp: {self.cfg.sysop_name}) "
        title_padded = title[:77].center(77)

        rows = [
            f"{ESC}[0m{ESC}[2J{ESC}[1;1H{border_c}╔{'═' * 77}╗",
            f"{ESC}[2;1H{border_c}║{head_c}{title_padded}{border_c}║",
            f"{ESC}[3;1H{border_c}║{sub_c}  Use {hi_c}UP/DOWN{sub_c} Arrows + {hi_c}ENTER{sub_c} or press a {hi_c}Hotkey{sub_c} to connect (Telnet or SSH):   {border_c}║",
            f"{ESC}[4;1H{border_c}╠{'═' * 77}╣",
            f"{ESC}[5;1H{border_c}║{col_c}  KEY   BBS SYSTEM NAME          HOST / IP ADDRESS          PORT    MODE     {border_c}║",
            f"{ESC}[6;1H{border_c}╟{'─' * 77}╢",
        ]
        for r in range(7, 17):
            rows.append(f"{ESC}[{r};1H{border_c}║{norm_c}{' ' * 77}{border_c}║")

        rows.extend([
            f"{ESC}[17;1H{border_c}╟{'─' * 77}╢",
            f"{ESC}[18;1H{border_c}║{dim_c}  INFO: {norm_c}{' ' * 69}{border_c}║",
            f"{ESC}[19;1H{border_c}╠{'═' * 77}╣",
            f"{ESC}[20;1H{border_c}║{norm_c}  [{hi_c}UP/DN{norm_c}] Move   [{hi_c}ENTER{norm_c}] Connect   [{hi_c}1-9/A-Z{norm_c}] Hotkey   [{hi_c}P{norm_c}] Ping   [{hi_c}Q{norm_c}] Quit    {border_c}║",
            f"{ESC}[21;1H{border_c}╚{'═' * 77}╝{ESC}[0m",
        ])
        await self.send_ansi("".join(rows))

    async def render_lightbar_items(self) -> None:
        """Draw the visible rows of the lightbar selector and the active BBS description."""
        entries = self.cfg.bbs_list
        rows = self.cfg.menu_rows
        start_x = self.cfg.menu_start_x
        start_y = self.cfg.menu_start_y
        width = max(self.cfg.menu_width, 76)
        width = min(width, 79 - start_x)

        if self.selected_idx < self.scroll_offset:
            self.scroll_offset = self.selected_idx
        elif self.selected_idx >= self.scroll_offset + rows:
            self.scroll_offset = self.selected_idx - rows + 1

        normal_c = dos_color_to_ansi(self.cfg.color_item_fg, self.cfg.color_item_bg)
        hilite_c = dos_color_to_ansi(self.cfg.color_hilite_fg, self.cfg.color_hilite_bg)
        desc_c = dos_color_to_ansi(11, 0)
        reset = f"{ESC}[0m"

        out: List[str] = []
        for r in range(rows):
            idx = self.scroll_offset + r
            y = start_y + r
            out.append(f"{ESC}[{y};{start_x}H")
            if idx < len(entries):
                item = entries[idx]
                is_sel = idx == self.selected_idx
                color = hilite_c if is_sel else normal_c
                marker = "»" if is_sel else " "
                _, _, clean_host = item.parse_target()
                status_tag = self.ping_status.get(idx, item.scope[:8])
                row_text = (
                    f" {marker}[{item.hotkey}]   "
                    f"{item.name[:23]:<23}  "
                    f"{clean_host[:25]:<25}  "
                    f"{item.port:<6}  "
                    f"{status_tag:<8}"
                )
                row_text = row_text[:width].ljust(width)
                out.append(f"{color}{row_text}{reset}")
            else:
                out.append(f"{normal_c}{' ' * width}{reset}")

        desc_y = start_y + rows + 1
        out.append(f"{ESC}[{desc_y};10H")
        if entries and 0 <= self.selected_idx < len(entries):
            cur = entries[self.selected_idx]
            _, _, clean_host = cur.parse_target()
            proto = "SSH" if cur.is_ssh else "TELNET"
            desc = f"[{proto}] {cur.description} ({clean_host}:{cur.port})"
        else:
            desc = "No BBS entries configured in gateway.cfg."
        out.append(f"{desc_c}{desc[:68]:<68}{reset}")
        out.append(f"{ESC}[{desc_y + 2};78H")
        await self.send_ansi("".join(out))

    async def check_bbs_online(self) -> None:
        """Perform a quick non-blocking TCP reachability check across listed Telnet & SSH BBS nodes."""
        for idx, entry in enumerate(self.cfg.bbs_list):
            _, _, clean_host = entry.parse_target()
            t0 = time.monotonic()
            try:
                fut = asyncio.open_connection(clean_host, entry.port)
                r, w = await asyncio.wait_for(fut, timeout=2.0)
                ms = int((time.monotonic() - t0) * 1000)
                w.close()
                try:
                    await w.wait_closed()
                except Exception:
                    pass
                self.ping_status[idx] = f"{ms}ms"
            except Exception:
                self.ping_status[idx] = "OFFLINE"

    async def render_full_screen(self, force_lightbar: bool = False) -> None:
        """Render gateway.ans and/or the lightbar interface according to DISPLAY_MODE."""
        self.cfg = load_gateway_config(self.cfg_path)
        ansi_bytes = read_ansi_file_cp437(self._resolve_ansi_path())
        mode = "LIGHTBAR" if force_lightbar else self.cfg.display_mode

        if mode == "ANSI_HOTKEY" and ansi_bytes:
            await self.send_raw(b"\x1b[0m\x1b[2J\x1b[1;1H" + ansi_bytes)
            prompt = (
                f"{ESC}[22;1H{ESC}[0;1;36;40mSelect BBS Hotkey [{ESC}[1;37m1-{len(self.cfg.bbs_list)}{ESC}[1;36m], "
                f"[{ESC}[1;37mL{ESC}[1;36m]ightbar Menu, or [{ESC}[1;37mQ{ESC}[1;36m]uit: {ESC}[0m"
            )
            await self.send_ansi(prompt)
        elif mode == "BOTH" and ansi_bytes:
            await self.send_raw(b"\x1b[0m\x1b[2J\x1b[1;1H" + ansi_bytes)
            await self.render_lightbar_items()
        else:
            await self.render_generated_frame()
            await self.render_lightbar_items()

    async def connect_to_ssh_bbs(self, entry: BBSEntry) -> None:
        """
        Connect the caller to a Local or External SSH BBS node.
        Uses `asyncssh` if installed, or falls back automatically to a POSIX PTY
        wrapping the system `/usr/bin/ssh` binary so no external pip packages are required.
        """
        ssh_user, ssh_pass, clean_host = entry.parse_target()

        await self.send_ansi(
            f"{ESC}[0m{ESC}[2J{ESC}[1;1H"
            f"|11╔═════════════════════════════════════════════════════════════════════════════╗\r\n"
            f"|11║ |15SSH Target    : |14{entry.name:<59} |11║\r\n"
            f"|11║ |15SSH Endpoint  : |10{f'{clean_host}:{entry.port} ({entry.scope})':<59} |11║\r\n"
            f"|11╚═════════════════════════════════════════════════════════════════════════════╝|07\r\n"
        )

        # Prompt caller for SSH login if not embedded in gateway.cfg as user:pass@host
        if not ssh_user:
            ssh_user = await self.prompt_line(
                "|11Enter SSH Username |08(Press ENTER for 'bbs', or ESC to cancel)|11: |15",
                default="bbs",
            )
            if not ssh_user:
                return

        if ssh_pass is None and HAS_ASYNCSSH:
            ssh_pass = await self.prompt_line(
                f"|11Enter SSH Password for |14{ssh_user}@{clean_host}|11 |08(Enter if none/prompted by BBS)|11: |15",
                default="",
                mask=True,
            )
            if ssh_pass is None:
                return

        await self.send_ansi(
            f"\r\n|10Establishing SSH tunnel to {ssh_user}@{clean_host}:{entry.port}...|07\r\n"
        )
        logging.info(
            "Caller %s:%s opening SSH connection to %s (%s@%s:%d)",
            self.client_ip,
            self.client_port,
            entry.name,
            ssh_user,
            clean_host,
            entry.port,
        )

        # Route 1: Native asyncssh client if available
        if HAS_ASYNCSSH:
            try:
                conn = await asyncio.wait_for(
                    asyncssh.connect(
                        clean_host,
                        port=entry.port,
                        username=ssh_user,
                        password=ssh_pass if ssh_pass else None,
                        known_hosts=None,
                        preferred_auth=("password", "keyboard-interactive", "none"),
                    ),
                    timeout=self.cfg.connect_timeout,
                )
                async with conn:
                    chan, _ = await conn.create_session(
                        asyncssh.SSHClientProcess,
                        term_type="ansi-bbs",
                        term_size=(80, 25),
                        encoding=None,
                    )
                    await self._bridge_streams(
                        chan.stdout,
                        chan.stdin,
                        strip_iac=not self.is_inbound_ssh,
                    )
                return
            except Exception as exc:
                await self.send_ansi(
                    f"\r\n|12[!] SSH connection failed ({clean_host}:{entry.port}): {exc}\r\n"
                    f"|07Press any key to return to the Gateway menu..."
                )
                await self.read_key(timeout=30)
                return

        # Route 2: Zero-dependency POSIX PTY + system `ssh` binary fallback
        ssh_bin = shutil.which("ssh")
        if not ssh_bin:
            await self.send_ansi(
                "\r\n|12[!] Neither Python 'asyncssh' nor system 'ssh' client found on host.\r\n"
                "|07Press any key to return to the Gateway menu..."
            )
            await self.read_key(timeout=30)
            return

        master_fd, slave_fd = pty.openpty()
        # Set 80x25 terminal window size on the PTY
        winsize = struct.pack("HHHH", 25, 80, 0, 0)
        fcntl.ioctl(slave_fd, termios.TIOCSWINSZ, winsize)

        cmd = [
            ssh_bin,
            "-tt",
            "-p", str(entry.port),
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", f"ConnectTimeout={self.cfg.connect_timeout}",
            f"{ssh_user}@{clean_host}",
        ]

        env = os.environ.copy()
        env["TERM"] = "ansi"

        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdin=slave_fd,
            stdout=slave_fd,
            stderr=slave_fd,
            env=env,
            start_new_session=True,
        )
        os.close(slave_fd)

        loop = asyncio.get_running_loop()
        pty_out_queue: asyncio.Queue[bytes] = asyncio.Queue()

        def _on_pty_readable() -> None:
            try:
                data = os.read(master_fd, 4096)
                if data:
                    pty_out_queue.put_nowait(data)
                else:
                    loop.remove_reader(master_fd)
                    pty_out_queue.put_nowait(b"")
            except OSError:
                loop.remove_reader(master_fd)
                pty_out_queue.put_nowait(b"")

        loop.add_reader(master_fd, _on_pty_readable)
        pw_sent = False

        async def _pty_to_caller() -> None:
            nonlocal pw_sent
            while True:
                chunk = await pty_out_queue.get()
                if not chunk:
                    break
                # If password was pre-configured in gateway.cfg, auto-answer SSH's password prompt
                if ssh_pass and not pw_sent and b"password:" in chunk.lower():
                    pw_sent = True
                    os.write(master_fd, (ssh_pass + "\n").encode("utf-8"))
                    continue
                await self.send_raw(chunk)

        async def _caller_to_pty() -> None:
            while True:
                data = await self.reader.read(4096)
                if not data:
                    break
                clean = data if self.is_inbound_ssh else self._strip_telnet_iac(data)
                if clean:
                    os.write(master_fd, clean)

        t1 = asyncio.create_task(_pty_to_caller())
        t2 = asyncio.create_task(_caller_to_pty())
        done, pending = await asyncio.wait([t1, t2], return_when=asyncio.FIRST_COMPLETED)
        for t in pending:
            t.cancel()

        try:
            loop.remove_reader(master_fd)
        except Exception:
            pass
        try:
            os.close(master_fd)
        except OSError:
            pass
        if proc.returncode is None:
            try:
                proc.terminate()
                await asyncio.wait_for(proc.wait(), timeout=2.0)
            except Exception:
                pass

    async def _bridge_streams(self, remote_reader, remote_writer, strip_iac: bool = False) -> None:
        """Bidirectionally pipe bytes between caller and downstream BBS."""
        async def _c2s() -> None:
            try:
                while True:
                    data = await self.reader.read(4096)
                    if not data:
                        break
                    out = self._strip_telnet_iac(data) if strip_iac else data
                    if out:
                        remote_writer.write(out)
                        await remote_writer.drain()
            except Exception:
                pass

        async def _s2c() -> None:
            try:
                while True:
                    data = await remote_reader.read(4096)
                    if not data:
                        break
                    self.writer.write(data)
                    await self.writer.drain()
            except Exception:
                pass

        t1 = asyncio.create_task(_c2s())
        t2 = asyncio.create_task(_s2c())
        done, pending = await asyncio.wait([t1, t2], return_when=asyncio.FIRST_COMPLETED)
        for t in pending:
            t.cancel()

    async def connect_to_bbs(self, entry: BBSEntry) -> None:
        """Route caller to either an SSH BBS or a Telnet BBS based on the entry's mode."""
        if entry.is_ssh:
            await self.connect_to_ssh_bbs(entry)
            return

        _, _, clean_host = entry.parse_target()
        await self.send_ansi(
            f"{ESC}[0m{ESC}[2J{ESC}[1;1H"
            f"|11╔═════════════════════════════════════════════════════════════════════════════╗\r\n"
            f"|11║ |15Connecting to : |14{entry.name:<59} |11║\r\n"
            f"|11║ |15Address       : |10{f'{clean_host}:{entry.port} ({entry.scope})':<59} |11║\r\n"
            f"|11╚═════════════════════════════════════════════════════════════════════════════╝|07\r\n"
        )
        logging.info(
            "Caller %s:%s connecting via Telnet to %s (%s:%d [%s])",
            self.client_ip,
            self.client_port,
            entry.name,
            clean_host,
            entry.port,
            entry.scope,
        )

        try:
            remote_reader, remote_writer = await asyncio.wait_for(
                asyncio.open_connection(clean_host, entry.port),
                timeout=self.cfg.connect_timeout,
            )
        except Exception as exc:
            await self.send_ansi(
                f"\r\n|12[!] Unable to connect to {entry.name} ({clean_host}:{entry.port}): {exc}\r\n"
                f"|07Press any key to return to the Gateway menu..."
            )
            await self.read_key(timeout=30)
            return

        await self.send_ansi(f"|10Connected! Handing off session to {entry.name}...|07\r\n\r\n")
        await self._bridge_streams(remote_reader, remote_writer, strip_iac=False)

        try:
            remote_writer.close()
            await remote_writer.wait_closed()
        except Exception:
            pass

        logging.info(
            "Caller %s:%s disconnected from %s",
            self.client_ip,
            self.client_port,
            entry.name,
        )

    async def run(self) -> None:
        """Main session loop for an incoming Telnet or SSH caller."""
        proto_label = "SSH" if self.is_inbound_ssh else "Telnet"
        logging.info("Incoming %s connection from %s:%s", proto_label, self.client_ip, self.client_port)
        try:
            await self.negotiate_telnet_char_mode()
            force_lightbar = False
            await self.render_full_screen(force_lightbar=force_lightbar)

            while True:
                key = await self.read_key()
                if key is None or key == "TIMEOUT":
                    if key == "TIMEOUT":
                        await self.send_ansi(
                            "\r\n|14Idle timeout reached. Disconnecting...|07\r\n"
                        )
                    break

                entries = self.cfg.bbs_list
                upper_key = key.upper()

                if upper_key in ("Q", "ESC"):
                    await self.send_ansi(
                        f"|CL|11Thank you for visiting {self.cfg.gateway_title}! Disconnecting...|07\r\n"
                    )
                    break

                if upper_key == "L" and self.cfg.display_mode == "ANSI_HOTKEY":
                    force_lightbar = not force_lightbar
                    await self.render_full_screen(force_lightbar=force_lightbar)
                    continue

                if upper_key == "P":
                    await self.CheckStatusAndRedraw(force_lightbar)
                    continue

                if key in ("UP", "LEFT") and entries:
                    self.selected_idx = (self.selected_idx - 1) % len(entries)
                    await self.render_lightbar_items()
                    continue

                if key in ("DOWN", "RIGHT") and entries:
                    self.selected_idx = (self.selected_idx + 1) % len(entries)
                    await self.render_lightbar_items()
                    continue

                if key == "HOME" and entries:
                    self.selected_idx = 0
                    await self.render_lightbar_items()
                    continue

                if key == "END" and entries:
                    self.selected_idx = len(entries) - 1
                    await self.render_lightbar_items()
                    continue

                if key == "PGUP" and entries:
                    self.selected_idx = max(0, self.selected_idx - self.cfg.menu_rows)
                    await self.render_lightbar_items()
                    continue

                if key == "PGDN" and entries:
                    self.selected_idx = min(len(entries) - 1, self.selected_idx + self.cfg.menu_rows)
                    await self.render_lightbar_items()
                    continue

                target_entry: Optional[BBSEntry] = None
                if key == "ENTER" and entries:
                    target_entry = entries[self.selected_idx]
                else:
                    for idx, item in enumerate(entries):
                        if item.hotkey.upper() == upper_key:
                            self.selected_idx = idx
                            target_entry = item
                            break

                if target_entry is not None:
                    await self.connect_to_bbs(target_entry)
                    if not self.cfg.return_after_disconnect:
                        break
                    await self.negotiate_telnet_char_mode()
                    await self.render_full_screen(force_lightbar=force_lightbar)

        except Exception as exc:
            logging.error("Session error for %s: %s", self.client_ip, exc)
        finally:
            try:
                await self.send_raw(f"{ESC}[0m".encode("ascii"))
                self.writer.close()
                await self.writer.wait_closed()
            except Exception:
                pass
            logging.info("Closed %s connection from %s:%s", proto_label, self.client_ip, self.client_port)

    async def CheckStatusAndRedraw(self, force_lightbar: bool) -> None:
        """Ping all configured BBS targets and update lightbar status column."""
        desc_y = self.cfg.menu_start_y + self.cfg.menu_rows + 1
        await self.send_ansi(
            f"{ESC}[{desc_y};10H|14Checking live status of all listed BBS nodes, please wait...        |07"
        )
        await self.check_bbs_online()
        await self.render_full_screen(force_lightbar=force_lightbar)


async def start_inbound_ssh_server(cfg: GatewayConfig, cfg_path: str, bind_host: str, ssh_port: int):
    """
    Start an optional inbound SSH listener using `asyncssh` so callers can also
    SSH directly into the gateway on `SSH_LISTEN_PORT` (default 2222).
    """
    if not HAS_ASYNCSSH:
        logging.warning(
            "SSH_ENABLED is TRUE in gateway.cfg, but 'asyncssh' is not installed. "
            "Install with 'pip install asyncssh' to enable the inbound SSH server. "
            "(Outbound SSH to BBS targets still works via the system 'ssh' client!)"
        )
        return None

    key_path = cfg.ssh_host_key
    if not os.path.isabs(key_path):
        key_path = os.path.join(os.path.dirname(os.path.abspath(cfg_path)), key_path)
    if not os.path.exists(key_path):
        logging.info("Generating new SSH host key at %s", key_path)
        priv_key = asyncssh.generate_private_key("ssh-ed25519")
        priv_key.write_private_key(key_path)

    class GatewaySSHServer(asyncssh.SSHServer):
        def begin_auth(self, username: str) -> bool:
            # Allow passwordless entry into the public BBS gateway menu
            return False

    async def _ssh_process_handler(process: "asyncssh.SSHServerProcess") -> None:
        session = TelnetSession(
            process.stdin,
            process.stdout,
            cfg_path,
            is_inbound_ssh=True,
        )
        await session.run()

    ssh_server = await asyncssh.create_server(
        GatewaySSHServer,
        bind_host,
        ssh_port,
        server_host_keys=[key_path],
        process_factory=_ssh_process_handler,
        encoding=None,
    )
    logging.info("Inbound SSH Gateway server listening on %s:%d", bind_host, ssh_port)
    return ssh_server


async def run_gateway_server(
    cfg_path: str,
    host_override: Optional[str],
    port_override: Optional[int],
    ssh_port_override: Optional[int] = None,
) -> None:
    """Start the asyncio TCP Telnet listener (and optional Inbound SSH listener)."""
    cfg = load_gateway_config(cfg_path)
    bind_host = host_override or cfg.listen_host
    bind_port = port_override or cfg.listen_port

    async def _client_connected(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        session = TelnetSession(reader, writer, cfg_path, is_inbound_ssh=False)
        await session.run()

    try:
        server = await asyncio.start_server(_client_connected, bind_host, bind_port)
    except PermissionError:
        logging.error(
            "Permission denied binding to port %d. On Linux, run with sudo or grant "
            "capability: sudo setcap 'cap_net_bind_service=+ep' $(readlink -f $(which python3)) "
            "or test on an unprivileged port with: python3 bbs_gateway.py --port 2323",
            bind_port,
        )
        sys.exit(1)

    if cfg.ssh_enabled or ssh_port_override is not None:
        await start_inbound_ssh_server(
            cfg,
            cfg_path,
            bind_host,
            ssh_port_override or cfg.ssh_listen_port,
        )

    addrs = ", ".join(str(sock.getsockname()) for sock in (server.sockets or []))
    logging.info("%s listening on Telnet %s (config: %s)", cfg.gateway_title, addrs, cfg_path)
    async with server:
        await server.serve_forever()


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Telnet & SSH BBS Gateway Server with CP437 ANSI display and Lightbar menu."
    )
    parser.add_argument(
        "-c", "--config",
        default="gateway.cfg",
        help="Path to human-readable gateway.cfg (default: gateway.cfg)",
    )
    parser.add_argument(
        "--host",
        default=None,
        help="Override listen address from gateway.cfg (e.g., 0.0.0.0 or 127.0.0.1)",
    )
    parser.add_argument(
        "-p", "--port",
        type=int,
        default=None,
        help="Override Telnet listen port from gateway.cfg (default in config is 23)",
    )
    parser.add_argument(
        "--ssh-port",
        type=int,
        default=None,
        help="Enable and override Inbound SSH listen port (e.g. 2222, requires asyncssh)",
    )
    parser.add_argument(
        "--check-config",
        action="store_true",
        help="Validate gateway.cfg and print parsed settings and BBS listings, then exit.",
    )
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
    )

    if args.check_config:
        cfg = load_gateway_config(args.config)
        print(f"Gateway Title : {cfg.gateway_title}")
        print(f"SysOp Name    : {cfg.sysop_name}")
        print(f"Telnet Socket : {cfg.listen_host}:{cfg.listen_port}")
        print(f"Inbound SSH   : {'ENABLED' if cfg.ssh_enabled else 'DISABLED'} (Port {cfg.ssh_listen_port})")
        print(f"ANSI File     : {cfg.ansi_file} (Mode: {cfg.display_mode})")
        print(f"BBS Listings  : {len(cfg.bbs_list)} configured")
        for idx, bbs in enumerate(cfg.bbs_list, 1):
            proto = "SSH" if bbs.is_ssh else "TELNET"
            print(f"  {idx}. [{bbs.hotkey}] {bbs.name:<22} -> {bbs.host}:{bbs.port} [{bbs.scope} / {proto}] - {bbs.description}")
        return

    try:
        asyncio.run(run_gateway_server(args.config, args.host, args.port, args.ssh_port))
    except KeyboardInterrupt:
        logging.info("Gateway server stopped by operator.")


if __name__ == "__main__":
    main()