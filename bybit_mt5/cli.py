from __future__ import annotations

import argparse
import os

from .bridge import run_bridge
from .client import BybitClient, parse_datetime
from .export import write_mt5_csv


def main() -> None:
    parser = argparse.ArgumentParser(prog="bybit-mt5")
    subparsers = parser.add_subparsers(dest="command", required=True)

    download = subparsers.add_parser("download", help="Download Bybit klines and export MT5 CSV")
    download.add_argument("--symbol", required=True, help="Example: BTCUSDT")
    download.add_argument("--category", default="linear", choices=["spot", "linear", "inverse"])
    download.add_argument("--interval", default="1", help="Bybit interval: 1,3,5,15,30,60,120,240,360,720,D,W")
    download.add_argument("--start", required=True, help="UTC ISO date or milliseconds")
    download.add_argument("--end", required=True, help="UTC ISO date or milliseconds")
    download.add_argument("--out", required=True, help="Output CSV path")
    download.add_argument("--testnet", action="store_true")

    serve = subparsers.add_parser("serve", help="Run local MT5 bridge")
    serve.add_argument("--host", default="127.0.0.1")
    serve.add_argument("--port", type=int, default=8765)
    serve.add_argument("--testnet", action="store_true")
    serve.add_argument("--live-trading", action="store_true")

    args = parser.parse_args()

    if args.command == "download":
        client = BybitClient(testnet=args.testnet)
        klines = client.iter_klines(
            symbol=args.symbol,
            category=args.category,
            interval=args.interval,
            start_ms=parse_datetime(args.start),
            end_ms=parse_datetime(args.end),
        )
        write_mt5_csv(args.out, klines)
        print(f"Wrote {len(klines)} bars to {args.out}")
        return

    if args.command == "serve":
        client = BybitClient(
            api_key=os.getenv("BYBIT_API_KEY"),
            api_secret=os.getenv("BYBIT_API_SECRET"),
            testnet=args.testnet,
        )
        run_bridge(args.host, args.port, client=client, live_trading=args.live_trading)


if __name__ == "__main__":
    main()

