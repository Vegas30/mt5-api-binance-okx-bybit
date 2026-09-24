const state = {
  ws: null,
  reconnectTimer: null,
  reconnectAttempts: 0,
  category: "linear",
  symbol: "BTCUSDT",
  interval: "1",
  lastPrice: null,
  prevPrice: null,
  prices: [],
  trades: [],
  bids: [],
  asks: [],
  buyFlow: 0,
  sellFlow: 0,
  lastTradeWindow: [],
};

const els = {
  controls: document.querySelector("#controls"),
  category: document.querySelector("#category"),
  symbol: document.querySelector("#symbol"),
  interval: document.querySelector("#interval"),
  connectionState: document.querySelector("#connectionState"),
  streamName: document.querySelector("#streamName"),
  lastUpdate: document.querySelector("#lastUpdate"),
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

const formatters = {
  price: new Intl.NumberFormat("en-US", { maximumFractionDigits: 8 }),
  compact: new Intl.NumberFormat("en-US", { notation: "compact", maximumFractionDigits: 2 }),
  pct: new Intl.NumberFormat("en-US", { maximumFractionDigits: 4 }),
};

function wsUrl(category) {
  return `wss://stream.bybit.com/v5/public/${category}`;
}

function topics() {
  const symbol = state.symbol;
  const kline = `kline.${state.interval}.${symbol}`;
  return [`tickers.${symbol}`, `orderbook.50.${symbol}`, `publicTrade.${symbol}`, kline];
}

function setConnection(status, label) {
  els.connectionState.className = `status-pill ${status}`;
  els.connectionState.querySelector("span:last-child").textContent = label;
}

function connect() {
  clearTimeout(state.reconnectTimer);
  if (state.ws) {
    state.ws.onclose = null;
    state.ws.close();
  }

  state.ws = new WebSocket(wsUrl(state.category));
  setConnection("", "Connecting");
  els.streamName.textContent = `${state.category.toUpperCase()} / ${state.symbol}`;

  state.ws.onopen = () => {
    state.reconnectAttempts = 0;
    setConnection("live", "Live");
    state.ws.send(JSON.stringify({ op: "subscribe", args: topics() }));
  };

  state.ws.onmessage = (event) => {
    const message = JSON.parse(event.data);
    if (message.op === "ping") {
      state.ws.send(JSON.stringify({ op: "pong" }));
      return;
    }
    if (!message.topic) return;
    routeMessage(message);
    els.lastUpdate.textContent = `Updated ${new Date().toLocaleTimeString()}`;
  };

  state.ws.onerror = () => setConnection("error", "Socket error");
  state.ws.onclose = () => {
    setConnection("error", "Reconnecting");
    const delay = Math.min(1000 * 2 ** state.reconnectAttempts, 15000);
    state.reconnectAttempts += 1;
    state.reconnectTimer = setTimeout(connect, delay);
  };
}

function routeMessage(message) {
  if (message.topic.startsWith("tickers.")) updateTicker(message.data);
  if (message.topic.startsWith("orderbook.")) updateOrderBook(message.data);
  if (message.topic.startsWith("publicTrade.")) updateTrades(message.data);
  if (message.topic.startsWith("kline.")) updateKline(message.data);
}

function updateTicker(data) {
  const lastPrice = toNumber(data.lastPrice);
  if (lastPrice) updatePrice(lastPrice);

  const price24hPcnt = toNumber(data.price24hPcnt);
  els.priceChange.textContent = Number.isFinite(price24hPcnt)
    ? `${formatters.pct.format(price24hPcnt * 100)}% 24h`
    : "-";
  els.priceChange.className = price24hPcnt >= 0 ? "up" : "down";

  els.volume24h.textContent = data.volume24h ? formatters.compact.format(toNumber(data.volume24h)) : "-";
  els.turnover24h.textContent = data.turnover24h
    ? `Turnover ${formatters.compact.format(toNumber(data.turnover24h))}`
    : "Turnover -";

  const fundingRate = toNumber(data.fundingRate);
  els.funding.textContent = Number.isFinite(fundingRate) ? `${formatters.pct.format(fundingRate * 100)}%` : "-";
  els.openInterest.textContent = data.openInterest
    ? `OI ${formatters.compact.format(toNumber(data.openInterest))}`
    : "OI -";

  updateFeatures();
}

function updateKline(rows) {
  const latest = Array.isArray(rows) ? rows[rows.length - 1] : rows;
  const close = toNumber(latest?.close);
  if (close) updatePrice(close);
}

function updatePrice(price) {
  state.prevPrice = state.lastPrice ?? price;
  state.lastPrice = price;
  state.prices.push({ price, ts: Date.now() });
  if (state.prices.length > 160) state.prices.shift();

  els.lastPrice.textContent = formatters.price.format(price);
  const direction = price >= state.prevPrice ? "up" : "down";
  els.lastPrice.className = direction;
  drawPriceChart();
  updateMomentumSignal();
}

function updateOrderBook(data) {
  const bidUpdates = data.b ?? [];
  const askUpdates = data.a ?? [];
  state.bids = mergeLevels(state.bids, bidUpdates, true).slice(0, 50);
  state.asks = mergeLevels(state.asks, askUpdates, false).slice(0, 50);
  renderOrderBook();
  updateFeatures();
}

function mergeLevels(current, updates, descending) {
  const map = new Map(current.map(([price, size]) => [price, size]));
  for (const [price, size] of updates) {
    if (toNumber(size) === 0) map.delete(price);
    else map.set(price, size);
  }
  return [...map.entries()].sort((a, b) => descending ? toNumber(b[0]) - toNumber(a[0]) : toNumber(a[0]) - toNumber(b[0]));
}

function renderOrderBook() {
  const topBids = state.bids.slice(0, 20);
  const topAsks = state.asks.slice(0, 20);
  const bidDepth = depth(topBids);
  const askDepth = depth(topAsks);
  const imbalance = bidDepth + askDepth > 0 ? (bidDepth - askDepth) / (bidDepth + askDepth) : 0;
  const maxSize = Math.max(...topBids.map(([, size]) => toNumber(size)), ...topAsks.map(([, size]) => toNumber(size)), 1);

  els.bidDepth.textContent = formatters.compact.format(bidDepth);
  els.askDepth.textContent = formatters.compact.format(askDepth);
  els.imbalance.textContent = `${formatters.pct.format(imbalance * 100)}%`;
  els.imbalance.className = imbalance >= 0 ? "up" : "down";

  const bestBid = topBids[0]?.[0];
  const bestAsk = topAsks[0]?.[0];
  els.bestBidAsk.textContent = bestBid && bestAsk ? `${fmt(bestBid)} / ${fmt(bestAsk)}` : "-";
  if (bestBid && bestAsk) {
    const spread = toNumber(bestAsk) - toNumber(bestBid);
    els.spread.textContent = `Spread ${formatters.price.format(spread)}`;
  }

  const askRows = topAsks.slice(0, 10).reverse().map(([price, size]) => bookRow("ask", price, size, maxSize));
  const bidRows = topBids.slice(0, 10).map(([price, size]) => bookRow("bid", price, size, maxSize));
  els.orderBook.innerHTML = [...askRows, ...bidRows].join("");

  setSignal(els.bookSignal, imbalance > 0.08 ? "Bid pressure" : imbalance < -0.08 ? "Ask pressure" : "Balanced", imbalance);
}

function bookRow(type, price, size, maxSize) {
  const pct = Math.max(3, Math.min(100, (toNumber(size) / maxSize) * 100));
  return `<div class="row ${type}" style="--w:${pct}%"><span>${fmt(price)}</span><span>${fmt(size)}</span><span>${type.toUpperCase()}</span></div>`;
}

function updateTrades(rows) {
  const list = Array.isArray(rows) ? rows : [rows];
  const now = Date.now();

  for (const trade of list) {
    const side = String(trade.S || trade.side || "").toLowerCase() === "buy" ? "buy" : "sell";
    const price = toNumber(trade.p || trade.price);
    const size = toNumber(trade.v || trade.size);
    if (!price || !size) continue;
    state.trades.unshift({ side, price, size, ts: now });
    state.lastTradeWindow.push({ side, size, ts: now });
  }

  state.trades = state.trades.slice(0, 60);
  state.lastTradeWindow = state.lastTradeWindow.filter((item) => now - item.ts < 60_000);
  renderTrades();
  updateFeatures();
}

function renderTrades() {
  const maxSize = Math.max(...state.trades.map((trade) => trade.size), 1);
  els.trades.innerHTML = state.trades.slice(0, 24).map((trade) => {
    const pct = Math.max(3, Math.min(100, (trade.size / maxSize) * 100));
    return `<div class="row ${trade.side}" style="--w:${pct}%"><span>${trade.side.toUpperCase()}</span><span>${formatters.price.format(trade.price)}</span><span>${fmt(trade.size)}</span></div>`;
  }).join("");

  const buyFlow = state.lastTradeWindow.filter((t) => t.side === "buy").reduce((sum, t) => sum + t.size, 0);
  const sellFlow = state.lastTradeWindow.filter((t) => t.side === "sell").reduce((sum, t) => sum + t.size, 0);
  const delta = buyFlow - sellFlow;
  els.buyFlow.textContent = formatters.compact.format(buyFlow);
  els.sellFlow.textContent = formatters.compact.format(sellFlow);
  els.flowDelta.textContent = formatters.compact.format(delta);
  els.flowDelta.className = delta >= 0 ? "up" : "down";
  setSignal(els.tradeSignal, delta > 0 ? "Buy flow" : delta < 0 ? "Sell flow" : "Neutral", delta);
}

function drawPriceChart() {
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

  const rising = points[points.length - 1].price >= points[0].price;
  ctx.strokeStyle = rising ? "#15b887" : "#e25959";
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
  ctx.fillText(formatters.price.format(max), pad, 16);
  ctx.fillText(formatters.price.format(min), pad, height - 8);
}

function updateMomentumSignal() {
  const points = state.prices.slice(-30);
  if (points.length < 6) return;
  const change = (points[points.length - 1].price - points[0].price) / points[0].price;
  setSignal(els.momentumSignal, change > 0.001 ? "Momentum up" : change < -0.001 ? "Momentum down" : "Neutral", change);
}

function updateFeatures() {
  const bidDepth = depth(state.bids.slice(0, 20));
  const askDepth = depth(state.asks.slice(0, 20));
  const imbalance = bidDepth + askDepth > 0 ? (bidDepth - askDepth) / (bidDepth + askDepth) : 0;
  const buyFlow = state.lastTradeWindow.filter((t) => t.side === "buy").reduce((sum, t) => sum + t.size, 0);
  const sellFlow = state.lastTradeWindow.filter((t) => t.side === "sell").reduce((sum, t) => sum + t.size, 0);
  const last30 = state.prices.slice(-30);
  const ret = last30.length > 1 ? (last30[last30.length - 1].price - last30[0].price) / last30[0].price : 0;

  els.features.innerHTML = [
    feature("Book imbalance", `${formatters.pct.format(imbalance * 100)}%`, imbalance),
    feature("Trade-flow delta", formatters.compact.format(buyFlow - sellFlow), buyFlow - sellFlow),
    feature("Short return", `${formatters.pct.format(ret * 100)}%`, ret),
    feature("Spread", els.spread.textContent.replace("Spread ", ""), 0),
    feature("Bid depth", formatters.compact.format(bidDepth), bidDepth),
    feature("Ask depth", formatters.compact.format(askDepth), -askDepth),
  ].join("");
}

function feature(label, value, sign) {
  const cls = sign > 0 ? "up" : sign < 0 ? "down" : "";
  return `<div><span>${label}</span><strong class="${cls}">${value}</strong></div>`;
}

function setSignal(element, label, value) {
  element.textContent = label;
  element.className = `signal ${value > 0 ? "buy" : value < 0 ? "sell" : ""}`;
}

function depth(levels) {
  return levels.reduce((sum, [, size]) => sum + toNumber(size), 0);
}

function toNumber(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : 0;
}

function fmt(value) {
  return formatters.price.format(toNumber(value));
}

els.controls.addEventListener("submit", (event) => {
  event.preventDefault();
  state.category = els.category.value;
  state.symbol = els.symbol.value.trim().toUpperCase();
  state.interval = els.interval.value;
  state.prices = [];
  state.trades = [];
  state.bids = [];
  state.asks = [];
  state.lastTradeWindow = [];
  connect();
});

window.addEventListener("resize", drawPriceChart);
connect();
