# DCA_for_Crypto usage

## Backtest in MT5 Strategy Tester

Use imported Bybit history as a custom symbol, for example `BYBIT_BTCUSDT`.

Recommended inputs:

```text
ExecutionMode = EXECUTION_MT5_TRADE
UseChartSymbol = true
Mt5TradeSymbol = BYBIT_BTCUSDT
ExchangeSymbol = BTCUSDT
InitialLot = 0.001
MaxTrades = 10
DistanceMode = DISTANCE_PERCENT
DistancePercents = 1.0
TakeProfit = 2.0
StopLoss = 0.0
```

In tester the EA trades through native MT5 orders. This is intentional: MT5 Strategy Tester should not depend on live HTTP calls.

## Live through connector

Start the connector first:

```powershell
python -m bybit_mt5.cli serve --host 127.0.0.1 --port 8765
```

For live trading:

```powershell
$env:BYBIT_API_KEY="..."
$env:BYBIT_API_SECRET="..."
python -m bybit_mt5.cli serve --live-trading
```

MT5 inputs:

```text
ExecutionMode = EXECUTION_BRIDGE
UseChartSymbol = true
ExchangeSymbol = BTCUSDT
ExchangeCategory = linear
BridgeUrl = http://127.0.0.1:8765/signal
```

Also add this URL to MT5:

```text
Tools -> Options -> Expert Advisors -> Allow WebRequest for listed URL:
http://127.0.0.1:8765
```

## Symbol selection

- `UseChartSymbol = true`: the EA uses the chart/tester symbol for price data and MT5 backtest trades.
- `UseChartSymbol = false`: the EA uses `Mt5TradeSymbol`.
- `ExchangeSymbol`: symbol sent to Bybit connector, for example `BTCUSDT` or `ETHUSDT`.
- `ExchangeCategory`: Bybit market category: `linear`, `spot`, or `inverse`.

For consistent tests, run the tester on the same imported symbol that maps to `ExchangeSymbol`.

## If tester trades 0.0000001 volume

This means the MT5 custom symbol specification has an incorrect `SYMBOL_VOLUME_MAX` or `SYMBOL_VOLUME_STEP`.

Reimport the symbol with `mql5\Scripts\ImportBybitCsvToCustomSymbol.mq5` and set, for example:

```text
VolumeMin = 0.001
VolumeMax = 1000.0
VolumeStep = 0.001
```

For ETH/BTC perpetual-style tests this allows lot values like `0.001`, `0.002`, `0.004`, etc. The EA now prints the symbol volume settings on startup and stops with a clear error if `InitialLot` is greater than the custom symbol maximum.

## If profit/loss is always zero

The custom symbol has no contract value settings. Reimport it with the updated import script and set:

```text
ContractSize = 1.0
CurrencyBase = ETH
CurrencyProfit = USD
CurrencyMargin = USD
PricePoint = 0.01
```

For `ETHUSDT`, `ContractSize = 1.0` means 1.0 lot equals 1 ETH, so a move of 10 USD on 0.001 lot is about 0.01 USD before fees. For `BTCUSDT`, use `CurrencyBase = BTC`. The EA prints `contractSize`, `tickSize`, `tickValue`, `profitCurrency`, and `calcMode` at startup; if contract size or tick value is zero, the custom symbol must be reimported.
