//+------------------------------------------------------------------+
//| AccountTradeNotifier.mq5                                         |
//| Notify account trade transactions to ServerChan                  |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"

input string InpServerChanMode = "turbo"; 
// turbo = https://sctapi.ftqq.com/<SENDKEY>.send
// sc3   = https://<UID>.push.ft07.com/send/<SENDKEY>.send

input string InpSendKey = "PUT_YOUR_SENDKEY_HERE";
input string InpServerChanUID = "";   // only for sc3
input bool   InpNotifyDealAdd = true;             // 成交通知
input bool   InpNotifyPositionStopChange = true;  // 持仓 SL/TP 添加或修改通知

input bool   InpNotifyPendingOrderAdd = false;     // 挂单通知
input bool   InpNotifyOrderStopChange = false;     // 挂单 SL/TP 添加或修改通知

input bool   InpNotifyRequest = false;            // 请求回报调试通知

input int    InpHttpTimeoutMs = 5000;

// 防止短时间内重复推送同一个 transaction
ulong g_last_deal = 0;
ulong g_last_order = 0;

enum ENUM_NOTIFY_EVENT_KIND
{
   NOTIFY_EVENT_NONE = 0,
   NOTIFY_EVENT_DEAL_ADD,
   NOTIFY_EVENT_PENDING_ORDER_ADD,
   NOTIFY_EVENT_ORDER_STOPS_CHANGED,
   NOTIFY_EVENT_POSITION_STOPS_CHANGED,
   NOTIFY_EVENT_REQUEST
};

struct StopSnapshot
{
   ulong ticket;
   double sl;
   double tp;
};

struct NotifyContext
{
   ENUM_NOTIFY_EVENT_KIND kind;
   bool sl_changed;
   bool tp_changed;
   double old_sl;
   double new_sl;
   double old_tp;
   double new_tp;
};

StopSnapshot g_order_stop_snapshots[];
StopSnapshot g_position_stop_snapshots[];


//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   LoadInitialStopSnapshots();
   Print("AccountTradeNotifier initialized. Account=", AccountInfoInteger(ACCOUNT_LOGIN));
   return INIT_SUCCEEDED;
}


//+------------------------------------------------------------------+
//| Trade transaction handler                                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(
   const MqlTradeTransaction& trans,
   const MqlTradeRequest& request,
   const MqlTradeResult& result
)
{
   NotifyContext context;

   if(!ShouldNotify(trans, context))
      return;

   string title = BuildTitle(trans, request, result, context);
   string body  = BuildBody(trans, request, result, context);

   bool ok = SendServerChan(title, body);

   if(!ok)
   {
      Print("ServerChan send failed. LastError=", GetLastError());
   }
}


//+------------------------------------------------------------------+
//| Decide whether to notify                                         |
//+------------------------------------------------------------------+
bool ShouldNotify(const MqlTradeTransaction& trans, NotifyContext& context)
{
   ResetNotifyContext(context);

   switch(trans.type)
   {
      case TRADE_TRANSACTION_DEAL_ADD:
         CachePositionStopSnapshot(trans.position);

         if(!InpNotifyDealAdd)
            return false;

         if(!IsTradeDealType(trans.deal_type))
            return false;

         // deal ticket 去重
         if(trans.deal != 0 && trans.deal == g_last_deal)
            return false;

         g_last_deal = trans.deal;
         context.kind = NOTIFY_EVENT_DEAL_ADD;
         return true;

      case TRADE_TRANSACTION_ORDER_ADD:
         if(!IsPendingOrderTransaction(trans))
            return false;

         CacheOrderStopSnapshot(trans);

         if(!InpNotifyPendingOrderAdd)
            return false;

         if(trans.order != 0 && trans.order == g_last_order)
            return false;

         g_last_order = trans.order;
         context.kind = NOTIFY_EVENT_PENDING_ORDER_ADD;
         return true;

      case TRADE_TRANSACTION_ORDER_UPDATE:
         if(!IsPendingOrderTransaction(trans))
            return false;

         if(!DetectOrderStopChange(trans, context))
            return false;

         context.kind = NOTIFY_EVENT_ORDER_STOPS_CHANGED;
         return InpNotifyOrderStopChange;

      case TRADE_TRANSACTION_ORDER_DELETE:
         RemoveStopSnapshot(g_order_stop_snapshots, trans.order);
         return false;

      case TRADE_TRANSACTION_POSITION:
         if(!DetectPositionStopChange(trans, context))
            return false;

         context.kind = NOTIFY_EVENT_POSITION_STOPS_CHANGED;
         return InpNotifyPositionStopChange;

      case TRADE_TRANSACTION_REQUEST:
         context.kind = NOTIFY_EVENT_REQUEST;
         return InpNotifyRequest;

      default:
         return false;
   }
}


//+------------------------------------------------------------------+
//| Build notification title                                         |
//+------------------------------------------------------------------+
string BuildTitle(
   const MqlTradeTransaction& trans,
   const MqlTradeRequest& request,
   const MqlTradeResult& result,
   const NotifyContext& context
)
{
   string account = IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN));
   string symbol = trans.symbol;

   if(symbol == "")
      symbol = request.symbol;

   string type_text = TransactionTypeToString(trans.type);

   if(context.kind == NOTIFY_EVENT_DEAL_ADD)
   {
      return "MT5成交通知 " + account + " " + symbol + " " + DealTypeToString(trans.deal_type);
   }

   if(context.kind == NOTIFY_EVENT_PENDING_ORDER_ADD)
   {
      return "MT5挂单通知 " + account + " " + symbol + " " + OrderTypeToString(trans.order_type);
   }

   if(context.kind == NOTIFY_EVENT_ORDER_STOPS_CHANGED)
   {
      return "MT5挂单止盈止损变化 " + account + " " + symbol + " " + OrderTypeToString(trans.order_type);
   }

   if(context.kind == NOTIFY_EVENT_POSITION_STOPS_CHANGED)
   {
      return "MT5持仓止盈止损变化 " + account + " " + symbol;
   }

   return "MT5订单变化 " + account + " " + type_text + " " + symbol;
}


//+------------------------------------------------------------------+
//| Build notification body                                          |
//+------------------------------------------------------------------+
string BuildBody(
   const MqlTradeTransaction& trans,
   const MqlTradeRequest& request,
   const MqlTradeResult& result,
   const NotifyContext& context
)
{
   string body = "";
   string symbol = trans.symbol;

   if(symbol == "")
      symbol = request.symbol;

   int digits = DigitsForSymbol(symbol);

   body += "### MT5 账户交易事件\n\n";

   body += "- 账户: `" + IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN)) + "`\n";
   body += "- 服务器: `" + AccountInfoString(ACCOUNT_SERVER) + "`\n";
   body += "- 账户名称: `" + AccountInfoString(ACCOUNT_NAME) + "`\n";
   body += "- 时间: `" + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + "`\n\n";

   body += "### 事件信息\n\n";
   body += "- 业务事件: `" + NotifyEventKindToString(context.kind) + "`\n";
   body += "- Transaction Type: `" + TransactionTypeToString(trans.type) + "`\n";
   body += "- Symbol: `" + symbol + "`\n";
   body += "- Deal: `" + IntegerToString((long)trans.deal) + "`\n";
   body += "- Order: `" + IntegerToString((long)trans.order) + "`\n";
   body += "- Position: `" + IntegerToString((long)trans.position) + "`\n";
   body += "- Deal Type: `" + DealTypeToString(trans.deal_type) + "`\n";
   body += "- Order Type: `" + OrderTypeToString(trans.order_type) + "`\n";
   body += "- Order State: `" + OrderStateToString(trans.order_state) + "`\n";
   body += "- Volume: `" + DoubleToString(trans.volume, 2) + "`\n";
   body += "- Price: `" + DoubleToString(trans.price, digits) + "`\n";
   body += "- SL: `" + FormatStopPrice(trans.price_sl, digits) + "`\n";
   body += "- TP: `" + FormatStopPrice(trans.price_tp, digits) + "`\n";

   if(context.kind == NOTIFY_EVENT_ORDER_STOPS_CHANGED || context.kind == NOTIFY_EVENT_POSITION_STOPS_CHANGED)
   {
      body += "\n### 止盈止损变化\n\n";

      if(context.sl_changed)
      {
         body += "- SL: `" + FormatStopPrice(context.old_sl, digits) + "` -> `" + FormatStopPrice(context.new_sl, digits) + "`\n";
      }

      if(context.tp_changed)
      {
         body += "- TP: `" + FormatStopPrice(context.old_tp, digits) + "` -> `" + FormatStopPrice(context.new_tp, digits) + "`\n";
      }
   }

   if(trans.type == TRADE_TRANSACTION_REQUEST)
   {
      body += "\n### Request / Result\n\n";
      body += "- Request Action: `" + IntegerToString((int)request.action) + "`\n";
      body += "- Request Symbol: `" + request.symbol + "`\n";
      body += "- Request Volume: `" + DoubleToString(request.volume, 2) + "`\n";
      body += "- Request Price: `" + DoubleToString(request.price, DigitsForSymbol(request.symbol)) + "`\n";
      body += "- Result Retcode: `" + IntegerToString((int)result.retcode) + "`\n";
      body += "- Result Deal: `" + IntegerToString((long)result.deal) + "`\n";
      body += "- Result Order: `" + IntegerToString((long)result.order) + "`\n";
      body += "- Result Comment: `" + result.comment + "`\n";
   }

   return body;
}


//+------------------------------------------------------------------+
//| Notification helpers                                             |
//+------------------------------------------------------------------+
void ResetNotifyContext(NotifyContext& context)
{
   context.kind = NOTIFY_EVENT_NONE;
   context.sl_changed = false;
   context.tp_changed = false;
   context.old_sl = 0.0;
   context.new_sl = 0.0;
   context.old_tp = 0.0;
   context.new_tp = 0.0;
}


void LoadInitialStopSnapshots()
{
   ArrayResize(g_order_stop_snapshots, 0);
   ArrayResize(g_position_stop_snapshots, 0);

   int orders_total = OrdersTotal();
   for(int i = 0; i < orders_total; i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;

      ENUM_ORDER_TYPE order_type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(!IsPendingOrderType(order_type))
         continue;

      SaveStopSnapshot(
         g_order_stop_snapshots,
         ticket,
         OrderGetDouble(ORDER_SL),
         OrderGetDouble(ORDER_TP)
      );
   }

   int positions_total = PositionsTotal();
   for(int i = 0; i < positions_total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      SaveStopSnapshot(
         g_position_stop_snapshots,
         ticket,
         PositionGetDouble(POSITION_SL),
         PositionGetDouble(POSITION_TP)
      );
   }

   Print(
      "Loaded SL/TP snapshots. Orders=",
      ArraySize(g_order_stop_snapshots),
      ", Positions=",
      ArraySize(g_position_stop_snapshots)
   );
}


bool IsTradeDealType(ENUM_DEAL_TYPE type)
{
   return type == DEAL_TYPE_BUY || type == DEAL_TYPE_SELL;
}


bool IsPendingOrderType(ENUM_ORDER_TYPE type)
{
   switch(type)
   {
      case ORDER_TYPE_BUY_LIMIT:
      case ORDER_TYPE_SELL_LIMIT:
      case ORDER_TYPE_BUY_STOP:
      case ORDER_TYPE_SELL_STOP:
      case ORDER_TYPE_BUY_STOP_LIMIT:
      case ORDER_TYPE_SELL_STOP_LIMIT:
         return true;

      default:
         return false;
   }
}


bool IsFinalOrderState(ENUM_ORDER_STATE state)
{
   return state == ORDER_STATE_CANCELED ||
          state == ORDER_STATE_FILLED ||
          state == ORDER_STATE_REJECTED ||
          state == ORDER_STATE_EXPIRED;
}


bool IsPendingOrderTransaction(const MqlTradeTransaction& trans)
{
   ENUM_ORDER_TYPE order_type = trans.order_type;

   if(trans.order != 0 && OrderSelect(trans.order))
      order_type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);

   return IsPendingOrderType(order_type);
}


void CacheOrderStopSnapshot(const MqlTradeTransaction& trans)
{
   if(trans.order == 0)
      return;

   double sl = trans.price_sl;
   double tp = trans.price_tp;

   if(OrderSelect(trans.order))
   {
      sl = OrderGetDouble(ORDER_SL);
      tp = OrderGetDouble(ORDER_TP);
   }

   SaveStopSnapshot(g_order_stop_snapshots, trans.order, sl, tp);
}


void CachePositionStopSnapshot(ulong position_ticket)
{
   if(position_ticket == 0)
      return;

   if(PositionSelectByTicket(position_ticket))
   {
      SaveStopSnapshot(
         g_position_stop_snapshots,
         position_ticket,
         PositionGetDouble(POSITION_SL),
         PositionGetDouble(POSITION_TP)
      );
   }
   else
   {
      RemoveStopSnapshot(g_position_stop_snapshots, position_ticket);
   }
}


bool DetectOrderStopChange(const MqlTradeTransaction& trans, NotifyContext& context)
{
   if(trans.order == 0)
      return false;

   string symbol = trans.symbol;
   double sl = trans.price_sl;
   double tp = trans.price_tp;

   if(OrderSelect(trans.order))
   {
      symbol = OrderGetString(ORDER_SYMBOL);
      sl = OrderGetDouble(ORDER_SL);
      tp = OrderGetDouble(ORDER_TP);
   }
   else if(IsFinalOrderState(trans.order_state))
   {
      RemoveStopSnapshot(g_order_stop_snapshots, trans.order);
      return false;
   }

   return DetectStopChange(g_order_stop_snapshots, trans.order, symbol, sl, tp, context);
}


bool DetectPositionStopChange(const MqlTradeTransaction& trans, NotifyContext& context)
{
   if(trans.position == 0)
      return false;

   string symbol = trans.symbol;
   double sl = trans.price_sl;
   double tp = trans.price_tp;

   if(PositionSelectByTicket(trans.position))
   {
      symbol = PositionGetString(POSITION_SYMBOL);
      sl = PositionGetDouble(POSITION_SL);
      tp = PositionGetDouble(POSITION_TP);
   }
   else
   {
      RemoveStopSnapshot(g_position_stop_snapshots, trans.position);
      return false;
   }

   return DetectStopChange(g_position_stop_snapshots, trans.position, symbol, sl, tp, context);
}


bool DetectStopChange(
   StopSnapshot& snapshots[],
   ulong ticket,
   string symbol,
   double sl,
   double tp,
   NotifyContext& context
)
{
   int index = FindStopSnapshot(snapshots, ticket);

   if(index < 0)
   {
      SaveStopSnapshot(snapshots, ticket, sl, tp);
      return false;
   }

   context.old_sl = snapshots[index].sl;
   context.new_sl = sl;
   context.old_tp = snapshots[index].tp;
   context.new_tp = tp;
   context.sl_changed = PriceChanged(context.old_sl, context.new_sl, symbol);
   context.tp_changed = PriceChanged(context.old_tp, context.new_tp, symbol);

   SaveStopSnapshot(snapshots, ticket, sl, tp);

   return context.sl_changed || context.tp_changed;
}


int FindStopSnapshot(StopSnapshot& snapshots[], ulong ticket)
{
   for(int i = 0; i < ArraySize(snapshots); i++)
   {
      if(snapshots[i].ticket == ticket)
         return i;
   }

   return -1;
}


void SaveStopSnapshot(StopSnapshot& snapshots[], ulong ticket, double sl, double tp)
{
   if(ticket == 0)
      return;

   int index = FindStopSnapshot(snapshots, ticket);

   if(index < 0)
   {
      int size = ArraySize(snapshots);
      ArrayResize(snapshots, size + 1);
      index = size;
      snapshots[index].ticket = ticket;
   }

   snapshots[index].sl = sl;
   snapshots[index].tp = tp;
}


void RemoveStopSnapshot(StopSnapshot& snapshots[], ulong ticket)
{
   if(ticket == 0)
      return;

   int index = FindStopSnapshot(snapshots, ticket);
   if(index < 0)
      return;

   int last = ArraySize(snapshots) - 1;
   if(index != last)
      snapshots[index] = snapshots[last];

   ArrayResize(snapshots, last);
}


bool PriceChanged(double previous, double current, string symbol)
{
   double point = 0.0;

   if(symbol != "")
      point = SymbolInfoDouble(symbol, SYMBOL_POINT);

   if(point <= 0.0)
      point = MathPow(10.0, -DigitsForSymbol(symbol));

   return MathAbs(previous - current) >= point * 0.5;
}


string FormatStopPrice(double price, int digits)
{
   if(price <= 0.0)
      return "未设置";

   return DoubleToString(price, digits);
}


string NotifyEventKindToString(ENUM_NOTIFY_EVENT_KIND kind)
{
   switch(kind)
   {
      case NOTIFY_EVENT_DEAL_ADD:
         return "成交";
      case NOTIFY_EVENT_PENDING_ORDER_ADD:
         return "挂单";
      case NOTIFY_EVENT_ORDER_STOPS_CHANGED:
         return "挂单止盈止损变化";
      case NOTIFY_EVENT_POSITION_STOPS_CHANGED:
         return "持仓止盈止损变化";
      case NOTIFY_EVENT_REQUEST:
         return "请求回报";
      default:
         return "未知";
   }
}


//+------------------------------------------------------------------+
//| Send ServerChan notification                                     |
//+------------------------------------------------------------------+
bool SendServerChan(string title, string desp)
{
   if(InpSendKey == "" || InpSendKey == "PUT_YOUR_SENDKEY_HERE")
   {
      Print("ServerChan SendKey is empty.");
      return false;
   }

   string url = "";

   if(StringCompare(InpServerChanMode, "turbo", false) == 0)
   {
      url = "https://sctapi.ftqq.com/" + InpSendKey + ".send";
   }
   else if(StringCompare(InpServerChanMode, "sc3", false) == 0)
   {
      if(InpServerChanUID == "")
      {
         Print("ServerChan UID is empty for sc3 mode.");
         return false;
      }

      url = "https://" + InpServerChanUID + ".push.ft07.com/send/" + InpSendKey + ".send";
   }
   else
   {
      Print("Unknown ServerChan mode: ", InpServerChanMode);
      return false;
   }

   string headers = "Content-Type: application/x-www-form-urlencoded\r\n";
   string payload = "title=" + UrlEncode(title) + "&desp=" + UrlEncode(desp);

   char post_data[];
   StringToCharArray(payload, post_data, 0, WHOLE_ARRAY, CP_UTF8);

   // StringToCharArray 会带终止符，需要去掉最后一个 0
   int size = ArraySize(post_data);
   if(size > 0)
      ArrayResize(post_data, size - 1);

   char result_data[];
   string result_headers;

   ResetLastError();

   int status = WebRequest(
      "POST",
      url,
      headers,
      InpHttpTimeoutMs,
      post_data,
      result_data,
      result_headers
   );

   if(status == -1)
   {
      Print("WebRequest failed. Error=", GetLastError(), ", url=", url);
      return false;
   }

   string response = CharArrayToString(result_data, 0, WHOLE_ARRAY, CP_UTF8);

   Print("ServerChan status=", status, ", response=", response);

   return status >= 200 && status < 300;
}


//+------------------------------------------------------------------+
//| URL encode                                                       |
//+------------------------------------------------------------------+
string UrlEncode(const string source)
{
   uchar bytes[];
   StringToCharArray(source, bytes, 0, WHOLE_ARRAY, CP_UTF8);

   string result = "";

   for(int i = 0; i < ArraySize(bytes); i++)
   {
      uchar c = bytes[i];

      if(c == 0)
         break;

      bool safe =
         (c >= 'A' && c <= 'Z') ||
         (c >= 'a' && c <= 'z') ||
         (c >= '0' && c <= '9') ||
         c == '-' || c == '_' || c == '.' || c == '~';

      if(safe)
      {
         result += CharToString(c);
      }
      else if(c == ' ')
      {
         result += "+";
      }
      else
      {
         result += "%" + StringFormat("%02X", c);
      }
   }

   return result;
}


//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
int DigitsForSymbol(string symbol)
{
   if(symbol == "")
      return 5;

   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   if(digits <= 0)
      return 5;

   return digits;
}


string TransactionTypeToString(ENUM_TRADE_TRANSACTION_TYPE type)
{
   switch(type)
   {
      case TRADE_TRANSACTION_ORDER_ADD:
         return "ORDER_ADD";
      case TRADE_TRANSACTION_ORDER_UPDATE:
         return "ORDER_UPDATE";
      case TRADE_TRANSACTION_ORDER_DELETE:
         return "ORDER_DELETE";
      case TRADE_TRANSACTION_DEAL_ADD:
         return "DEAL_ADD";
      case TRADE_TRANSACTION_DEAL_UPDATE:
         return "DEAL_UPDATE";
      case TRADE_TRANSACTION_DEAL_DELETE:
         return "DEAL_DELETE";
      case TRADE_TRANSACTION_HISTORY_ADD:
         return "HISTORY_ADD";
      case TRADE_TRANSACTION_HISTORY_UPDATE:
         return "HISTORY_UPDATE";
      case TRADE_TRANSACTION_HISTORY_DELETE:
         return "HISTORY_DELETE";
      case TRADE_TRANSACTION_POSITION:
         return "POSITION";
      case TRADE_TRANSACTION_REQUEST:
         return "REQUEST";
      default:
         return "UNKNOWN";
   }
}


string DealTypeToString(ENUM_DEAL_TYPE type)
{
   switch(type)
   {
      case DEAL_TYPE_BUY:
         return "BUY";
      case DEAL_TYPE_SELL:
         return "SELL";
      case DEAL_TYPE_BALANCE:
         return "BALANCE";
      case DEAL_TYPE_CREDIT:
         return "CREDIT";
      case DEAL_TYPE_CHARGE:
         return "CHARGE";
      case DEAL_TYPE_CORRECTION:
         return "CORRECTION";
      case DEAL_TYPE_BONUS:
         return "BONUS";
      case DEAL_TYPE_COMMISSION:
         return "COMMISSION";
      case DEAL_TYPE_COMMISSION_DAILY:
         return "COMMISSION_DAILY";
      case DEAL_TYPE_COMMISSION_MONTHLY:
         return "COMMISSION_MONTHLY";
      case DEAL_TYPE_INTEREST:
         return "INTEREST";
      case DEAL_TYPE_BUY_CANCELED:
         return "BUY_CANCELED";
      case DEAL_TYPE_SELL_CANCELED:
         return "SELL_CANCELED";
      default:
         return "UNKNOWN";
   }
}


string OrderTypeToString(ENUM_ORDER_TYPE type)
{
   switch(type)
   {
      case ORDER_TYPE_BUY:
         return "BUY";
      case ORDER_TYPE_SELL:
         return "SELL";
      case ORDER_TYPE_BUY_LIMIT:
         return "BUY_LIMIT";
      case ORDER_TYPE_SELL_LIMIT:
         return "SELL_LIMIT";
      case ORDER_TYPE_BUY_STOP:
         return "BUY_STOP";
      case ORDER_TYPE_SELL_STOP:
         return "SELL_STOP";
      case ORDER_TYPE_BUY_STOP_LIMIT:
         return "BUY_STOP_LIMIT";
      case ORDER_TYPE_SELL_STOP_LIMIT:
         return "SELL_STOP_LIMIT";
      case ORDER_TYPE_CLOSE_BY:
         return "CLOSE_BY";
      default:
         return "UNKNOWN";
   }
}


string OrderStateToString(ENUM_ORDER_STATE state)
{
   switch(state)
   {
      case ORDER_STATE_STARTED:
         return "STARTED";
      case ORDER_STATE_PLACED:
         return "PLACED";
      case ORDER_STATE_CANCELED:
         return "CANCELED";
      case ORDER_STATE_PARTIAL:
         return "PARTIAL";
      case ORDER_STATE_FILLED:
         return "FILLED";
      case ORDER_STATE_REJECTED:
         return "REJECTED";
      case ORDER_STATE_EXPIRED:
         return "EXPIRED";
      case ORDER_STATE_REQUEST_ADD:
         return "REQUEST_ADD";
      case ORDER_STATE_REQUEST_MODIFY:
         return "REQUEST_MODIFY";
      case ORDER_STATE_REQUEST_CANCEL:
         return "REQUEST_CANCEL";
      default:
         return "UNKNOWN";
   }
}
