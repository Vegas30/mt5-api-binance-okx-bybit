from __future__ import annotations

import json
from decimal import Decimal
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

from .client import BybitClient, BybitError
from .models import Signal


class BridgeServer(ThreadingHTTPServer):
    def __init__(self, server_address: tuple[str, int], client: BybitClient, live_trading: bool) -> None:
        super().__init__(server_address, BridgeHandler)
        self.client = client
        self.live_trading = live_trading


class BridgeHandler(BaseHTTPRequestHandler):
    server: BridgeServer

    def do_GET(self) -> None:
        if self.path == "/health":
            self._send_json({"ok": True, "liveTrading": self.server.live_trading})
            return
        self._send_json({"error": "not found"}, status=404)

    def do_POST(self) -> None:
        if self.path != "/signal":
            self._send_json({"error": "not found"}, status=404)
            return

        try:
            payload = self._read_json()
            signal = Signal(
                symbol=str(payload["symbol"]),
                side=str(payload["side"]),
                qty=Decimal(str(payload["qty"])),
                category=str(payload.get("category", "linear")),
                order_type=str(payload.get("orderType", "Market")),
                price=Decimal(str(payload["price"])) if payload.get("price") not in (None, "") else None,
                reduce_only=bool(payload.get("reduceOnly", False)),
                time_in_force=str(payload.get("timeInForce", "GTC")),
            )

            if not self.server.live_trading:
                self._send_json({"ok": True, "mode": "dry-run", "signal": serialize_signal(signal)})
                return

            result = self.server.client.place_order(signal)
            self._send_json({"ok": True, "mode": "live", "result": result.get("result", {})})
        except (KeyError, ValueError, BybitError, json.JSONDecodeError) as exc:
            self._send_json({"ok": False, "error": str(exc)}, status=400)

    def log_message(self, format: str, *args: Any) -> None:
        return

    def _read_json(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length).decode("utf-8")
        return json.loads(raw)

    def _send_json(self, payload: dict[str, Any], status: int = 200) -> None:
        data = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def serialize_signal(signal: Signal) -> dict[str, Any]:
    return {
        "symbol": signal.symbol.upper(),
        "side": signal.side,
        "qty": str(signal.qty),
        "category": signal.category,
        "orderType": signal.order_type,
        "price": str(signal.price) if signal.price is not None else None,
        "reduceOnly": signal.reduce_only,
        "timeInForce": signal.time_in_force,
    }


def run_bridge(host: str, port: int, client: BybitClient, live_trading: bool) -> None:
    server = BridgeServer((host, port), client=client, live_trading=live_trading)
    print(f"Bybit MT5 bridge listening on http://{host}:{port}")
    print(f"Trading mode: {'live' if live_trading else 'dry-run'}")
    server.serve_forever()

