# MT5 Bybit Connector

Практичный стартовый коннектор между MetaTrader 5 и Bybit V5 API.

Выбран Bybit, потому что у него единый V5 API для spot/linear/inverse, простая публичная загрузка свечей, testnet для проверки торговли и официальный лимит до 1000 kline-записей за REST-запрос. Binance тоже подходит для истории, но для дальнейшей торговли API и доступность сильнее зависят от юрисдикции. OKX API мощный, но для первого MT5-моста требует больше нормализации инструментов и account-mode деталей.

## Что уже есть

- Загрузка исторических OHLCV свечей Bybit.
- Экспорт CSV в формат, который удобно импортировать в MT5 custom symbol.
- Локальный HTTP bridge для MT5 советников.
- Dry-run торговый endpoint, чтобы сначала интегрировать советники без реальных заявок.
- Пример MQL5 советника, который отправляет сигнал в bridge.

## Быстрый старт

```powershell
python -m bybit_mt5.cli download --symbol BTCUSDT --category linear --interval 1 --start 2024-01-01 --end 2024-01-02 --out data\BTCUSDT_M1.csv
```

## Как открыть скачанную историю в MT5

CSV сам по себе не появится на графике. Его нужно импортировать в custom symbol.

1. Скопируйте CSV в общую файловую папку MT5:

```powershell
Copy-Item data\BTCUSDT_M1.csv "$env:APPDATA\MetaQuotes\Terminal\Common\Files\BTCUSDT_M1.csv"
```

2. Скопируйте `mql5\Scripts\ImportBybitCsvToCustomSymbol.mq5` в папку терминала:

```text
MQL5\Scripts\ImportBybitCsvToCustomSymbol.mq5
```

3. В MT5 откройте MetaEditor, скомпилируйте скрипт `ImportBybitCsvToCustomSymbol`.

4. В MT5 запустите скрипт из Navigator -> Scripts. Параметры по умолчанию:

```text
CsvFileName = BTCUSDT_M1.csv
CustomSymbolName = BYBIT_BTCUSDT
```

5. Откройте Market Watch, включите Show All, найдите `BYBIT_BTCUSDT`, затем откройте M1 chart.

Запуск локального bridge:

```powershell
python -m bybit_mt5.cli serve --host 127.0.0.1 --port 8765
```

Проверка:

```powershell
Invoke-RestMethod http://127.0.0.1:8765/health
```

## Торговля

По умолчанию bridge работает в dry-run режиме и не отправляет реальные заявки.

Для реальной отправки заявок:

```powershell
$env:BYBIT_API_KEY="..."
$env:BYBIT_API_SECRET="..."
python -m bybit_mt5.cli serve --live-trading
```

Для testnet:

```powershell
$env:BYBIT_API_KEY="..."
$env:BYBIT_API_SECRET="..."
python -m bybit_mt5.cli serve --testnet --live-trading
```

В MT5 нужно разрешить WebRequest для URL:

```text
http://127.0.0.1:8765
```

## Архитектура

```text
MT5 Expert Advisor
        |
        | HTTP POST /signal
        v
Local Python bridge
        |
        | signed REST when live-trading enabled
        v
Bybit V5 API
```

Исторические данные для бектеста лучше загружать заранее через CLI и импортировать в custom symbol MT5. Для торговли советник отправляет сигнал в локальный bridge, а bridge уже валидирует, логирует и подписывает заявки.

## Важные ограничения

- Это не торговая рекомендация и не готовая HFT-инфраструктура.
- Перед live-режимом обязательно прогнать testnet и dry-run.
- MT5 Strategy Tester не исполняет сетевые WebRequest так же, как live chart, поэтому для бектеста используйте custom symbol с импортированной историей.
- Для фьючерсов и perpetual нужно внимательно настроить размер контракта, шаг объема, плечо и режим позиции на стороне биржи.
