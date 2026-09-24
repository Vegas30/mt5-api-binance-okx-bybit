# Bybit Real-Time Dashboard

Локальный real-time дашборд на публичных WebSocket-потоках Bybit V5. API-ключи не нужны.

## Запуск

```powershell
cd C:\Users\RenamedUser\Documents\Codex\2026-04-29\mt5-api-binance-okx-bybit
python -m http.server 8080 --directory dashboard
```

Затем открыть:

```text
http://127.0.0.1:8080
```

## Что показывает

- live price и 24h change;
- best bid/ask и spread;
- 24h volume/turnover;
- funding rate и open interest для derivatives;
- top levels стакана;
- bid/ask depth imbalance;
- поток публичных сделок;
- buy/sell flow за последнюю минуту;
- компактный набор признаков для моделей движения цены.

## Источник данных

Данные приходят из публичного Bybit V5 WebSocket:

```text
wss://stream.bybit.com/v5/public/{spot|linear|inverse}
```

Используемые topics:

- `tickers.{symbol}`
- `orderbook.50.{symbol}`
- `publicTrade.{symbol}`
- `kline.{interval}.{symbol}`
