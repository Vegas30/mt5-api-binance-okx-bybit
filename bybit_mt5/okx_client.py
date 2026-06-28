from __future__ import annotations

import json
import time
from decimal import Decimal
from typing import Any
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from .models import Kline


class OkxError(RuntimeError):
    pass


class OkxClient:
    MAINNET_URL = "https://www.okx.com"

    def __init__(self, timeout: int = 20) -> None:
        self.base_url = self.MAINNET_URL
        self.timeout = timeout

    def get_history_candles(
        self,
        inst_id: str,
        bar: str,
        after_ms: int | None = None,
        before_ms: int | None = None,
        limit: int = 100,
    ) -> list[Kline]:
        params: dict[str, Any] = {
            "instId": inst_id.upper(),
            "bar": bar,
            "limit": min(max(limit, 1), 100),
        }
        if after_ms is not None:
            params["after"] = after_ms
        if before_ms is not None:
            params["before"] = before_ms

        payload = self._public_get("/api/v5/market/history-candles", params)
        klines = [
            Kline(
                start_ms=int(row[0]),
                open=Decimal(row[1]),
                high=Decimal(row[2]),
                low=Decimal(row[3]),
                close=Decimal(row[4]),
                volume=Decimal(row[5]),
                turnover=Decimal(row[7]) if len(row) > 7 else Decimal("0"),
            )
            for row in payload.get("data", [])
        ]
        return sorted(klines, key=lambda item: item.start_ms)

    def iter_klines(
        self,
        inst_id: str,
        bar: str,
        start_ms: int,
        end_ms: int,
    ) -> list[Kline]:
        cursor_after = end_ms
        out: list[Kline] = []
        seen: set[int] = set()

        while cursor_after > start_ms:
            page = self.get_history_candles(
                inst_id=inst_id,
                bar=bar,
                after_ms=cursor_after,
                limit=100,
            )
            if not page:
                break

            for candle in page:
                if start_ms <= candle.start_ms < end_ms and candle.start_ms not in seen:
                    seen.add(candle.start_ms)
                    out.append(candle)

            oldest = page[0].start_ms
            if oldest <= start_ms or oldest >= cursor_after:
                break
            cursor_after = oldest
            time.sleep(0.05)

        return sorted(out, key=lambda item: item.start_ms)

    def _public_get(self, path: str, params: dict[str, Any]) -> dict[str, Any]:
        url = f"{self.base_url}{path}?{urlencode(params)}"
        headers = {
            "Accept": "application/json",
            "User-Agent": "mt5-okx-history-loader/0.1",
        }
        return self._request(Request(url, headers=headers, method="GET"))

    def _request(self, request: Request) -> dict[str, Any]:
        with urlopen(request, timeout=self.timeout) as response:
            data = json.loads(response.read().decode("utf-8"))
        if data.get("code") != "0":
            raise OkxError(f"OKX error {data.get('code')}: {data.get('msg')}")
        return data
