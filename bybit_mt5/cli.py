from __future__ import annotations

import argparse
import os

from .bridge import run_bridge
from .client import BybitClient, normalize_bybit_symbol, parse_datetime
from .export import write_mt5_csv
from .okx_client import OkxClient


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

    symbols = subparsers.add_parser("symbols", help="List matching Bybit instruments")
    symbols.add_argument("--category", required=True, choices=["spot", "linear", "inverse"])
    symbols.add_argument("--symbol", help="Exact symbol filter, for example: XAGUSDT")
    symbols.add_argument("--base-coin", help="Base coin filter, for example: XAG")
    symbols.add_argument("--status", default="Trading", help="Instrument status filter, default: Trading")
    symbols.add_argument("--testnet", action="store_true")

    download_okx = subparsers.add_parser("download-okx", help="Download OKX candles and export MT5 CSV")
    download_okx.add_argument("--inst-id", required=True, help="Example: BTC-USDT or BTC-USDT-SWAP")
    download_okx.add_argument("--bar", default="1m", help="OKX bar: 1m,3m,5m,15m,30m,1H,2H,4H,6H,12H,1D,1W")
    download_okx.add_argument("--start", required=True, help="UTC ISO date or milliseconds")
    download_okx.add_argument("--end", required=True, help="UTC ISO date or milliseconds")
    download_okx.add_argument("--out", required=True, help="Output CSV path")

    serve = subparsers.add_parser("serve", help="Run local MT5 bridge")
    serve.add_argument("--host", default="127.0.0.1")
    serve.add_argument("--port", type=int, default=8765)
    serve.add_argument("--testnet", action="store_true")
    serve.add_argument("--live-trading", action="store_true")

    args = parser.parse_args()

    if args.command == "download":
        client = BybitClient(testnet=args.testnet)
        symbol = normalize_bybit_symbol(args.symbol)
        if symbol != args.symbol.upper():
            print(f"Normalized symbol {args.symbol} -> {symbol}")
        klines = client.iter_klines(
            symbol=symbol,
            category=args.category,
            interval=args.interval,
            start_ms=parse_datetime(args.start),
            end_ms=parse_datetime(args.end),
        )
        write_mt5_csv(args.out, klines)
        print(f"Wrote {len(klines)} bars to {args.out}")
        return

    if args.command == "symbols":
        client = BybitClient(testnet=args.testnet)
        response = client.get_instruments_info(
            category=args.category,
            symbol=args.symbol,
            base_coin=args.base_coin,
            status=args.status,
        )
        rows = response.get("result", {}).get("list", [])
        if not rows:
            print("No instruments matched the filters.")
            return

        for row in rows:
            print(
                "\t".join(
                    [
                        str(row.get("symbol", "")),
                        str(row.get("status", "")),
                        str(row.get("baseCoin", "")),
                        str(row.get("quoteCoin", "")),
                        str(row.get("contractType", "")),
                    ]
                )
            )
        next_cursor = response.get("result", {}).get("nextPageCursor")
        if next_cursor:
            print(f"nextPageCursor={next_cursor}")
        return

    if args.command == "download-okx":
        client = OkxClient()
        klines = client.iter_klines(
            inst_id=args.inst_id,
            bar=args.bar,
            start_ms=parse_datetime(args.start),
            end_ms=parse_datetime(args.end),
        )
        write_mt5_csv(args.out, klines)
        print(f"Wrote {len(klines)} OKX bars to {args.out}")
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
