from __future__ import annotations

import hashlib
import hmac
import json
import time
from datetime import datetime, timezone
from decimal import Decimal
from typing import Any
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from .models import Kline, Signal


class BybitError(RuntimeError):
    pass


class BybitClient:
    MAINNET_URL = "https://api.bybit.com"
    TESTNET_URL = "https://api-testnet.bybit.com"

    def __init__(
        self,
        api_key: str | None = None,
        api_secret: str | None = None,
        testnet: bool = False,
        recv_window: int = 5000,
        timeout: int = 20,
    ) -> None:
        self.api_key = api_key
        self.api_secret = api_secret
        self.base_url = self.TESTNET_URL if testnet else self.MAINNET_URL
        self.recv_window = recv_window
        self.timeout = timeout

    def get_klines(
        self,
        symbol: str,
        interval: str,
        category: str = "linear",
        start_ms: int | None = None,
        end_ms: int | None = None,
        limit: int = 1000,
    ) -> list[Kline]:
        params: dict[str, Any] = {
            "category": category,
            "symbol": normalize_bybit_symbol(symbol),
            "interval": interval,
            "limit": min(max(limit, 1), 1000),
        }
        if start_ms is not None:
            params["start"] = start_ms
        if end_ms is not None:
            params["end"] = end_ms

        payload = self._public_get("/v5/market/kline", params)
        rows = payload["result"].get("list", [])
        klines = [
            Kline(
                start_ms=int(row[0]),
                open=Decimal(row[1]),
                high=Decimal(row[2]),
                low=Decimal(row[3]),
                close=Decimal(row[4]),
                volume=Decimal(row[5]),
                turnover=Decimal(row[6]),
            )
            for row in rows
        ]
        return sorted(klines, key=lambda item: item.start_ms)

    def get_instruments_info(
        self,
        category: str,
        symbol: str | None = None,
        base_coin: str | None = None,
        status: str | None = None,
        limit: int = 500,
        cursor: str | None = None,
    ) -> dict[str, Any]:
        params: dict[str, Any] = {
            "category": category,
            "limit": min(max(limit, 1), 1000),
        }
        if symbol is not None:
            params["symbol"] = symbol.upper()
        if base_coin is not None:
            params["baseCoin"] = base_coin.upper()
        if status is not None:
            params["status"] = status
        if cursor is not None:
            params["cursor"] = cursor
        return self._public_get("/v5/market/instruments-info", params)

    def iter_klines(
        self,
        symbol: str,
        interval: str,
        category: str,
        start_ms: int,
        end_ms: int,
    ) -> list[Kline]:
        # Bybit returns at most 1000 candles and, for a range larger than that,
        # the page is the newest part of the requested range.  Paging forward
        # therefore silently drops the oldest candles in the first request.
        # Walk backward from end_ms so every page has an unambiguous cursor.
        return self.iter_klines_backward(
            symbol=symbol,
            interval=interval,
            category=category,
            start_ms=start_ms,
            end_ms=end_ms,
        )

    def iter_klines_backward(
        self,
        symbol: str,
        interval: str,
        category: str,
        start_ms: int,
        end_ms: int,
    ) -> list[Kline]:
        cursor_end = end_ms
        out: list[Kline] = []
        seen: set[int] = set()

        while cursor_end > start_ms:
            page = self.get_klines(
                symbol=symbol,
                interval=interval,
                category=category,
                start_ms=start_ms,
                end_ms=cursor_end - 1,
                limit=1000,
            )
            if not page:
                break

            for candle in page:
                if start_ms <= candle.start_ms < end_ms and candle.start_ms not in seen:
                    seen.add(candle.start_ms)
                    out.append(candle)

            next_cursor_end = min(candle.start_ms for candle in page)
            if next_cursor_end >= cursor_end:
                break
            cursor_end = max(start_ms, next_cursor_end)
            time.sleep(0.05)

        return sorted(out, key=lambda item: item.start_ms)

    def place_order(self, signal: Signal) -> dict[str, Any]:
        body: dict[str, Any] = {
            "category": signal.category,
            "symbol": normalize_bybit_symbol(signal.symbol),
            "side": normalize_side(signal.side),
            "orderType": signal.order_type,
            "qty": str(signal.qty),
            "timeInForce": signal.time_in_force,
        }
        if signal.category.lower() != "spot" or signal.reduce_only:
            body["reduceOnly"] = signal.reduce_only
        if signal.price is not None:
            body["price"] = str(signal.price)

        return self._private_post("/v5/order/create", body)

    def _public_get(self, path: str, params: dict[str, Any]) -> dict[str, Any]:
        url = f"{self.base_url}{path}?{urlencode(params)}"
        return self._request(Request(url, method="GET"))

    def _private_post(self, path: str, body: dict[str, Any]) -> dict[str, Any]:
        if not self.api_key or not self.api_secret:
            raise BybitError("BYBIT_API_KEY and BYBIT_API_SECRET are required for live trading")

        payload = json.dumps(body, separators=(",", ":"))
        timestamp = str(int(time.time() * 1000))
        sign_payload = f"{timestamp}{self.api_key}{self.recv_window}{payload}"
        signature = hmac.new(
            self.api_secret.encode("utf-8"),
            sign_payload.encode("utf-8"),
            hashlib.sha256,
        ).hexdigest()

        headers = {
            "Content-Type": "application/json",
            "X-BAPI-API-KEY": self.api_key,
            "X-BAPI-TIMESTAMP": timestamp,
            "X-BAPI-RECV-WINDOW": str(self.recv_window),
            "X-BAPI-SIGN": signature,
        }
        return self._request(
            Request(
                f"{self.base_url}{path}",
                data=payload.encode("utf-8"),
                headers=headers,
                method="POST",
            )
        )

    def _request(self, request: Request) -> dict[str, Any]:
        with urlopen(request, timeout=self.timeout) as response:
            data = json.loads(response.read().decode("utf-8"))
        if data.get("retCode") != 0:
            raise BybitError(f"Bybit error {data.get('retCode')}: {data.get('retMsg')}")
        return data


def parse_datetime(value: str) -> int:
    if value.isdigit():
        return int(value)
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return int(parsed.timestamp() * 1000)


def interval_to_milliseconds(interval: str) -> int:
    mapping = {
        "1": 60_000,
        "3": 180_000,
        "5": 300_000,
        "15": 900_000,
        "30": 1_800_000,
        "60": 3_600_000,
        "120": 7_200_000,
        "240": 14_400_000,
        "360": 21_600_000,
        "720": 43_200_000,
        "D": 86_400_000,
        "W": 604_800_000,
    }
    if interval not in mapping:
        raise ValueError(f"Unsupported interval for pagination: {interval}")
    return mapping[interval]


def normalize_side(value: str) -> str:
    side = value.strip().lower()
    if side in {"buy", "long"}:
        return "Buy"
    if side in {"sell", "short"}:
        return "Sell"
    raise ValueError("side must be buy/sell/long/short")


def normalize_bybit_symbol(value: str) -> str:
    symbol = value.strip().upper()
    if symbol.endswith(".P"):
        return symbol[:-2]
    return symbol
