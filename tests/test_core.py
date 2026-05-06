from __future__ import annotations

import unittest
from decimal import Decimal
from pathlib import Path

from bybit_mt5.client import interval_to_milliseconds, normalize_side, parse_datetime
from bybit_mt5.client import BybitClient
from bybit_mt5.export import write_mt5_csv
from bybit_mt5.models import Kline


class CoreTests(unittest.TestCase):
    def test_parse_datetime_iso_utc(self) -> None:
        self.assertEqual(parse_datetime("2024-01-01T00:00:00Z"), 1704067200000)

    def test_interval_to_milliseconds(self) -> None:
        self.assertEqual(interval_to_milliseconds("1"), 60_000)
        self.assertEqual(interval_to_milliseconds("D"), 86_400_000)

    def test_normalize_side(self) -> None:
        self.assertEqual(normalize_side("long"), "Buy")
        self.assertEqual(normalize_side("SELL"), "Sell")

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

    def test_iter_klines_splits_large_minute_ranges(self) -> None:
        class FakeClient(BybitClient):
            def __init__(self) -> None:
                self.calls = []

            def get_klines(self, symbol, interval, category="linear", start_ms=None, end_ms=None, limit=1000):
                self.calls.append((start_ms, end_ms, limit))
                assert start_ms is not None
                assert end_ms is not None
                bars = []
                current = start_ms
                while current <= end_ms and len(bars) < limit:
                    bars.append(
                        Kline(
                            start_ms=current,
                            open=Decimal("1"),
                            high=Decimal("1"),
                            low=Decimal("1"),
                            close=Decimal("1"),
                            volume=Decimal("1"),
                            turnover=Decimal("1"),
                        )
                    )
                    current += 60_000
                return bars

        client = FakeClient()
        bars = client.iter_klines(
            symbol="ETHUSDT",
            interval="1",
            category="linear",
            start_ms=0,
            end_ms=2_500 * 60_000,
        )

        self.assertEqual(len(bars), 2500)
        self.assertEqual(len(client.calls), 3)
        self.assertEqual(client.calls[0], (0, 59_999_999, 1000))
        self.assertEqual(client.calls[1], (60_000_000, 119_999_999, 1000))


if __name__ == "__main__":
    unittest.main()
