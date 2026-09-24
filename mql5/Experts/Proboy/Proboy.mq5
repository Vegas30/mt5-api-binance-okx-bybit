//+------------------------------------------------------------------+
//|                                           Proboy от тек цены.mq5
//|
//+------------------------------------------------------------------+
#property version   "1.00"
//+------------------------------------------------------------------+
//|                                                      ProjectName |
//|                                      Copyright 2020, CompanyName |
//|                                       http://www.companyname.net |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\SymbolInfo.mqh>

CTrade            o_trade;
CPositionInfo     o_position;
COrderInfo        o_order;
CSymbolInfo       o_symbol;
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
input double   Lots               = 1;
input int      TakeProfit         = 30;
input int      StopLoss           = 30;
input int      TP_first           = 30;
input double   Lot_first          = 1;
input int      TP_second          = 0;    // TP второго объёма; 0 = TakeProfit
input double   Lot_second         = 1;    // Второй частичный объём
//input int BarCount   = 3;
//input int LifeTimeMinutes = 20;
input int      Magic              = 123;
input int      Slippage           = 100;
input int      BarCount           = 3;
input int      Indent             = 100;   // Отступ
input double   timeout            = 60;         //время в минутах
input string   TradeComment       = "Test";
input int      Trail              = 0;
input int      TrailingStop       = 300;
input int      TrailingStep       = 100;
input bool     HalfClose          = true;
input bool     NonLoss            = false;
input int      NonLossProfitLevel = 40;
input int      MinProfitNoLoss    = 20;

input bool     InpTimeControl    = false;    // Для крипто Bybit: если false торговать круглосуточно
input int      InpStartHourMonday= 10;        // Start hour Monday
input int      InpEndHourFriday  = 19;       // End hour Friday
input uchar    InpStartHour      = 10;        // Start hour
input uchar    InpEndHour        = 18;       // End hour

input bool     UseMarketBreakoutFallback = true; // Если STOP-заявки запрещены, входить рынком при пробое

// Независимый фильтр объёма. По умолчанию выключен для сохранения старой логики.
input bool     UseVolumeFilter    = false;
input int      VolumeLookbackBars = 20;
input double   MinVolumeRatio     = 1.0;

double minprice,maxprice,SL_BUY,TP_BUY,SL_SELL,TP_SELL,Indent2,ormod1,ormod2,OT;
int send1,send2;

int dIndent;
double dLots;
int dTrailingStop;
int dTrailingStep;
int dTakeProfit;
int dStopLoss;
int countSellStop;
int countBuyStop;
int countBuy;
int countSell;
int countSellLimit;
int countBuyLimit;

// В режиме рыночного fallback уровни должны сохраняться между тиками.
// Иначе включение текущей свечи в GetMinPrice/GetMaxPrice делает пробой
// недостижимым: максимум растёт вместе с Ask, а минимум падает вместе с Bid.
double fallbackMinPrice = 0.0;
double fallbackMaxPrice = 0.0;
datetime fallbackLevelTime = 0;
bool fallbackLevelsReady = false;

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int OnInit()
  {
   dIndent = Indent;
   dLots = Lots;
   dTrailingStop = TrailingStop;
   dTrailingStep = TrailingStep;
   dTakeProfit   = TakeProfit;
   dStopLoss     = StopLoss;

   o_trade.SetExpertMagicNumber(Magic);
   o_trade.SetDeviationInPoints(Slippage);
   o_symbol.Name(Symbol());
   o_symbol.RefreshRates();

   if(!SymbolInfoInteger(_Symbol,SYMBOL_SELECT))
      SymbolSelect(_Symbol,true);

   countSellStop  = 0;
   countBuyStop   = 0;
   countBuy       = 0;
   countSell      = 0;
   countSellLimit = 0;
   countBuyLimit  = 0;



   // Bybit/Custom Symbol может разрешать только один конкретный режим
   // исполнения. CTrade умеет выбрать его из спецификации символа.
   o_trade.SetTypeFillingBySymbol(_Symbol);

   long order_mode = SymbolInfoInteger(_Symbol,SYMBOL_ORDER_MODE);
   Print("Bybit symbol ",_Symbol,
         ": order_mode=",order_mode,
         ", volume min/step/max=",
         DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),8),"/",
         DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP),8),"/",
         DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX),8),
         ", tick_size=",DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE),8),
         ", stops_level=",IntegerToString((int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)));

   if((order_mode & SYMBOL_ORDER_STOP)==0 && !UseMarketBreakoutFallback)
     {
      Print("На символе ",_Symbol," запрещены STOP-заявки. Включите UseMarketBreakoutFallback.");
      return(INIT_FAILED);
     }

   int second_target = TP_second > 0 ? TP_second : dTakeProfit;
   if(HalfClose && Lot_second > 0 && TP_first > 0 &&
      second_target > 0 && second_target <= TP_first)
      Print("HalfClose: TP_second должен быть больше TP_first, чтобы цели шли последовательно.");

   if(HalfClose && Lot_second > 0 && second_target > 0 &&
      dTakeProfit > 0 && dTakeProfit <= second_target)
      Print("HalfClose: TakeProfit должен быть больше TP_second, "
            "чтобы остаток закрывался после второго объёма.");

   if(HalfClose && Lot_second > 0 &&
      NormalizeVolumeForSymbol(Lot_first) + NormalizeVolumeForSymbol(Lot_second) >=
      NormalizeVolumeForSymbol(dLots))
      Print("HalfClose: сумма Lot_first и Lot_second должна быть меньше общего Lots, "
            "если после TP2 должен оставаться объём для закрытия/трейлинга.");


//if (o_symbol.Digits() == 3 || o_symbol.Digits() == 5)
//{
//   dIndent *= 10;
//}

   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {


  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(TimeControl())
     {
      PrintSpread();
      o_symbol.RefreshRates();
      //o_symbol.Refresh();

      //TotalOrders = CalculateAllPendingOrders();
      countSellStop = CountSellStop();
      countBuyStop  = CountBuyStop();
      countBuy      = CountBuy();
      countSell     = CountSell();
      countSellLimit= CountSellLimit();
      countBuyLimit = CountBuyLimit();

      closeLimitOrdersByTime();

      if(Bars(_Symbol,PERIOD_CURRENT) < BarCount + 2)
         return;

       OT = dIndent * o_symbol.Point(); // отступ в единицах цены
       minprice = NormalizePrice(GetMinPrice() - OT);
       maxprice = NormalizePrice(GetMaxPrice() + OT);
       bool volume_filter_passed = IsVolumeFilterPassed();



      // В Bybit Custom Symbol нередко разрешены только Market + SL + TP.
      // Тогда ждём фактический пробой на тике и входим рыночной заявкой.
      if(CanUseStopOrders())
        {
         if(countSell == 0 && countBuy == 0)
           {
             if(volume_filter_passed && o_symbol.Bid() <= minprice)
               {
                OpenSellMarket();
                return;
               }
             if(volume_filter_passed && o_symbol.Ask() >= maxprice)
               {
                OpenBuyMarket();
                return;
               }
             if(volume_filter_passed)
               {
                if(countSellStop == 0)
                   PlaceSellStop(minprice);
                if(countBuyStop == 0)
                   PlaceBuyStop(maxprice);
               }
           }
        }
      else
        {
         if(UseMarketBreakoutFallback && countBuy == 0 && countSell == 0)
           {
            // Аналог BuyStop/SellStop для символа, где STOP-заявки запрещены:
            // фиксируем уровни при начале цикла и ждём их пересечения.
            datetime now = TimeCurrent();
            if(!fallbackLevelsReady ||
               (timeout > 0.0 && now - fallbackLevelTime >= timeout * 60.0))
              {
               fallbackMinPrice = minprice;
               fallbackMaxPrice = maxprice;
               fallbackLevelTime = now;
               fallbackLevelsReady = true;
               Print("Fallback levels set: sell <= ",DoubleToString(fallbackMinPrice,_Digits),
                     ", buy >= ",DoubleToString(fallbackMaxPrice,_Digits),
                     ", timeout=",DoubleToString(timeout,1)," min");
              }

             if(volume_filter_passed && o_symbol.Ask() >= fallbackMaxPrice)
               {
                if(OpenBuyMarket())
                   ResetFallbackLevels();
                return;
               }
             if(volume_filter_passed && o_symbol.Bid() <= fallbackMinPrice)
               {
                if(OpenSellMarket())
                   ResetFallbackLevels();
               return;
              }
           }
        }

      if(countBuy > 0 || countSell > 0)
         ResetFallbackLevels();

      if((CountBuy() > 0 && CountSellStop() > 0) ||
         (CountSell() > 0 && CountBuyStop() > 0))
        {
         deleteSecondOrder();
        }
        
      if(countBuy == 0 && countSell == 0)
        {
         deleteLimitOrder();
        }

      if(!PositionSelect(_Symbol)) // если на текущем символе нет открытой позиции
         return; // то выходим
      Trailing(); // а если есть, то трейлим стоп лосс

      if(NonLoss)
        {
         if(!PositionSelect(_Symbol)) // если на текущем символе нет открытой позиции
           {
            return; // то выходим
           }
         nonLoss(); // а если есть, то трейлим стоп лосс
        }
       
       if(HalfClose)
        {
         if(!PositionSelect(_Symbol)) // если на текущем символе нет открытой позиции
           {
            return; // то выходим
           }
          halfClose(); // а если есть, то трейлим стоп лосс
        }

     }

  }

void ResetFallbackLevels()
  {
   fallbackMinPrice = 0.0;
   fallbackMaxPrice = 0.0;
   fallbackLevelTime = 0;
   fallbackLevelsReady = false;
  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsFillingTypeAllowed(string symbol, long fill_type)
  {
   long filling = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);

   return ((filling && fill_type) == fill_type);
  }

//+------------------------------------------------------------------+
//| Проверка возможностей символа                                   |
//+------------------------------------------------------------------+
bool CanUseStopOrders()
  {
   long mode = SymbolInfoInteger(_Symbol,SYMBOL_ORDER_MODE);
   return((mode & SYMBOL_ORDER_STOP) != 0);
  }

// Возвращает real volume, а для символов без real volume — tick volume.
long GetBarVolume(const int shift)
  {
   long real_volume = iRealVolume(_Symbol,PERIOD_CURRENT,shift);
   if(real_volume > 0)
      return(real_volume);

   return(iTickVolume(_Symbol,PERIOD_CURRENT,shift));
  }

// Сравнивает объём текущего бара со средним объёмом предыдущих закрытых баров.
bool IsVolumeFilterPassed()
  {
   if(!UseVolumeFilter)
      return(true);

   if(VolumeLookbackBars <= 0 || Bars(_Symbol,PERIOD_CURRENT) < VolumeLookbackBars + 1)
      return(false);

   long current_volume = GetBarVolume(0);
   if(current_volume <= 0)
      return(false);

   double previous_volume_sum = 0.0;
   int valid_bars = 0;
   for(int shift = 1; shift <= VolumeLookbackBars; shift++)
     {
      long volume = GetBarVolume(shift);
      if(volume <= 0)
         continue;

      previous_volume_sum += (double)volume;
      valid_bars++;
     }

   if(valid_bars <= 0)
      return(false);

   double previous_volume_average = previous_volume_sum / valid_bars;
   double min_ratio = MathMax(MinVolumeRatio,0.0);
   return((double)current_volume >= previous_volume_average * min_ratio);
  }

double NormalizePrice(double price)
  {
   double tick_size = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0.0)
      tick_size = o_symbol.Point();
   if(tick_size <= 0.0)
      return(NormalizeDouble(price,_Digits));

   return(NormalizeDouble(MathRound(price/tick_size)*tick_size,_Digits));
  }

double NormalizeVolumeForSymbol(double volume)
  {
   double min_volume  = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double max_volume  = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step_volume = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);

   if(volume <= 0.0)
      return(0.0);
   if(step_volume <= 0.0)
      step_volume = min_volume > 0.0 ? min_volume : 0.01;

   double normalized = MathFloor((volume + step_volume*0.000001)/step_volume)*step_volume;
   if(min_volume > 0.0 && normalized < min_volume)
     {
      Print("Объём ",DoubleToString(volume,8),
            " меньше минимального для ",_Symbol,". Использую минимум ",
            DoubleToString(min_volume,8));
      normalized = min_volume;
     }
   if(max_volume > 0.0 && normalized > max_volume)
      normalized = max_volume;

   return(NormalizeDouble(normalized,VolumeDigits(step_volume)));
  }

int VolumeDigits(double step)
  {
   int digits = 0;
   while(digits < 8 && MathAbs(step - NormalizeDouble(step,digits)) > 0.0000000001)
      digits++;
   return(digits);
  }

double MinTradeDistance()
  {
   double levels = MathMax((int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),
                           (int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL));
   return(levels * o_symbol.Point());
  }

bool TradeResultOk()
  {
   uint retcode = o_trade.ResultRetcode();
   return(retcode == TRADE_RETCODE_DONE ||
          retcode == TRADE_RETCODE_PLACED ||
          retcode == TRADE_RETCODE_DONE_PARTIAL);
  }

void PrintTradeError(string action)
  {
   Print(action," failed: retcode=",IntegerToString((int)o_trade.ResultRetcode()),
         " (",o_trade.ResultRetcodeDescription(),"), last_error=",GetLastError());
  }

void BuildBuyStops(double entry,double &sl,double &tp)
  {
   double distance = MinTradeDistance();
   sl = dStopLoss > 0 ? NormalizePrice(entry - MathMax(dStopLoss*o_symbol.Point(),distance)) : 0.0;
   // TakeProfit оставляем на позиции для остаточного объёма.
   // TP_first и TP_second обрабатываются вручную частичными закрытиями.
   bool use_full_tp = !HalfClose || dTakeProfit > 0;
   tp = use_full_tp && dTakeProfit > 0 ?
        NormalizePrice(entry + MathMax(dTakeProfit*o_symbol.Point(),distance)) : 0.0;
  }

void BuildSellStops(double entry,double &sl,double &tp)
  {
   double distance = MinTradeDistance();
   sl = dStopLoss > 0 ? NormalizePrice(entry + MathMax(dStopLoss*o_symbol.Point(),distance)) : 0.0;
   bool use_full_tp = !HalfClose || dTakeProfit > 0;
   tp = use_full_tp && dTakeProfit > 0 ?
        NormalizePrice(entry - MathMax(dTakeProfit*o_symbol.Point(),distance)) : 0.0;
  }

bool PlaceBuyStop(double entry)
  {
   double volume = NormalizeVolumeForSymbol(dLots);
   if(volume <= 0.0)
      return(false);
   double min_entry = o_symbol.Ask() + MinTradeDistance();
   if(entry <= min_entry)
      entry = NormalizePrice(min_entry + o_symbol.Point());
   double sl,tp;
   BuildBuyStops(entry,sl,tp);
   ResetLastError();
   bool sent = o_trade.BuyStop(volume,entry,_Symbol,sl,tp,ORDER_TIME_GTC,0,TradeComment);
   if(!sent || !TradeResultOk())
     {
      PrintTradeError("BuyStop");
      return(false);
     }
   return(true);
  }

bool PlaceSellStop(double entry)
  {
   double volume = NormalizeVolumeForSymbol(dLots);
   if(volume <= 0.0)
      return(false);
   double max_entry = o_symbol.Bid() - MinTradeDistance();
   if(entry >= max_entry)
      entry = NormalizePrice(max_entry - o_symbol.Point());
   double sl,tp;
   BuildSellStops(entry,sl,tp);
   ResetLastError();
   bool sent = o_trade.SellStop(volume,entry,_Symbol,sl,tp,ORDER_TIME_GTC,0,TradeComment);
   if(!sent || !TradeResultOk())
     {
      PrintTradeError("SellStop");
      return(false);
     }
   return(true);
  }

bool OpenBuyMarket()
  {
   double volume = NormalizeVolumeForSymbol(dLots);
   if(volume <= 0.0)
      return(false);
   double sl,tp;
   BuildBuyStops(o_symbol.Ask(),sl,tp);
   ResetLastError();
   bool sent = o_trade.Buy(volume,_Symbol,0.0,sl,tp,TradeComment);
   if(!sent || !TradeResultOk())
     {
      PrintTradeError("Market Buy");
      return(false);
     }
   Print("Market Buy: volume=",DoubleToString(volume,8),
         ", ask=",DoubleToString(o_symbol.Ask(),_Digits),
         ", sl=",DoubleToString(sl,_Digits),
         ", tp=",DoubleToString(tp,_Digits));
   return(true);
  }

bool OpenSellMarket()
  {
   double volume = NormalizeVolumeForSymbol(dLots);
   if(volume <= 0.0)
      return(false);
   double sl,tp;
   BuildSellStops(o_symbol.Bid(),sl,tp);
   ResetLastError();
   bool sent = o_trade.Sell(volume,_Symbol,0.0,sl,tp,TradeComment);
   if(!sent || !TradeResultOk())
     {
      PrintTradeError("Market Sell");
      return(false);
     }
   Print("Market Sell: volume=",DoubleToString(volume,8),
         ", bid=",DoubleToString(o_symbol.Bid(),_Digits),
         ", sl=",DoubleToString(sl,_Digits),
         ", tp=",DoubleToString(tp,_Digits));
   return(true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void PrintSpread()
  {
   long symb_spread = SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
   Comment("Spread: ",IntegerToString((int)symb_spread),"\n");
  }

//+------------------------------------------------------------------+
double GetMinPrice()
  {

   double dLow=1.0e100,
   dPrice;

   for(int i=0; i<=BarCount; i++)
     {
      dPrice=iLow(_Symbol,PERIOD_CURRENT,i);
      if(dPrice>0.0 && dPrice<dLow)
         dLow=dPrice;
     }

   return(dLow);
  }
//+------------------------------------------------------------------+
double GetMaxPrice()
  {

   double dHigh=0,
   dPrice;

   for(int i=0; i<=BarCount; i++)
     {
      dPrice=iHigh(_Symbol,PERIOD_CURRENT,i);
      if(dPrice>0.0 && dPrice>dHigh)
         dHigh=dPrice;
     }

   return(dHigh);
  }
//+------------------------------------------------------------------+
//| Считаем открытые позиции на покупку                              |
//+------------------------------------------------------------------+
int CountBuy(void)
  {
   int count=0;
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      if(o_position.SelectByIndex(i))
        {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && o_position.Magic() == Magic)
           {
            if(o_position.PositionType() == POSITION_TYPE_BUY)
              {
               count++;
              }
           }
        }
     }
   return(count);
  }
//+------------------------------------------------------------------+
//| Считаем открытые позиции на продажу                              |
//+------------------------------------------------------------------+
int CountSell(void)
  {
   int count=0;
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      if(o_position.SelectByIndex(i))
        {
         if(o_position.Symbol()==o_symbol.Name() && o_position.Magic() == Magic)
           {
            if(o_position.PositionType() == POSITION_TYPE_SELL)
              {
               count++;
              }
           }
        }
     }
   return(count);
  }
//+------------------------------------------------------------------+
//| Считаем открытые ордера на покупку                               |
//+------------------------------------------------------------------+
int CountBuyStop(void)
  {
   int count=0;
   for(int i=OrdersTotal()-1; i>=0; i--)
     {
      if(o_order.SelectByIndex(i))
        {
         if(o_order.Symbol()==o_symbol.Name() && o_order.Magic()==Magic)
           {
            if(o_order.OrderType()==ORDER_TYPE_BUY_STOP)
              {
               count++;
              }
           }

        }
     }
   return(count);
  }
//+------------------------------------------------------------------+
//| Считаем открытые ордера на продажу                               |
//+------------------------------------------------------------------+
int CountSellStop(void)
  {
   int count=0;
   for(int i=OrdersTotal()-1; i>=0; i--)
     {
      if(o_order.SelectByIndex(i))
        {
         if(o_order.Symbol()==o_symbol.Name() && o_order.Magic()==Magic)
           {
            if(o_order.OrderType()==ORDER_TYPE_SELL_STOP)
              {
               count++;
              }
           }

        }
     }
   return(count);
  }
  
//+------------------------------------------------------------------+
//| Считаем открытые ордера StopLimit                                |
//+------------------------------------------------------------------+
int CountSellLimit(void)
  {
   int count=0;
   for(int i=OrdersTotal()-1; i>=0; i--)
     {
      if(o_order.SelectByIndex(i))
        {
         if(o_order.Symbol()==o_symbol.Name() && o_order.Magic()==Magic)
           {
            if(o_order.OrderType()==ORDER_TYPE_SELL_LIMIT)
              {
               count++;
              }
           }

        }
     }
   return(count);
  }
//+------------------------------------------------------------------+
//| Считаем открытые ордера BuyLimit                                 |
//+------------------------------------------------------------------+
int CountBuyLimit(void)
  {
   int count=0;
   for(int i=OrdersTotal()-1; i>=0; i--)
     {
      if(o_order.SelectByIndex(i))
        {
         if(o_order.Symbol()==o_symbol.Name() && o_order.Magic()==Magic)
           {
            if(o_order.OrderType()==ORDER_TYPE_BUY_LIMIT)
              {
               count++;
              }
           }

        }
     }
   return(count);
  }
//int CalculateAllPendingOrders(void)
//  {
//   int count=0;
//   for(int i=OrdersTotal()-1; i>=0; i--) // returns the number of current orders
//      if(o_order.SelectByIndex(i))     // selects the pending order by index for further access to its properties
//         count++;
////---
//   return(count);
//  }
//
//void CalculateAllPendingOrders(int &count_buy_stops,int &count_sell_stops)
//  {
//   count_buy_stops   = 0;
//   count_sell_stops  = 0;
//   for(int i=OrdersTotal()-1; i>=0; i--) // returns the number of current orders
//      if(o_order.SelectByIndex(i))     // selects the pending order by index for further access to its properties
//         if(o_order.Symbol()==o_symbol.Name() && o_order.Magic()==Magic)
//           {
//            if(o_order.OrderType()==ORDER_TYPE_BUY_STOP)
//               count_buy_stops++;
//            else
//               if(o_order.OrderType()==ORDER_TYPE_SELL_STOP)
//                  count_sell_stops++;
//           }
//  }
//+------------------------------------------------------------------+
//| Трейлинг стоп                                                    |
//+------------------------------------------------------------------+
bool Trailing()
  {
   switch(Trail)
     {
      case 1:
         for(int i=PositionsTotal()-1; i>=0; i--) // запустим цикл и переберём все открытые позиции
           {
            if(o_position.SelectByIndex(i)) // если выбрана позиция
              {
               if(o_position.Symbol()==Symbol()) // и если символ совпадает
                 {
                  if(o_position.Profit()<0.0) // проверяем позицию и если её профит меньше нуля,
                     continue; // то начинаем всё заново
                  //---
                  if(o_position.PositionType()==POSITION_TYPE_BUY) // если выбранная позиция BUY
                    {
                      double new_sl_buy = NormalizePrice(o_position.PriceCurrent()-dTrailingStop*o_symbol.Point());
                      if((o_position.StopLoss() == 0.0 ||
                          new_sl_buy > o_position.StopLoss() + dTrailingStep*o_symbol.Point()) &&
                         new_sl_buy < o_symbol.Bid())
                        {
                         if(!o_trade.PositionModify(o_position.Ticket(),new_sl_buy,o_position.TakeProfit()) ||
                            !TradeResultOk())
                            PrintTradeError("Trailing Buy");
                       }
                    }
                  else
                     if(o_position.PositionType()==POSITION_TYPE_SELL) // если выбранная позиция SELL
                       {
                         double new_sl_sell = NormalizePrice(o_position.PriceCurrent()+dTrailingStop*o_symbol.Point());
                         if((o_position.StopLoss() == 0.0 ||
                             new_sl_sell < o_position.StopLoss() - dTrailingStep*o_symbol.Point()) &&
                            new_sl_sell > o_symbol.Ask())
                           {
                            if(!o_trade.PositionModify(o_position.Ticket(),new_sl_sell,o_position.TakeProfit()) ||
                               !TradeResultOk())
                               PrintTradeError("Trailing Sell");
                          }
                       }
                 }
              }
           }
         return(true);
         break;

      case 2:
         for(int i=PositionsTotal()-1; i>=0; i--)
           {
            if(o_position.SelectByIndex(i))
              {
               if(o_position.Symbol() == o_symbol.Name() && o_position.Magic() == Magic)
                 {
                  if(o_position.PositionType() == POSITION_TYPE_BUY)
                    {
                     if(o_symbol.Bid() - o_position.PriceOpen() > dTrailingStop * o_symbol.Point())
                       {
                         double new_sl_buy = NormalizePrice(o_position.PriceCurrent()-dTrailingStop*o_symbol.Point());
                         if((o_position.StopLoss() == 0.0 ||
                             o_position.StopLoss() < new_sl_buy - dTrailingStep*o_symbol.Point()) &&
                            new_sl_buy < o_symbol.Bid())
                           {
                            if(!o_trade.PositionModify(o_position.Ticket(),new_sl_buy,o_position.TakeProfit()) ||
                               !TradeResultOk())
                               PrintTradeError("Trailing Buy");
                          }
                       }
                    }
                  if(o_position.PositionType() == POSITION_TYPE_SELL)
                    {
                     if((o_position.PriceOpen() - o_symbol.Ask()) > (dTrailingStop*o_symbol.Point()))
                       {
                         double new_sl_sell = NormalizePrice(o_position.PriceCurrent()+dTrailingStop*o_symbol.Point());
                         if((o_position.StopLoss() == 0.0 ||
                             o_position.StopLoss() > new_sl_sell + dTrailingStep*o_symbol.Point()) &&
                            new_sl_sell > o_symbol.Ask())
                           {
                            if(!o_trade.PositionModify(o_position.Ticket(),new_sl_sell,o_position.TakeProfit()) ||
                               !TradeResultOk())
                               PrintTradeError("Trailing Sell");
                          }
                       }
                    }
                 }
              }
           }
         return(true);
         break;

      default:
         break;
     }
   return(true);
  }




//+------------------------------------------------------------------+
//| Перевод в безубыток                                              |
//+------------------------------------------------------------------+
void nonLoss()
  {
// MQL4 | функция перевода Stop Loss сделки в безубыток | ENSED Team, http://ensed.org
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      if(!o_position.SelectByIndex(i))
         continue;
      if(o_position.Magic() != Magic)
         continue;
      if(o_position.Symbol() != o_symbol.Name())
         continue;
      // ---
      if(o_position.PositionType() == POSITION_TYPE_BUY)
         if(o_position.StopLoss() < o_position.PriceOpen() || o_position.StopLoss() == 0)
            if(NormalizeDouble(o_symbol.Bid() - o_position.PriceOpen(), _Digits) >= NormalizeDouble(NonLossProfitLevel * o_symbol.Point(), _Digits))
              {
               if(!o_trade.PositionModify(o_position.Ticket(),
                                          NormalizePrice(o_position.PriceOpen() + MinProfitNoLoss * o_symbol.Point()),
                                          o_position.TakeProfit()) || !TradeResultOk())
                  PrintTradeError("Break-even Buy");
              }

      // ---
      if(o_position.PositionType() == POSITION_TYPE_SELL)
         if(o_position.StopLoss() > o_position.PriceOpen() || o_position.StopLoss() == 0)

            if(NormalizeDouble(o_position.PriceOpen() - o_symbol.Ask(), _Digits) >= NormalizeDouble(NonLossProfitLevel * o_symbol.Point(), _Digits))
              {
               if(!o_trade.PositionModify(o_position.Ticket(),
                                          NormalizePrice(o_position.PriceOpen() - MinProfitNoLoss * o_symbol.Point()),
                                          o_position.TakeProfit()) || !TradeResultOk())
                  PrintTradeError("Break-even Sell");
              }

     }


  }
//+------------------------------------------------------------------+
//| Частичное закрытие по TP1 и TP2 без LIMIT-заявки                 |
//| У Bybit Custom Symbol обычно разрешены только Market + SL + TP. |
//+------------------------------------------------------------------+
void halfClose()
  {
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      if(!o_position.SelectByIndex(i))
         continue;
      if(o_position.Magic() != Magic)
         continue;
      if(o_position.Symbol() != o_symbol.Name())
         continue;

      double close_volume = NormalizeVolumeForSymbol(Lot_first);
      double second_close_volume = NormalizeVolumeForSymbol(Lot_second);
      double position_volume = o_position.Volume();
      double volume_step = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
      if(volume_step <= 0.0)
         volume_step = 0.01;

      // После первого частичного закрытия объём позиции становится меньше
      // исходного Lots. Это не даёт закрывать Lot_first повторно на каждом тике.
      double initial_volume = NormalizeVolumeForSymbol(dLots);
      bool first_closed = close_volume <= 0.0 ||
                          position_volume + volume_step*0.5 < initial_volume;

      bool tp1_reached = false;
      if(TP_first > 0)
        {
         double target_distance = TP_first * o_symbol.Point();
         if(o_position.PositionType() == POSITION_TYPE_BUY)
            tp1_reached = o_symbol.Bid() >= NormalizePrice(o_position.PriceOpen() + target_distance);
         else
            if(o_position.PositionType() == POSITION_TYPE_SELL)
               tp1_reached = o_symbol.Ask() <= NormalizePrice(o_position.PriceOpen() - target_distance);
        }

      if(!first_closed && tp1_reached && close_volume < position_volume)
        {
         ResetLastError();
         bool closed = o_trade.PositionClosePartial(o_position.Ticket(),close_volume,Slippage);
         if(!closed || !TradeResultOk())
            PrintTradeError("Partial close TP1");
         continue;
        }

      if(!first_closed)
         continue;

      // Второй объём закрывается по TP_second.
      // Если TP_second не задан, для совместимости используется TakeProfit.
      int second_target = TP_second > 0 ? TP_second : dTakeProfit;
      if(second_target <= 0)
         continue;

      bool second_closed = second_close_volume <= 0.0 ||
                           position_volume + volume_step*0.5 <=
                           initial_volume - close_volume - second_close_volume;
      if(second_closed)
         continue;

      bool tp2_reached = false;
      double tp2_distance = second_target * o_symbol.Point();
      if(o_position.PositionType() == POSITION_TYPE_BUY)
         tp2_reached = o_symbol.Bid() >= NormalizePrice(o_position.PriceOpen() + tp2_distance);
      else
         if(o_position.PositionType() == POSITION_TYPE_SELL)
            tp2_reached = o_symbol.Ask() <= NormalizePrice(o_position.PriceOpen() - tp2_distance);

      if(!tp2_reached)
         continue;

      if(second_close_volume > 0.0 &&
         position_volume > second_close_volume + volume_step*0.5)
        {
         ResetLastError();
         bool closed = o_trade.PositionClosePartial(o_position.Ticket(),
                                                     second_close_volume,
                                                     Slippage);
         if(!closed || !TradeResultOk())
            PrintTradeError("Partial close TP2");
        }
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void closeLimitOrdersByTime()
  {
   if(CountSellStop() > 0)
     {
      for(int i = OrdersTotal() -1; i>=0; i--)
        {
         if(o_order.SelectByIndex(i))
           {
            if(o_order.Symbol() == o_symbol.Name() &&
               o_order.Magic() == Magic && o_order.OrderType() == ORDER_TYPE_SELL_STOP)
               if(TimeCurrent() - o_order.TimeSetup() >= timeout*60)
                  if(!o_trade.OrderDelete(o_order.Ticket()))
                     Print("Ошибка закрытия ордера на продажу!");
           }
        }
     }

   if(CountBuyStop() > 0)
     {
      for(int i = OrdersTotal() -1; i>=0; i--)
        {
         if(o_order.SelectByIndex(i))
           {
            if(o_order.Symbol() == o_symbol.Name() &&
               o_order.Magic() == Magic && o_order.OrderType() == ORDER_TYPE_BUY_STOP)
               if(TimeCurrent() - o_order.TimeSetup() >= timeout*60)
                  if(!o_trade.OrderDelete(o_order.Ticket()))
                     Print("Ошибка закрытия ордера на покупку!");
           }
        }
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void deleteSecondOrder()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(o_order.SelectByIndex(i))
        {
         if(o_order.Symbol() == o_symbol.Name() && o_order.Magic() == Magic)
            {
            if(o_order.OrderType() == ORDER_TYPE_SELL_STOP)
               {
               o_trade.OrderDelete(o_order.Ticket());
               }
            if(o_order.OrderType() == ORDER_TYPE_BUY_STOP)
               {
               o_trade.OrderDelete(o_order.Ticket());
               }
            }
        }

     }
  }
  
void deleteLimitOrder()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(o_order.SelectByIndex(i))
        {
         if(o_order.Symbol() == o_symbol.Name() && o_order.Magic() == Magic)
            {
            if(o_order.OrderType() == ORDER_TYPE_BUY_LIMIT)
               {
               o_trade.OrderDelete(o_order.Ticket());
               }
            if(o_order.OrderType() == ORDER_TYPE_SELL_LIMIT)
               {
               o_trade.OrderDelete(o_order.Ticket());
               }
            }
        }

     }
  }
//+------------------------------------------------------------------+
//| TimeControl                                                      |
//+------------------------------------------------------------------+
bool TimeControl(void)
  {
   if(!InpTimeControl)
      return(true);
   MqlDateTime STimeCurrent;
   datetime time_current=TimeCurrent();
   if(time_current==D'1970.01.01 00:00')
      return(false);
   TimeToStruct(time_current,STimeCurrent);
//--- Monday, Friday
   if(STimeCurrent.day_of_week==1 && STimeCurrent.hour<InpStartHourMonday)
      return(false);
   if(STimeCurrent.day_of_week==5 && STimeCurrent.hour>=InpEndHourFriday)
      return(false);
//---
   if(InpStartHour<InpEndHour) // intraday time interval
     {
      /*
      Example:
      input uchar    InpStartHour      = 5;        // Start hour
      input uchar    InpEndHour        = 10;       // End hour
      0  1  2  3  4  5  6  7  8  9  10 11 12 13 14 15 16 17 18 19 20 21 22 23 0  1  2  3  4  5  6  7  8  9  10 11 12 13 14 15
      _  _  _  _  _  +  +  +  +  +  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  +  +  +  +  +  _  _  _  _  _  _
      */
      if(STimeCurrent.hour>=InpStartHour && STimeCurrent.hour<InpEndHour)
         return(true);
     }
   else
      if(InpStartHour>InpEndHour) // time interval with the transition in a day
        {
         /*
         Example:
         input uchar    InpStartHour      = 10;       // Start hour
         input uchar    InpEndHour        = 5;        // End hour
         0  1  2  3  4  5  6  7  8  9  10 11 12 13 14 15 16 17 18 19 20 21 22 23 0  1  2  3  4  5  6  7  8  9  10 11 12 13 14 15
         _  _  _  _  _  _  _  _  _  _  +  +  +  +  +  +  +  +  +  +  +  +  +  +  +  +  +  +  +  _  _  _  _  _  +  +  +  +  +  +
         */
         if(STimeCurrent.hour>=InpStartHour || STimeCurrent.hour<InpEndHour)
            return(true);
        }
      else
         return(false);
//---
   return(false);
  }
//+------------------------------------------------------------------+
