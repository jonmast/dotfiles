#!/usr/bin/env python3
"""Bridge between The Shell's Google TV widget and the Android TV Remote protocol.

Long-running, driven over stdin, reporting over stdout. Quickshell spawns one
of these (nix/home/quickshell/Bar/GoogleTv.qml) and keeps it alive for the
session; the widget never touches a socket, a certificate, or a protobuf.

Why a persistent process rather than one spawn per key press, the shape the
DWT and brightness widgets use: the remote protocol is a TLS session that the
TV has to accept, which takes a noticeable fraction of a second to set up,
and the TV pushes power/app state over that same session. A press-per-spawn
design would pay the handshake on every click and would have nothing to show
in the bar between clicks.

Wire format, both directions line-oriented:

  stdin   key <CODE>       send a key (RemoteKeyCode name, e.g. HOME, DPAD_UP)
          pair             start pairing; the TV shows a six-digit code
          pin <CODE>       finish pairing with that code
          host <ADDR>      set the TV address (persisted), then reconnect
          retry            reconnect now rather than waiting for the backoff

  stdout  one JSON object per line, the full state, on every change:
          {"status": ..., "host": ..., "powered": true|false|null,
           "app": "<package>"|null, "volume": {...}|null, "error": "..."}

`status` is one of:
  unconfigured   no host known; send `host`
  connecting     handshake in progress
  unreachable    TCP/TLS failed; retrying with backoff (see `error`)
  unpaired       the TV rejected our certificate; send `pair`
  pairing        the TV is showing a code; send `pin`
  connected      live; keys will be delivered
  reconnecting   was connected, lost the link; the library is retrying

Config is ~/.config/googletv/config.json ({"host": "..."}); the client
certificate the TV pairs against lives in ~/.local/state/googletv/. Both paths
honour XDG overrides. Delete the state dir to force a fresh pairing.

Debugging story: run this in a terminal and type the commands above.
"""

import asyncio
import json
import logging
import os
import sys
from pathlib import Path

from androidtvremote2 import (
    AndroidTVRemote,
    CannotConnect,
    ConnectionClosed,
    InvalidAuth,
)

# Shown on the TV's pairing screen as the name of the thing asking.
CLIENT_NAME = os.environ.get("GOOGLETV_CLIENT_NAME", "The Shell")

CONFIG_FILE = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "googletv" / "config.json"
STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state")) / "googletv"
CERT_FILE = STATE_DIR / "cert.pem"
KEY_FILE = STATE_DIR / "key.pem"

RETRY_MIN = 2
RETRY_MAX = 60
# The library puts no bound on the TCP connect; a wrong or dark address would
# otherwise sit in "connecting" for the kernel's full SYN retry (minutes).
CONNECT_TIMEOUT = 10


class Bridge:
    def __init__(self) -> None:
        self.host: str | None = os.environ.get("GOOGLETV_HOST") or None
        self.status = "unconfigured"
        self.powered: bool | None = None
        self.app: str | None = None
        self.volume: dict | None = None
        self.error = ""
        self.remote: AndroidTVRemote | None = None
        self.connect_task: asyncio.Task | None = None
        self.retry_wakeup = asyncio.Event()

    # ---- state --------------------------------------------------------

    def emit(self) -> None:
        print(
            json.dumps(
                {
                    "status": self.status,
                    "host": self.host or "",
                    "powered": self.powered,
                    "app": self.app,
                    "volume": self.volume,
                    "error": self.error,
                }
            ),
            flush=True,
        )

    def set(self, **fields) -> None:
        for name, value in fields.items():
            setattr(self, name, value)
        self.emit()

    def load_config(self) -> None:
        if self.host:
            return
        try:
            self.host = json.loads(CONFIG_FILE.read_text()).get("host") or None
        except (OSError, ValueError):
            self.host = None

    def save_config(self) -> None:
        CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
        CONFIG_FILE.write_text(json.dumps({"host": self.host}, indent=2) + "\n")

    # ---- connection ---------------------------------------------------

    def build_remote(self) -> AndroidTVRemote:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        remote = AndroidTVRemote(CLIENT_NAME, str(CERT_FILE), str(KEY_FILE), self.host)
        remote.add_is_on_updated_callback(lambda on: self.set(powered=on))
        remote.add_current_app_updated_callback(lambda app: self.set(app=app))
        remote.add_volume_info_updated_callback(lambda v: self.set(volume=dict(v)))
        remote.add_is_available_updated_callback(self.on_available)
        return remote

    def on_available(self, available: bool) -> None:
        if available:
            self.set(status="connected", error="", powered=self.remote.is_on, app=self.remote.current_app)
        else:
            self.set(status="reconnecting", powered=None, app=None)

    def on_invalid_auth(self) -> None:
        # keep_reconnecting gives up on InvalidAuth; from here only `pair`
        # can get us back.
        self.set(status="unpaired", powered=None, app=None, error="TV no longer trusts this client")

    def start_connect(self) -> None:
        self.stop_connect()
        if not self.host:
            self.set(status="unconfigured", powered=None, app=None, error="")
            return
        self.remote = self.build_remote()
        self.set(status="connecting", powered=None, app=None, error="")
        self.connect_task = asyncio.create_task(self.connect_loop())

    def stop_connect(self) -> None:
        if self.connect_task:
            self.connect_task.cancel()
            self.connect_task = None
        if self.remote:
            self.remote.disconnect()

    async def connect_loop(self) -> None:
        # Only the FIRST connection is ours. Once it succeeds the library's
        # keep_reconnecting owns retries; it just cannot help before that,
        # because there is nothing to reconnect.
        await self.remote.async_generate_cert_if_missing()
        delay = RETRY_MIN
        while True:
            self.set(status="connecting", error="")
            try:
                await asyncio.wait_for(self.remote.async_connect(), CONNECT_TIMEOUT)
            except InvalidAuth:
                self.set(status="unpaired", powered=None, app=None, error="")
                return
            except (CannotConnect, ConnectionClosed, TimeoutError) as exc:
                self.set(status="unreachable", powered=None, app=None, error=str(exc) or type(exc).__name__)
                self.retry_wakeup.clear()
                try:
                    await asyncio.wait_for(self.retry_wakeup.wait(), delay)
                except TimeoutError:
                    pass
                delay = min(delay * 2, RETRY_MAX)
                continue
            self.remote.keep_reconnecting(self.on_invalid_auth)
            self.set(status="connected", error="", powered=self.remote.is_on, app=self.remote.current_app)
            return

    # ---- commands -----------------------------------------------------

    async def cmd_host(self, addr: str) -> None:
        if not addr:
            self.set(error="host needs an address")
            return
        self.host = addr
        self.save_config()
        self.start_connect()

    async def cmd_retry(self) -> None:
        if self.status in ("unreachable",):
            self.retry_wakeup.set()
        elif self.status in ("unpaired", "unconfigured"):
            self.start_connect()

    async def cmd_pair(self) -> None:
        if not self.host:
            self.set(error="set a host first")
            return
        # Pairing needs the API connection down, and async_start_pairing
        # disconnects on its own — but our connect loop would just race it
        # back up, so it goes first.
        self.stop_connect()
        self.remote = self.build_remote()
        await self.remote.async_generate_cert_if_missing()
        try:
            await asyncio.wait_for(self.remote.async_start_pairing(), CONNECT_TIMEOUT)
        except (CannotConnect, ConnectionClosed, TimeoutError) as exc:
            self.set(status="unreachable", error=str(exc) or type(exc).__name__)
            return
        self.set(status="pairing", error="")

    async def cmd_pin(self, code: str) -> None:
        if self.status != "pairing" or not self.remote:
            self.set(error="not pairing; send `pair` first")
            return
        try:
            await self.remote.async_finish_pairing(code)
        except InvalidAuth:
            # The TV drops the pairing session on a wrong code; there is no
            # second try without a fresh `pair`.
            self.set(status="unpaired", error="wrong code — pair again")
            return
        except ConnectionClosed:
            self.set(status="unpaired", error="pairing cancelled on the TV")
            return
        self.start_connect()

    async def cmd_key(self, code: str) -> None:
        if not self.remote or self.status != "connected":
            self.set(error="not connected")
            return
        try:
            self.remote.send_key_command(code)
        except ValueError:
            self.set(error=f"unknown key {code!r}")
        except ConnectionClosed:
            self.set(error="connection dropped")
        else:
            if self.error:
                self.set(error="")

    async def handle(self, line: str) -> None:
        verb, _, arg = line.strip().partition(" ")
        arg = arg.strip()
        match verb:
            case "key":
                await self.cmd_key(arg)
            case "pair":
                await self.cmd_pair()
            case "pin":
                await self.cmd_pin(arg)
            case "host":
                await self.cmd_host(arg)
            case "retry":
                await self.cmd_retry()
            case "":
                pass
            case _:
                self.set(error=f"unknown command {verb!r}")

    # ---- main ---------------------------------------------------------

    async def run(self) -> None:
        self.load_config()
        self.emit()
        self.start_connect()

        reader = asyncio.StreamReader()
        await asyncio.get_running_loop().connect_read_pipe(lambda: asyncio.StreamReaderProtocol(reader), sys.stdin)
        while True:
            line = await reader.readline()
            if not line:
                # Quickshell closed our stdin: it is going away, so are we.
                break
            try:
                await self.handle(line.decode(errors="replace"))
            except Exception as exc:  # noqa: BLE001 — one bad command must not kill the bridge
                logging.exception("command failed")
                self.set(error=f"{type(exc).__name__}: {exc}")
        self.stop_connect()


def main() -> None:
    logging.basicConfig(level=os.environ.get("GOOGLETV_LOGLEVEL", "WARNING"), stream=sys.stderr)
    try:
        asyncio.run(Bridge().run())
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
