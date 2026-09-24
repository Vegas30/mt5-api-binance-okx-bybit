const state = {
  ws: null,
  reconnectTimer: null,
  reconnectAttempts: 0,
  category: "linear",
  symbol: "BTCUSDT",
  interval: "1",
  lastPrice: 0,
  prevPrice: 0,
  prices: [],
  bids: [],
  asks: [],
  trades: [],
  tradeWindow: [],
  ticker: {},
};

const els = {
  controls: document.querySelector("#controls"),
  category: document.querySelector("#category"),
  symbol: document.querySelector("#symbol"),
  interval: document.querySelector("#interval"),
  connectionState: document.querySelector("#connectionState"),
  streamName: document.querySelector("#streamName"),
  lastUpdate: document.querySelector("#lastUpdate"),
  signalHero: document.querySelector("#signalHero"),
  recommendation: document.querySelector("#recommendation"),
  recommendationSummary: document.querySelector("#recommendationSummary"),
  confidenceValue: document.querySelector("#confidenceValue"),
  confidenceBar: document.querySelector("#confidenceBar"),
  scoreGrid: document.querySelector("#scoreGrid"),
  lastPrice: document.querySelector("#lastPrice"),
  priceChange: document.querySelector("#priceChange"),
  bestBidAsk: document.querySelector("#bestBidAsk"),
  spread: document.querySelector("#spread"),
  volume24h: document.querySelector("#volume24h"),
  turnover24h: document.querySelector("#turnover24h"),
  funding: document.querySelector("#funding"),
  openInterest: document.querySelector("#openInterest"),
  priceChart: document.querySelector("#priceChart"),
  momentumSignal: document.querySelector("#momentumSignal"),
  bookSignal: document.querySelector("#bookSignal"),
  bidDepth: document.querySelector("#bidDepth"),
  askDepth: document.querySelector("#askDepth"),
  imbalance: document.querySelector("#imbalance"),
  orderBook: document.querySelector("#orderBook"),
  tradeSignal: document.querySelector("#tradeSignal"),
  buyFlow: document.querySelector("#buyFlow"),
  sellFlow: document.querySelector("#sellFlow"),
  flowDelta: document.querySelector("#flowDelta"),
  trades: document.querySelector("#trades"),
  features: document.querySelector("#features"),
};

const f = {
  price: new Intl.NumberFormat("en-US", { maximumFractionDigits: 8 }),
  compact: new Intl.NumberFormat("en-US", { notation: "compact", maximumFractionDigits: 2 }),
  pct: new Intl.NumberFormat("en-US", { maximumFractionDigits: 3 }),
};

function connect() {
  clearTimeout(state.reconnectTimer);
  if (state.ws) {
    state.ws.onclose = null;
    state.ws.close();
  }

  state.ws = new WebSocket(`wss://stream.bybit.com/v5/public/${state.category}`);
  setConnection("", "Connecting");
  els.streamName.textContent = `${state.category.toUpperCase()} / ${state.symbol}`;

  state.ws.onopen = () => {
    state.reconnectAttempts = 0;
    setConnection("live", "Live");
    state.ws.send(JSON.stringify({
      op: "subscribe",
      args: [
        `tickers.${state.symbol}`,
        `orderbook.50.${state.symbol}`,
        `publicTrade.${state.symbol}`,
        `kline.${state.interval}.${state.symbol}`,
      ],
    }));
  };

  state.ws.onmessage = (event) => {
    let message;
    try {
      message = JSON.parse(event.data);
    } catch {
      return;
    }
    if (message.op === "ping") {
      state.ws.send(JSON.stringify({ op: "pong" }));
      return;
    }
    if (!message.topic) return;
    if (message.topic.startsWith("tickers.")) updateTicker(message.data);
    if (message.topic.startsWith("orderbook.")) updateOrderBook(message.data);
    if (message.topic.startsWith("publicTrade.")) updateTrades(message.data);
    if (message.topic.startsWith("kline.")) updateKline(message.data);
    els.lastUpdate.textContent = `Updated ${new Date().toLocaleTimeString()}`;
    updateRecommendation();
  };

  state.ws.onerror = () => setConnection("error", "Socket error");
  state.ws.onclose = () => {
    setConnection("error", "Reconnecting");
    const delay = Math.min(1000 * 2 ** state.reconnectAttempts, 15000);
    state.reconnectAttempts += 1;
    state.reconnectTimer = setTimeout(connect, delay);
  };
}

function updateTicker(data) {
  state.ticker = { ...state.ticker, ...data };
  const last = num(data.lastPrice);
  if (last) updatePrice(last);

  const change24 = num(data.price24hPcnt);
  els.priceChange.textContent = Number.isFinite(change24) ? `${f.pct.format(change24 * 100)}% 24h` : "-";
  els.priceChange.className = change24 >= 0 ? "up" : "down";
  els.volume24h.textContent = data.volume24h ? f.compact.format(num(data.volume24h)) : "-";
  els.turnover24h.textContent = data.turnover24h ? `Turnover ${f.compact.format(num(data.turnover24h))}` : "Turnover -";

  const funding = num(data.fundingRate);
  els.funding.textContent = Number.isFinite(funding) ? `${f.pct.format(funding * 100)}%` : "-";
  els.openInterest.textContent = data.openInterest ? `OI ${f.compact.format(num(data.openInterest))}` : "OI -";
}

function updateKline(rows) {
  const latest = Array.isArray(rows) ? rows[rows.length - 1] : rows;
  const close = num(latest?.close);
  if (close) updatePrice(close);
}

function updatePrice(price) {
  state.prevPrice = state.lastPrice || price;
  state.lastPrice = price;
  state.prices.push({ price, ts: Date.now() });
  if (state.prices.length > 160) state.prices.shift();
  els.lastPrice.textContent = f.price.format(price);
  els.lastPrice.className = price >= state.prevPrice ? "up" : "down";
  drawChart();
  updateMomentumSignal();
}

function updateOrderBook(data) {
  state.bids = merge(state.bids, data.b || [], true).slice(0, 50);
  state.asks = merge(state.asks, data.a || [], false).slice(0, 50);
  renderOrderBook();
}

function merge(current, updates, desc) {
  const map = new Map(current.map(([price, size]) => [price, size]));
  for (const [price, size] of updates) {
    if (num(size) === 0) map.delete(price);
    else map.set(price, size);
  }
  return [...map.entries()].sort((a, b) => desc ? num(b[0]) - num(a[0]) : num(a[0]) - num(b[0]));
}

function renderOrderBook() {
  const bids = state.bids.slice(0, 20);
  const asks = state.asks.slice(0, 20);
  const bidDepth = depth(bids);
  const askDepth = depth(asks);
  const imb = normalized(bidDepth - askDepth, bidDepth + askDepth);
  const maxSize = Math.max(...bids.map(([, size]) => num(size)), ...asks.map(([, size]) => num(size)), 1);

  els.bidDepth.textContent = f.compact.format(bidDepth);
  els.askDepth.textContent = f.compact.format(askDepth);
  els.imbalance.textContent = `${f.pct.format(imb * 100)}%`;
  els.imbalance.className = imb >= 0 ? "up" : "down";

  const bestBid = bids[0]?.[0];
  const bestAsk = asks[0]?.[0];
  els.bestBidAsk.textContent = bestBid && bestAsk ? `${fmt(bestBid)} / ${fmt(bestAsk)}` : "-";
  if (bestBid && bestAsk) {
    els.spread.textContent = `Spread ${f.price.format(num(bestAsk) - num(bestBid))}`;
  }

  els.orderBook.innerHTML = [
    ...asks.slice(0, 10).reverse().map(([price, size]) => levelRow("ask", price, size, maxSize)),
    ...bids.slice(0, 10).map(([price, size]) => levelRow("bid", price, size, maxSize)),
  ].join("");
  setSignal(els.bookSignal, imb > 0.08 ? "Bid pressure" : imb < -0.08 ? "Ask pressure" : "Balanced", imb);
}

function updateTrades(rows) {
  const now = Date.now();
  for (const trade of Array.isArray(rows) ? rows : [rows]) {
    const side = String(trade.S || trade.side || "").toLowerCase() === "buy" ? "buy" : "sell";
    const price = num(trade.p || trade.price);
    const size = num(trade.v || trade.size);
    if (!price || !size) continue;
    state.trades.unshift({ side, price, size, ts: now });
    state.tradeWindow.push({ side, size, ts: now });
  }
  state.trades = state.trades.slice(0, 60);
  state.tradeWindow = state.tradeWindow.filter((item) => now - item.ts < 60_000);
  renderTrades();
}

function renderTrades() {
  const maxSize = Math.max(...state.trades.map((t) => t.size), 1);
  els.trades.innerHTML = state.trades.slice(0, 24).map((trade) => {
    const width = Math.max(3, Math.min(100, (trade.size / maxSize) * 100));
    return `<div class="row ${trade.side}" style="--w:${width}%"><span>${trade.side.toUpperCase()}</span><span>${f.price.format(trade.price)}</span><span>${fmt(trade.size)}</span></div>`;
  }).join("");

  const flows = tradeFlows();
  els.buyFlow.textContent = f.compact.format(flows.buy);
  els.sellFlow.textContent = f.compact.format(flows.sell);
  els.flowDelta.textContent = f.compact.format(flows.delta);
  els.flowDelta.className = flows.delta >= 0 ? "up" : "down";
  setSignal(els.tradeSignal, flows.delta > 0 ? "Buy flow" : flows.delta < 0 ? "Sell flow" : "Neutral", flows.delta);
}

function updateRecommendation() {
  const inputs = signalInputs();
  const components = [
    { key: "momentum", label: "Momentum", value: clamp(inputs.momentum * 900, -1, 1), weight: 0.28 },
    { key: "book", label: "Book", value: clamp(inputs.imbalance * 3.2, -1, 1), weight: 0.24 },
    { key: "flow", label: "Trade flow", value: clamp(inputs.flowDelta / Math.max(inputs.flowTotal, 1), -1, 1), weight: 0.24 },
    { key: "spread", label: "Spread", value: clamp(-inputs.spreadPct * 700, -0.35, 0.15), weight: 0.08 },
    { key: "funding", label: "Funding", value: clamp(-inputs.funding * 1800, -0.35, 0.35), weight: 0.08 },
    { key: "volume", label: "Activity", value: clamp(inputs.activity, -0.2, 0.2), weight: 0.08 },
  ];

  const score = components.reduce((sum, item) => sum + item.value * item.weight, 0);
  const confidence = Math.min(100, Math.round(Math.abs(score) * 125));
  const ready = state.prices.length >= 10 && state.bids.length >= 5 && state.trades.length >= 10;
  const action = !ready || confidence < 22 ? "WAIT" : score > 0 ? "BUY" : "SELL";
  const cls = action === "BUY" ? "buy" : action === "SELL" ? "sell" : "wait";
  const top = [...components].sort((a, b) => Math.abs(b.value * b.weight) - Math.abs(a.value * a.weight)).slice(0, 3);

  els.signalHero.className = `signal-hero ${cls}`;
  els.recommendation.textContent = action;
  els.confidenceValue.textContent = `${confidence}%`;
  els.confidenceBar.style.width = `${confidence}%`;
  els.recommendationSummary.textContent = ready
    ? top.map((item) => `${item.label}: ${signed(item.value)}`).join(" | ")
    : "Waiting for enough live price, book and trade data";

  els.scoreGrid.innerHTML = components.slice(0, 6).map((item) => {
    const contribution = item.value * item.weight;
    const sideClass = contribution > 0 ? "buy-text" : contribution < 0 ? "sell-text" : "wait-text";
    return `<div><span>${item.label}</span><strong class="${sideClass}">${signed(contribution)}</strong></div>`;
  }).join("");

  els.features.innerHTML = [
    feature("Raw score", signed(score), score),
    feature("Confidence", `${confidence}%`, score),
    feature("Book imbalance", `${f.pct.format(inputs.imbalance * 100)}%`, inputs.imbalance),
    feature("Trade-flow delta", f.compact.format(inputs.flowDelta), inputs.flowDelta),
    feature("Short return", `${f.pct.format(inputs.momentum * 100)}%`, inputs.momentum),
    feature("Spread pct", `${f.pct.format(inputs.spreadPct * 100)}%`, -inputs.spreadPct),
  ].join("");
}

function signalInputs() {
  const bidDepth = depth(state.bids.slice(0, 20));
  const askDepth = depth(state.asks.slice(0, 20));
  const imbalance = normalized(bidDepth - askDepth, bidDepth + askDepth);
  const flows = tradeFlows();
  const shortWindow = state.prices.slice(-30);
  const first = shortWindow[0]?.price || state.lastPrice || 1;
  const last = shortWindow[shortWindow.length - 1]?.price || first;
  const momentum = normalized(last - first, first);
  const bestBid = num(state.bids[0]?.[0]);
  const bestAsk = num(state.asks[0]?.[0]);
  const mid = bestBid && bestAsk ? (bestBid + bestAsk) / 2 : state.lastPrice || 1;
  const spreadPct = bestBid && bestAsk ? (bestAsk - bestBid) / mid : 0;
  const funding = num(state.ticker.fundingRate);
  const activity = clamp(state.tradeWindow.length / 120, 0, 1) - 0.2;

  return { imbalance, flowDelta: flows.delta, flowTotal: flows.total, momentum, spreadPct, funding, activity };
}

function drawChart() {
  const canvas = els.priceChart;
  const dpr = window.devicePixelRatio || 1;
  const rect = canvas.getBoundingClientRect();
  canvas.width = Math.max(300, Math.floor(rect.width * dpr));
  canvas.height = Math.max(220, Math.floor(rect.height * dpr));
  const ctx = canvas.getContext("2d");
  ctx.scale(dpr, dpr);
  const width = canvas.width / dpr;
  const height = canvas.height / dpr;
  ctx.clearRect(0, 0, width, height);

  const points = state.prices;
  if (points.length < 2) {
    ctx.fillStyle = "#8f9da5";
    ctx.fillText("Waiting for price data", 18, 28);
    return;
  }

  const prices = points.map((p) => p.price);
  const min = Math.min(...prices);
  const max = Math.max(...prices);
  const range = max - min || 1;
  const pad = 18;

  ctx.strokeStyle = "#2b353c";
  ctx.lineWidth = 1;
  for (let i = 0; i < 5; i += 1) {
    const y = pad + ((height - pad * 2) / 4) * i;
    ctx.beginPath();
    ctx.moveTo(pad, y);
    ctx.lineTo(width - pad, y);
    ctx.stroke();
  }

  ctx.strokeStyle = points[points.length - 1].price >= points[0].price ? "#15b887" : "#e25959";
  ctx.lineWidth = 2;
  ctx.beginPath();
  points.forEach((point, index) => {
    const x = pad + (index / (points.length - 1)) * (width - pad * 2);
    const y = height - pad - ((point.price - min) / range) * (height - pad * 2);
    if (index === 0) ctx.moveTo(x, y);
    else ctx.lineTo(x, y);
  });
  ctx.stroke();

  ctx.fillStyle = "#8f9da5";
  ctx.font = "12px system-ui";
  ctx.fillText(f.price.format(max), pad, 16);
  ctx.fillText(f.price.format(min), pad, height - 8);
}

function updateMomentumSignal() {
  const inputs = signalInputs();
  setSignal(els.momentumSignal, inputs.momentum > 0.001 ? "Momentum up" : inputs.momentum < -0.001 ? "Momentum down" : "Neutral", inputs.momentum);
}

function levelRow(type, price, size, maxSize) {
  const width = Math.max(3, Math.min(100, (num(size) / maxSize) * 100));
  return `<div class="row ${type}" style="--w:${width}%"><span>${fmt(price)}</span><span>${fmt(size)}</span><span>${type.toUpperCase()}</span></div>`;
}

function feature(label, value, sign) {
  const cls = sign > 0 ? "up" : sign < 0 ? "down" : "";
  return `<div><span>${label}</span><strong class="${cls}">${value}</strong></div>`;
}

function tradeFlows() {
  const buy = state.tradeWindow.filter((t) => t.side === "buy").reduce((sum, t) => sum + t.size, 0);
  const sell = state.tradeWindow.filter((t) => t.side === "sell").reduce((sum, t) => sum + t.size, 0);
  return { buy, sell, delta: buy - sell, total: buy + sell };
}

function setConnection(status, label) {
  els.connectionState.className = `status-pill ${status}`;
  els.connectionState.querySelector("span:last-child").textContent = label;
}

function setSignal(element, label, value) {
  element.textContent = label;
  element.className = `signal ${value > 0 ? "buy" : value < 0 ? "sell" : ""}`;
}

function depth(levels) {
  return levels.reduce((sum, [, size]) => sum + num(size), 0);
}

function normalized(numerator, denominator) {
  return denominator ? numerator / denominator : 0;
}

function signed(value) {
  return `${value >= 0 ? "+" : ""}${Number(value).toFixed(3)}`;
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function num(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : 0;
}

function fmt(value) {
  return f.price.format(num(value));
}

els.controls.addEventListener("submit", (event) => {
  event.preventDefault();
  state.category = els.category.value;
  state.symbol = els.symbol.value.trim().toUpperCase();
  state.interval = els.interval.value;
  state.lastPrice = 0;
  state.prevPrice = 0;
  state.prices = [];
  state.bids = [];
  state.asks = [];
  state.trades = [];
  state.tradeWindow = [];
  state.ticker = {};
  connect();
});

window.addEventListener("resize", drawChart);
connect();
