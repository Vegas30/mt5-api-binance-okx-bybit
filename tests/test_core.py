from __future__ import annotations

import unittest
from decimal import Decimal
from pathlib import Path

from bybit_mt5.client import (
    BybitClient,
    interval_to_milliseconds,
    normalize_bybit_symbol,
    normalize_side,
    parse_datetime,
)
from bybit_mt5.export import write_mt5_csv
from bybit_mt5.models import Kline, Signal
from bybit_mt5.okx_client import OkxClient


class CoreTests(unittest.TestCase):
    def test_parse_datetime_iso_utc(self) -> None:
        self.assertEqual(parse_datetime("2024-01-01T00:00:00Z"), 1704067200000)

    def test_interval_to_milliseconds(self) -> None:
        self.assertEqual(interval_to_milliseconds("1"), 60_000)
        self.assertEqual(interval_to_milliseconds("D"), 86_400_000)

    def test_normalize_side(self) -> None:
        self.assertEqual(normalize_side("long"), "Buy")
        self.assertEqual(normalize_side("SELL"), "Sell")

    def test_normalize_bybit_symbol(self) -> None:
        self.assertEqual(normalize_bybit_symbol("XAGUSDT.P"), "XAGUSDT")
        self.assertEqual(normalize_bybit_symbol("xagusdt"), "XAGUSDT")

    def test_write_mt5_csv(self) -> None:
        output_dir = Path.cwd() / "test_output"
        output_dir.mkdir(exist_ok=True)
        output = output_dir / "rates.csv"
        write_mt5_csv(
            output,
            [
                Kline(
                    start_ms=1704067200000,
                    open=Decimal("1"),
                    high=Decimal("2"),
                    low=Decimal("0.5"),
                    close=Decimal("1.5"),
                    volume=Decimal("12.34"),
                    turnover=Decimal("18.51"),
                )
            ],
        )

        self.assertEqual(
            output.read_text(encoding="utf-8").splitlines(),
            [
                "Date,Time,Open,High,Low,Close,TickVolume,Volume,Spread",
                "2024.01.01,00:00:00,1,2,0.5,1.5,12,12.34,0",
            ],
        )

    def test_iter_klines_does_not_drop_oldest_bars_when_api_page_is_limited(self) -> None:
        class FakeClient(BybitClient):
            def __init__(self) -> None:
                self.calls = []
                self.data = [
                    Kline(
                        start_ms=index * 60_000,
                        open=Decimal("1"),
                        high=Decimal("1"),
                        low=Decimal("1"),
                        close=Decimal("1"),
                        volume=Decimal("1"),
                        turnover=Decimal("1"),
                    )
                    for index in range(2_500)
                ]

            def get_klines(self, symbol, interval, category="linear", start_ms=None, end_ms=None, limit=1000):
                self.calls.append((start_ms, end_ms, limit))
                bars = [bar for bar in self.data if start_ms <= bar.start_ms <= end_ms]
                # This mirrors the important Bybit behavior: the API returns
                # the newest `limit` candles from a large requested range.
                return bars[-limit:]

        client = FakeClient()
        bars = client.iter_klines(
            symbol="ETHUSDT",
            interval="1",
            category="linear",
            start_ms=0,
            end_ms=2_500 * 60_000,
        )

        self.assertEqual(len(bars), 2500)
        self.assertEqual([bar.start_ms for bar in bars], [index * 60_000 for index in range(2_500)])
        self.assertEqual(len(client.calls), 3)
        self.assertEqual(client.calls[0], (0, 149_999_999, 1000))
        self.assertEqual(client.calls[1], (0, 89_999_999, 1000))
        self.assertEqual(client.calls[2], (0, 29_999_999, 1000))

    def test_okx_history_candles_parse_rows(self) -> None:
        class FakeOkxClient(OkxClient):
            def _public_get(self, path, params):
                self.path = path
                self.params = params
                return {
                    "code": "0",
                    "data": [
                        ["1704067200000", "1", "2", "0.5", "1.5", "12.34", "12.34", "18.51", "1"]
                    ],
                }

        client = FakeOkxClient()
        bars = client.get_history_candles(inst_id="btc-usdt-swap", bar="1m", after_ms=1704067260000, limit=300)

        self.assertEqual(client.path, "/api/v5/market/history-candles")
        self.assertEqual(client.params["instId"], "BTC-USDT-SWAP")
        self.assertEqual(client.params["bar"], "1m")
        self.assertEqual(client.params["after"], 1704067260000)
        self.assertEqual(client.params["limit"], 100)
        self.assertEqual(
            bars,
            [
                Kline(
                    start_ms=1704067200000,
                    open=Decimal("1"),
                    high=Decimal("2"),
                    low=Decimal("0.5"),
                    close=Decimal("1.5"),
                    volume=Decimal("12.34"),
                    turnover=Decimal("18.51"),
                )
            ],
        )

    def test_okx_iter_klines_pages_backward_from_end(self) -> None:
        class FakeOkxClient(OkxClient):
            def __init__(self) -> None:
                self.calls = []

            def get_history_candles(self, inst_id, bar, after_ms=None, before_ms=None, limit=100):
                self.calls.append((after_ms, limit))
                rows_by_cursor = {
                    300_000: [240_000, 180_000],
                    180_000: [120_000, 60_000],
                }
                return sorted(
                    [
                        Kline(
                            start_ms=start_ms,
                            open=Decimal("1"),
                            high=Decimal("1"),
                            low=Decimal("1"),
                            close=Decimal("1"),
                            volume=Decimal("1"),
                            turnover=Decimal("1"),
                        )
                        for start_ms in rows_by_cursor.get(after_ms, [])
                    ],
                    key=lambda item: item.start_ms,
                )

        client = FakeOkxClient()
        bars = client.iter_klines(inst_id="BTC-USDT-SWAP", bar="1m", start_ms=60_000, end_ms=300_000)

        self.assertEqual([bar.start_ms for bar in bars], [60_000, 120_000, 180_000, 240_000])
        self.assertEqual(client.calls, [(300_000, 100), (180_000, 100)])

    def test_spot_order_omits_reduce_only_when_false(self) -> None:
        class FakeClient(BybitClient):
            def __init__(self) -> None:
                super().__init__(api_key="key", api_secret="secret")
                self.body = None

            def _private_post(self, path, body):
                self.body = body
                return {"result": {}}

        client = FakeClient()
        client.place_order(Signal(symbol="BTCUSDT", side="Buy", qty=Decimal("0.01"), category="spot"))

        self.assertNotIn("reduceOnly", client.body)

    def test_futures_order_keeps_reduce_only(self) -> None:
        class FakeClient(BybitClient):
            def __init__(self) -> None:
                super().__init__(api_key="key", api_secret="secret")
                self.body = None

            def _private_post(self, path, body):
                self.body = body
                return {"result": {}}

        client = FakeClient()
        client.place_order(
            Signal(symbol="BTCUSDT", side="Buy", qty=Decimal("0.01"), category="linear", reduce_only=True)
        )

        self.assertTrue(client.body["reduceOnly"])

    def test_get_instruments_info_uses_bybit_endpoint(self) -> None:
        class FakeClient(BybitClient):
            def __init__(self) -> None:
                super().__init__()
                self.path = None
                self.params = None

            def _public_get(self, path, params):
                self.path = path
                self.params = params
                return {"result": {"list": []}}

        client = FakeClient()
        client.get_instruments_info(category="linear", base_coin="XAG", status="Trading")

        self.assertEqual(client.path, "/v5/market/instruments-info")
        self.assertEqual(client.params["category"], "linear")
        self.assertEqual(client.params["baseCoin"], "XAG")
        self.assertEqual(client.params["status"], "Trading")


if __name__ == "__main__":
    unittest.main()
