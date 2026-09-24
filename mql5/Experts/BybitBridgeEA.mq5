#property strict

input string BridgeUrl = "http://127.0.0.1:8765/signal";
input string BybitSymbol = "BTCUSDT";
input string Category = "linear";
input double Quantity = 0.001;
input int FastMAPeriod = 12;
input int SlowMAPeriod = 26;

int fast_ma_handle;
int slow_ma_handle;
datetime last_bar_time = 0;

int OnInit()
{
   fast_ma_handle = iMA(_Symbol, _Period, FastMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   slow_ma_handle = iMA(_Symbol, _Period, SlowMAPeriod, 0, MODE_EMA, PRICE_CLOSE);

   if(fast_ma_handle == INVALID_HANDLE || slow_ma_handle == INVALID_HANDLE)
   {
      Print("Failed to create MA handles");
      return INIT_FAILED;
   }

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(fast_ma_handle != INVALID_HANDLE)
      IndicatorRelease(fast_ma_handle);
   if(slow_ma_handle != INVALID_HANDLE)
      IndicatorRelease(slow_ma_handle);
}

void OnTick()
{
   datetime bar_time = iTime(_Symbol, _Period, 0);
   if(bar_time == last_bar_time)
      return;
   last_bar_time = bar_time;

   double fast[3];
   double slow[3];
   if(CopyBuffer(fast_ma_handle, 0, 0, 3, fast) != 3)
      return;
   if(CopyBuffer(slow_ma_handle, 0, 0, 3, slow) != 3)
      return;

   bool crossed_up = fast[1] <= slow[1] && fast[0] > slow[0];
   bool crossed_down = fast[1] >= slow[1] && fast[0] < slow[0];

   if(crossed_up)
      SendSignal("Buy");
   if(crossed_down)
      SendSignal("Sell");
}

void SendSignal(string side)
{
   string body = StringFormat(
      "{\"symbol\":\"%s\",\"category\":\"%s\",\"side\":\"%s\",\"qty\":%.8f,\"orderType\":\"Market\"}",
      BybitSymbol,
      Category,
      side,
      Quantity
   );

   char post[];
   char result[];
   string headers = "Content-Type: application/json\r\n";
   string response_headers;

   int bytes = StringToCharArray(body, post, 0, WHOLE_ARRAY, CP_UTF8);
   if(bytes > 0)
      ArrayResize(post, bytes - 1);
   ResetLastError();
   int status = WebRequest(
      "POST",
      BridgeUrl,
      headers,
      5000,
      post,
      result,
      response_headers
   );

   if(status == -1)
   {
      Print("WebRequest failed. Error: ", GetLastError());
      return;
   }

   string response = CharArrayToString(result, 0, -1, CP_UTF8);
   Print("Bridge response: ", status, " ", response);
}
