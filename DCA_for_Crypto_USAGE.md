# DCA_for_Crypto usage

## Backtest in MT5 Strategy Tester

Use imported Bybit history as a custom symbol, for example `BYBIT_BTCUSDT`.

Recommended inputs:

```text
ExecutionMode = EXECUTION_MT5_TRADE
UseChartSymbol = true
Mt5TradeSymbol = BYBIT_BTCUSDT
HedgeMt5Symbol = BYBIT_BTCUSDT.P
ExchangeSymbol = BTCUSDT
HedgeFuturesSymbol = BTCUSDT
InitialLot = 0.001
MaxTrades = 10
DistanceMode = DISTANCE_PERCENT
DistancePercents = 1.0
TakeProfit = 2.0
StopLoss = 0.0
UseTrailing = false
TrailLevel = 1.0
TrailMove = 0.5
TrailStep = 0.25
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
ExchangeCategory = spot
HedgeMt5Symbol = BYBIT_BTCUSDT.P
HedgeFuturesSymbol = BTCUSDT
BridgeUrl = http://127.0.0.1:8765/signal
UseFuturesHedge = true
HedgeFuturesCategory = linear
HedgeInsuranceVolume = 0.001
HedgeStopLoss = 1.0
HedgeNonLossOffset = 0.0
HedgeNonLossTrigger = 1.0
ReopenHedgeAfterStop = true
ReopenHedgeCooldownBars = 3
LimitHedgeVolumeToOpenSpot = true
SpotCommissionPercent = 0.1
FuturesCommissionPercent = 0.055
```

Also add this URL to MT5:

```text
Tools -> Options -> Expert Advisors -> Allow WebRequest for listed URL:
http://127.0.0.1:8765
```

## Symbol selection

- `UseChartSymbol = true`: the EA uses the chart/tester symbol for price data and MT5 backtest trades.
- `UseChartSymbol = false`: the EA uses `Mt5TradeSymbol`.
- `HedgeMt5Symbol`: separate MT5 futures/custom symbol used for hedge prices and MT5 tester hedge sells.
- `ExchangeSymbol`: spot symbol sent to Bybit connector, for example `BTCUSDT` or `ETHUSDT`.
- `HedgeFuturesSymbol`: futures symbol sent to Bybit connector for hedge sells and reduce-only buys.
- `ExchangeCategory`: Bybit market category: `linear`, `spot`, or `inverse`.

For realistic hedge tests, import/select both MT5 symbols: the spot chart symbol or `Mt5TradeSymbol`, and `HedgeMt5Symbol` for futures prices.

## Spot DCA with insurance futures hedge

When `UseFuturesHedge = true`, the EA opens one insurance futures short at the start of a new basket, after the first spot buy succeeds. DCA buys do not create additional hedge orders. In tester it uses `HedgeMt5Symbol`; in live bridge mode it uses `HedgeFuturesSymbol` + `HedgeFuturesCategory`.

- `ExchangeCategory`: use `spot` for spot DCA buys and basket sells.
- `HedgeMt5Symbol`: MT5 futures/custom symbol for hedge prices and tester hedge sell orders.
- `HedgeFuturesSymbol`: live exchange futures symbol for hedge orders.
- `HedgeFuturesCategory`: futures market category for the hedge, usually `linear`.
- `HedgeInsuranceVolume`: manual volume for the single insurance futures hedge.
- `HedgeStopLoss`: stop-loss percent above the futures short entry price. `0` disables it.
- `HedgeNonLossTrigger`: favorable price move percent from the short entry before moving SL to non-loss.
- `HedgeNonLossOffset`: percent below the short entry where the non-loss SL is placed.
- `ReopenHedgeAfterStop`: if `true`, a hedge closed by its SL is opened again only when the spot price goes back below the original spot buy price.
- `ReopenHedgeCooldownBars`: number of current chart/tester timeframe bars to wait after hedge SL before re-opening. On H1 it counts H1 candles; on M1 it counts M1 candles. `0` disables the cooldown.
- `LimitHedgeVolumeToOpenSpot`: in MT5 tester/trade mode, prevents total open futures hedge SELL volume from exceeding the currently open DCA spot BUY volume. The first spot buy is excluded because it is not hedged.
- `SpotCommissionPercent`: spot fee percent of trade notional per side. `0.1` means 0.1% on buy and 0.1% on sell.
- `FuturesCommissionPercent`: futures fee percent of trade notional per side. `0.055` means 0.055% on hedge entry and 0.055% on hedge close.

Example: if a futures hedge is sold at `100000`, `HedgeStopLoss = 1.0` starts its virtual SL at `101000`. If `HedgeNonLossTrigger = 1.0`, after price falls to `99000`, the SL moves to `100000` when `HedgeNonLossOffset = 0.0`, or to `99900` when `HedgeNonLossOffset = 0.1`.

Re-hedge example: if the first spot buy was at `98000`, the insurance futures hedge closed by SL, `ReopenHedgeAfterStop = true`, and `ReopenHedgeCooldownBars = 3`, the EA waits at least 3 current-timeframe bars, then waits until the current spot bid is `98000` or lower, and only then opens a new futures short with `HedgeInsuranceVolume`.

Commission accounting is printed to the EA log as `Spot commission`, `Futures commission`, `Basket commission summary`, and `Total commission summary`. It is an internal calculated total and does not change MT5 Strategy Tester balance directly.

## Trailing logic

- `TrailLevel`: profit percent from average price before trailing can start.
- `TrailMove`: distance from current price to trailing stop.
- `TrailStep`: minimum improvement percent before the EA moves the stop again.

In `EXECUTION_MT5_TRADE` the EA modifies MT5 SL only when `TrailStep` is passed. In `EXECUTION_BRIDGE` it does not spam exchange stop modifications: the stop is virtual inside MT5, and the EA sends one reduce-only market close to the connector only when price crosses the trailing stop.

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
