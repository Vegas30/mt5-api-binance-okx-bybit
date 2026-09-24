# Bybit Signal Dashboard

Второй вариант real-time дашборда. Основная версия в `dashboard/` не менялась.

## Запуск

```powershell
cd C:\Users\RenamedUser\Documents\Codex\2026-04-29\mt5-api-binance-okx-bybit
python -m http.server 8081 --bind 127.0.0.1 --directory dashboard-signal
```

Открыть:

```text
http://127.0.0.1:8081
```

## Логика рекомендации

Рекомендация `BUY`, `SELL` или `WAIT` считается из live-данных:

- short momentum по последним live-ценам;
- bid/ask depth imbalance по стакану;
- buy/sell trade-flow delta за последнюю минуту;
- spread penalty;
- funding-rate перекос для derivatives;
- активность потока сделок.

Индикатор является эвристическим сигналом для мониторинга, а не торговой гарантией.
