from __future__ import annotations

import csv
from pathlib import Path

from .models import Kline


MT5_HEADER = ["Date", "Time", "Open", "High", "Low", "Close", "TickVolume", "Volume", "Spread"]


def write_mt5_csv(path: str | Path, klines: list[Kline]) -> None:
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)

    with target.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(MT5_HEADER)
        for candle in klines:
            dt = candle.dt_utc
            writer.writerow(
                [
                    dt.strftime("%Y.%m.%d"),
                    dt.strftime("%H:%M:%S"),
                    str(candle.open),
                    str(candle.high),
                    str(candle.low),
                    str(candle.close),
                    str(max(int(candle.volume), 1)),
                    str(candle.volume),
                    "0",
                ]
            )

