from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from decimal import Decimal


@dataclass(frozen=True)
class Kline:
    start_ms: int
    open: Decimal
    high: Decimal
    low: Decimal
    close: Decimal
    volume: Decimal
    turnover: Decimal

    @property
    def dt_utc(self) -> datetime:
        return datetime.fromtimestamp(self.start_ms / 1000, tz=timezone.utc)


@dataclass(frozen=True)
class Signal:
    symbol: str
    side: str
    qty: Decimal
    category: str = "linear"
    order_type: str = "Market"
    price: Decimal | None = None
    reduce_only: bool = False
    time_in_force: str = "GTC"

