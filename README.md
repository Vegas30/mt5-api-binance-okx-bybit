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

## Подробно: скачивание исторических данных (`download`)

Базовый синтаксис:

```powershell
python -m bybit_mt5.cli download --symbol <SYMBOL> --category <CATEGORY> --interval <INTERVAL> --start <START> --end <END> --out <FILE.csv> [--testnet]
```

Все параметры команды:

1. `--symbol` (обязательный)  
Торговая пара Bybit, обычно без разделителей, например: `BTCUSDT`, `ETHUSDT`, `SOLUSDT`.
Если у вас MT5-стиль с суффиксом `.P`, например `XAGUSDT.P`, CLI нормализует его в `XAGUSDT`.

2. `--category` (необязательный, по умолчанию `linear`)  
Тип рынка:
- `spot` - спот
- `linear` - USDT perpetual/фьючерсы
- `inverse` - inverse контракты

3. `--interval` (необязательный, по умолчанию `1`)  
Таймфрейм свечей:
- `1`, `3`, `5`, `15`, `30` минут
- `60`, `120`, `240`, `360`, `720` минут
- `D` (день), `W` (неделя)

4. `--start` (обязательный)  
Начало диапазона в UTC. Допустимые форматы:
- ISO-дата: `2026-04-01`
- ISO-дата/время: `2026-04-01T00:00:00Z`
- timestamp в миллисекундах: `1775001600000`

5. `--end` (обязательный)  
Конец диапазона в UTC, в тех же форматах, что `--start`.
Важно: верхняя граница не включается (`end` exclusive).  
Пример: чтобы взять весь день `2026-04-30`, нужно ставить `--end 2026-05-01`.

6. `--out` (обязательный)  
Куда сохранить CSV, например: `data\ETHUSDT_M1_2026-04.csv`.

7. `--testnet` (опционально, флаг)  
Использует testnet endpoint Bybit для истории.

Если нужно уточнить точное имя инструмента на Bybit, используйте:

```powershell
python -m bybit_mt5.cli symbols --category linear --base-coin XAG --status Trading
```

Для `XAG` это вернёт `XAGUSDT` в категории `linear`.

Примеры:

```powershell
# ETHUSDT, 1 минута, весь апрель 2026 (UTC)
python -m bybit_mt5.cli download --symbol ETHUSDT --category linear --interval 1 --start 2026-04-01 --end 2026-05-01 --out data\ETHUSDT_M1_2026-04.csv

# BTCUSDT spot, 5 минут, неделя
python -m bybit_mt5.cli download --symbol BTCUSDT --category spot --interval 5 --start 2026-04-01 --end 2026-04-08 --out data\BTCUSDT_SPOT_M5_week.csv

# SOLUSDT linear, часовые свечи, конкретное UTC-время
python -m bybit_mt5.cli download --symbol SOLUSDT --category linear --interval 60 --start 2026-04-01T00:00:00Z --end 2026-04-15T12:00:00Z --out data\SOLUSDT_H1.csv

# Testnet
python -m bybit_mt5.cli download --symbol BTCUSDT --category linear --interval 15 --start 2026-04-01 --end 2026-04-03 --out data\BTCUSDT_M15_testnet.csv --testnet
```

Проверка результата:

```powershell
Get-Content data\ETHUSDT_M1_2026-04.csv -TotalCount 5
```

Частые причины, почему данных "мало":

- Неверный `category` для инструмента (`spot` vs `linear`).
- Неверный символ для выбранного рынка.
- Диапазон указан не в UTC.
- Ожидание, что `end` включительный (в нашем CLI он не включается).
- На стороне биржи нет данных за часть периода для конкретного инструмента.

Технически: Bybit отдает максимум 1000 свечей за один REST-запрос. В CLI это уже обработано пагинацией, поэтому длинные диапазоны (например месяц M1) скачиваются автоматически в несколько запросов.

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
