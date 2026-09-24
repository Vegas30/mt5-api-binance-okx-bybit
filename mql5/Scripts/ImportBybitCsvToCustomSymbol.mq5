#property strict
#property script_show_inputs

input string CsvFileName = "BTCUSDT_M1.csv";
input string CustomSymbolName = "BYBIT_BTCUSDT";
input string CustomSymbolPath = "Crypto\\Bybit";

// 0 means detect from the decimal precision present in the CSV prices.
input int PriceDigits = 0;
input double PricePoint = 0.0;
input double ContractSize = 1.0;
input bool AutoDetectCurrencies = true;
input string CurrencyBase = "";
input string CurrencyProfit = "";
input string CurrencyMargin = "";

// 0 means detect the quantity precision from the CSV volume column.
// The exchange's exact order quantity step should be preferred when known.
input double VolumeMin = 0.0;
input double VolumeMax = 1000.0;
input double VolumeStep = 0.0;
input double InitialBidAskSpreadPoints = 1.0;
input bool ClearExistingHistory = true;

void OnStart()
{
   string symbol = CustomSymbolName;
   if(!CustomSymbolCreate(symbol, CustomSymbolPath))
   {
      int err = GetLastError();
      if(err != 5304)
      {
         Print("CustomSymbolCreate failed: ", err);
         return;
      }
      ResetLastError();
   }

   int handle = FileOpen(CsvFileName, FILE_READ | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(handle == INVALID_HANDLE)
   {
      Print("FileOpen failed. Put CSV into Terminal Common\\Files. Error: ", GetLastError());
      return;
   }

   SkipHeader(handle);

   MqlRates rates[];
   ArrayResize(rates, 0);
   int detectedPriceDigits = 0;
   int detectedVolumeDigits = 0;

   while(!FileIsEnding(handle))
   {
      string dateValue = FileReadString(handle);
      if(dateValue == "")
         break;

      string timeValue = FileReadString(handle);
      string openValue = FileReadString(handle);
      string highValue = FileReadString(handle);
      string lowValue = FileReadString(handle);
      string closeValue = FileReadString(handle);
      double open = StringToDouble(openValue);
      double high = StringToDouble(highValue);
      double low = StringToDouble(lowValue);
      double close = StringToDouble(closeValue);
      long tickVolume = (long)StringToInteger(FileReadString(handle));
      string volumeValue = FileReadString(handle);
      double sourceVolume = StringToDouble(volumeValue);
      int spread = (int)StringToInteger(FileReadString(handle));
      datetime barTime = StringToTime(dateValue + " " + timeValue);

      if(barTime <= 0 || high < low || high < open || high < close || low > open || low > close)
      {
         Print("Skipping invalid CSV row at ", dateValue, " ", timeValue);
         continue;
      }

      if(ArraySize(rates) > 0 && barTime <= rates[ArraySize(rates) - 1].time)
      {
         Print("CSV must be strictly chronological. Skipping duplicate/out-of-order row at ",
               dateValue, " ", timeValue);
         continue;
      }

      int next = ArraySize(rates);
      ArrayResize(rates, next + 1);
      rates[next].time = barTime;
      rates[next].open = open;
      rates[next].high = high;
      rates[next].low = low;
      rates[next].close = close;
      // MqlRates.real_volume is an integer, while Bybit's base-asset volume
      // is often fractional. Preserve it as faithfully as MT5 allows.
      rates[next].tick_volume = (long)MathMax(tickVolume, 0);
      rates[next].real_volume = (long)MathMax(MathRound(sourceVolume), 0);
      rates[next].spread = MathMax(spread, (int)InitialBidAskSpreadPoints);

      detectedPriceDigits = MathMax(detectedPriceDigits, DecimalPlaces(openValue));
      detectedPriceDigits = MathMax(detectedPriceDigits, DecimalPlaces(highValue));
      detectedPriceDigits = MathMax(detectedPriceDigits, DecimalPlaces(lowValue));
      detectedPriceDigits = MathMax(detectedPriceDigits, DecimalPlaces(closeValue));
      detectedVolumeDigits = MathMax(detectedVolumeDigits, DecimalPlaces(volumeValue));
   }

   FileClose(handle);

   int count = ArraySize(rates);
   if(count == 0)
   {
      Print("No rates loaded from CSV");
      return;
   }

   int resolvedPriceDigits = PriceDigits;
   double resolvedPricePoint = PricePoint;
   if(resolvedPriceDigits <= 0)
      resolvedPriceDigits = MathMin(MathMax(detectedPriceDigits, 0), 8);
   if(resolvedPricePoint <= 0.0)
      resolvedPricePoint = MathPow(10.0, -resolvedPriceDigits);

   double resolvedVolumeStep = VolumeStep;
   if(resolvedVolumeStep <= 0.0)
   {
      int volumeDigits = MathMin(MathMax(detectedVolumeDigits, 0), 8);
      resolvedVolumeStep = MathPow(10.0, -volumeDigits);
      if(resolvedVolumeStep <= 0.0)
         resolvedVolumeStep = 0.001;
   }
   double resolvedVolumeMin = VolumeMin > 0.0 ? VolumeMin : resolvedVolumeStep;
   double resolvedVolumeMax = VolumeMax > 0.0 ? VolumeMax : 1000.0;

   ConfigureSymbol(symbol, resolvedPriceDigits, resolvedPricePoint,
                   resolvedVolumeMin, resolvedVolumeMax, resolvedVolumeStep);

   if(ClearExistingHistory)
   {
      int deletedRates = CustomRatesDelete(symbol, 0, LONG_MAX);
      int deletedTicks = CustomTicksDelete(symbol, 0, LONG_MAX);
      if(deletedRates < 0 || deletedTicks < 0)
      {
         Print("Could not clear existing history. Rates error/result=", deletedRates,
               ", ticks error/result=", deletedTicks);
         return;
      }
   }

   int imported = CustomRatesReplace(symbol, rates[0].time, rates[count - 1].time, rates);
   if(imported < 0)
   {
      Print("CustomRatesReplace failed: ", GetLastError());
      return;
   }

   MqlTick ticks[1];
   ticks[0].time = rates[count - 1].time;
   ticks[0].bid = rates[count - 1].close;
   ticks[0].ask = rates[count - 1].close + InitialBidAskSpreadPoints * resolvedPricePoint;
   ticks[0].last = rates[count - 1].close;
   ticks[0].volume = 1;
   CustomTicksAdd(symbol, ticks);

   SymbolSelect(symbol, true);
   Print(
      "Imported ", imported,
      " bars into ", symbol,
      ". Base=", SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE),
      ", Profit=", SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT),
      ", Margin=", SymbolInfoString(symbol, SYMBOL_CURRENCY_MARGIN),
      ", ContractSize=", DoubleToString(SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE), 8),
      ", Digits=", IntegerToString((int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)),
      ", Point=", DoubleToString(SymbolInfoDouble(symbol, SYMBOL_POINT), 8),
      ", VolumeStep=", DoubleToString(SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP), 8)
   );
}

void ConfigureSymbol(string symbol, int priceDigits, double pricePoint,
                     double volumeMin, double volumeMax, double volumeStep)
{
   string baseCurrency = CurrencyBase;
   string profitCurrency = CurrencyProfit;
   string marginCurrency = CurrencyMargin;

   if(AutoDetectCurrencies)
   {
      InferCryptoCurrencies(symbol, baseCurrency, profitCurrency, marginCurrency);
   }

   CustomSymbolSetString(symbol, SYMBOL_DESCRIPTION, "Bybit imported crypto data");
   CustomSymbolSetString(symbol, SYMBOL_BASIS, "Bybit");
   CustomSymbolSetString(symbol, SYMBOL_CURRENCY_BASE, baseCurrency);
   CustomSymbolSetString(symbol, SYMBOL_CURRENCY_PROFIT, profitCurrency);
   CustomSymbolSetString(symbol, SYMBOL_CURRENCY_MARGIN, marginCurrency);

   CustomSymbolSetInteger(symbol, SYMBOL_DIGITS, priceDigits);
   CustomSymbolSetDouble(symbol, SYMBOL_POINT, pricePoint);
   CustomSymbolSetDouble(symbol, SYMBOL_TRADE_TICK_SIZE, pricePoint);
   CustomSymbolSetDouble(symbol, SYMBOL_TRADE_TICK_VALUE, ContractSize * pricePoint);
   CustomSymbolSetDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE, ContractSize);

   CustomSymbolSetDouble(symbol, SYMBOL_VOLUME_MIN, volumeMin);
   CustomSymbolSetDouble(symbol, SYMBOL_VOLUME_MAX, volumeMax);
   CustomSymbolSetDouble(symbol, SYMBOL_VOLUME_STEP, volumeStep);
   CustomSymbolSetDouble(symbol, SYMBOL_VOLUME_LIMIT, volumeMax);

   CustomSymbolSetInteger(symbol, SYMBOL_TRADE_MODE, SYMBOL_TRADE_MODE_FULL);
   CustomSymbolSetInteger(symbol, SYMBOL_TRADE_CALC_MODE, SYMBOL_CALC_MODE_CFD);
   CustomSymbolSetInteger(symbol, SYMBOL_ORDER_MODE, SYMBOL_ORDER_MARKET | SYMBOL_ORDER_SL | SYMBOL_ORDER_TP);
   CustomSymbolSetInteger(symbol, SYMBOL_FILLING_MODE, SYMBOL_FILLING_FOK | SYMBOL_FILLING_IOC);
   CustomSymbolSetInteger(symbol, SYMBOL_EXPIRATION_MODE, SYMBOL_EXPIRATION_GTC);
   CustomSymbolSetInteger(symbol, SYMBOL_SPREAD, (int)InitialBidAskSpreadPoints);
   CustomSymbolSetInteger(symbol, SYMBOL_SPREAD_FLOAT, false);

   // Crypto markets quote and trade seven days a week. Explicitly setting
   // sessions also repairs symbols previously created with empty weekends.
   datetime sessionFrom = D'1970.01.01 00:00:00';
   datetime sessionTo = D'1970.01.01 23:59:59';
   for(int day = SUNDAY; day <= SATURDAY; day++)
   {
      CustomSymbolSetSessionQuote(symbol, (ENUM_DAY_OF_WEEK)day, 0, sessionFrom, sessionTo);
      CustomSymbolSetSessionTrade(symbol, (ENUM_DAY_OF_WEEK)day, 0, sessionFrom, sessionTo);
   }
}

void InferCryptoCurrencies(string symbol, string &baseCurrency, string &profitCurrency, string &marginCurrency)
{
   string pair = symbol;
   int underscore = -1;
   for(int i = 0; i < StringLen(pair); i++)
   {
      if(StringGetCharacter(pair, i) == '_')
         underscore = i;
   }
   if(underscore >= 0)
      pair = StringSubstr(pair, underscore + 1);

   StringToUpper(pair);
   RemoveSuffix(pair, ".PERP");
   RemoveSuffix(pair, ".P");
   RemoveSuffix(pair, "_PERP");
   RemoveSuffix(pair, "_P");
   RemoveSuffix(pair, "-PERP");
   RemoveSuffix(pair, "-P");
   StringReplace(pair, "/", "");
   StringReplace(pair, "-", "");
   StringReplace(pair, ".", "");
   StringToUpper(pair);

   string quote = "";
   if(StringLen(pair) > 4 && StringSubstr(pair, StringLen(pair) - 4) == "USDT")
   {
      quote = "USD";
      baseCurrency = StringSubstr(pair, 0, StringLen(pair) - 4);
   }
   else if(StringLen(pair) > 4 && StringSubstr(pair, StringLen(pair) - 4) == "USDC")
   {
      quote = "USD";
      baseCurrency = StringSubstr(pair, 0, StringLen(pair) - 4);
   }
   else if(StringLen(pair) > 3)
   {
      quote = StringSubstr(pair, StringLen(pair) - 3);
      baseCurrency = StringSubstr(pair, 0, StringLen(pair) - 3);
   }

   if(baseCurrency == "")
      baseCurrency = "ETH";
   if(profitCurrency == "")
      profitCurrency = quote;
   if(profitCurrency == "USDT" || profitCurrency == "USDC")
      profitCurrency = "USD";
   if(profitCurrency == "")
      profitCurrency = "USD";
   if(marginCurrency == "")
      marginCurrency = profitCurrency;
   if(marginCurrency == "USDT" || marginCurrency == "USDC")
      marginCurrency = "USD";
}

void RemoveSuffix(string &value, string suffix)
{
   if(StringLen(value) >= StringLen(suffix) &&
      StringSubstr(value, StringLen(value) - StringLen(suffix)) == suffix)
   {
      value = StringSubstr(value, 0, StringLen(value) - StringLen(suffix));
   }
}

int DecimalPlaces(string value)
{
   int dot = StringFind(value, ".");
   if(dot < 0)
      return 0;
   int places = StringLen(value) - dot - 1;
   while(places > 0 && StringGetCharacter(value, dot + places) == '0')
      places--;
   return places;
}

void SkipHeader(int handle)
{
   for(int i = 0; i < 9 && !FileIsEnding(handle); i++)
      FileReadString(handle);
}
