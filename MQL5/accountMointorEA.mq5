//+------------------------------------------------------------------+
//| AccountTradeNotifier.mq5                                         |
//| Notify account trade transactions to ServerChan                  |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"

input string InpServerChanMode = "turbo"; 
turbo = https://sctapi.ftqq.com/<SENDKEY>.send
// sc3   = https://<UID>.push.ft07.com/send/<SENDKEY>.send

input string InpSendKey = "PUT_YOUR_SENDKEY_HERE";
input string InpServerChanUID = "";   // only for sc3
input bool   InpNotifyDealAdd = true;
input bool   InpNotifyOrderAdd = true;
input bool   InpNotifyOrderUpdate = true;
input bool   InpNotifyOrderDelete = true;
input bool   InpNotifyPosition = true;
input bool   InpNotifyRequest = false;

input int    InpHttpTimeoutMs = 5000;

// 防止短时间内重复推送同一个 transaction
ulong g_last_deal = 0;
ulong g_last_order = 0;
datetime g_last_notify_time = 0;


//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
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
   if(!ShouldNotify(trans))
      return;

   string title = BuildTitle(trans, request, result);
   string body  = BuildBody(trans, request, result);

   bool ok = SendServerChan(title, body);

   if(!ok)
   {
      Print("ServerChan send failed. LastError=", GetLastError());
   }
}


//+------------------------------------------------------------------+
//| Decide whether to notify                                         |
//+------------------------------------------------------------------+
bool ShouldNotify(const MqlTradeTransaction& trans)
{
   switch(trans.type)
   {
      case TRADE_TRANSACTION_DEAL_ADD:
         if(!InpNotifyDealAdd)
            return false;

         // deal ticket 去重
         if(trans.deal != 0 && trans.deal == g_last_deal)
            return false;

         g_last_deal = trans.deal;
         return true;

      case TRADE_TRANSACTION_ORDER_ADD:
         if(!InpNotifyOrderAdd)
            return false;

         if(trans.order != 0 && trans.order == g_last_order)
            return false;

         g_last_order = trans.order;
         return true;

      case TRADE_TRANSACTION_ORDER_UPDATE:
         return InpNotifyOrderUpdate;

      case TRADE_TRANSACTION_ORDER_DELETE:
         return InpNotifyOrderDelete;

      case TRADE_TRANSACTION_POSITION:
         return InpNotifyPosition;

      case TRADE_TRANSACTION_REQUEST:
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
   const MqlTradeResult& result
)
{
   string account = IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN));
   string symbol = trans.symbol;

   if(symbol == "")
      symbol = request.symbol;

   string type_text = TransactionTypeToString(trans.type);

   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      return "MT5成交通知 " + account + " " + symbol + " " + DealTypeToString(trans.deal_type);
   }

   if(trans.type == TRADE_TRANSACTION_POSITION)
   {
      return "MT5持仓变化 " + account + " " + symbol;
   }

   return "MT5订单变化 " + account + " " + type_text + " " + symbol;
}


//+------------------------------------------------------------------+
//| Build notification body                                          |
//+------------------------------------------------------------------+
string BuildBody(
   const MqlTradeTransaction& trans,
   const MqlTradeRequest& request,
   const MqlTradeResult& result
)
{
   string body = "";

   body += "### MT5 账户交易事件\n\n";

   body += "- 账户: `" + IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN)) + "`\n";
   body += "- 服务器: `" + AccountInfoString(ACCOUNT_SERVER) + "`\n";
   body += "- 账户名称: `" + AccountInfoString(ACCOUNT_NAME) + "`\n";
   body += "- 时间: `" + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + "`\n\n";

   body += "### 事件信息\n\n";
   body += "- Transaction Type: `" + TransactionTypeToString(trans.type) + "`\n";
   body += "- Symbol: `" + trans.symbol + "`\n";
   body += "- Deal: `" + IntegerToString((int)trans.deal) + "`\n";
   body += "- Order: `" + IntegerToString((int)trans.order) + "`\n";
   body += "- Position: `" + IntegerToString((int)trans.position) + "`\n";
   body += "- Deal Type: `" + DealTypeToString(trans.deal_type) + "`\n";
   body += "- Order Type: `" + OrderTypeToString(trans.order_type) + "`\n";
   body += "- Order State: `" + OrderStateToString(trans.order_state) + "`\n";
   body += "- Volume: `" + DoubleToString(trans.volume, 2) + "`\n";
   body += "- Price: `" + DoubleToString(trans.price, DigitsForSymbol(trans.symbol)) + "`\n";
   body += "- SL: `" + DoubleToString(trans.price_sl, DigitsForSymbol(trans.symbol)) + "`\n";
   body += "- TP: `" + DoubleToString(trans.price_tp, DigitsForSymbol(trans.symbol)) + "`\n";

   if(trans.type == TRADE_TRANSACTION_REQUEST)
   {
      body += "\n### Request / Result\n\n";
      body += "- Request Action: `" + IntegerToString((int)request.action) + "`\n";
      body += "- Request Symbol: `" + request.symbol + "`\n";
      body += "- Request Volume: `" + DoubleToString(request.volume, 2) + "`\n";
      body += "- Request Price: `" + DoubleToString(request.price, DigitsForSymbol(request.symbol)) + "`\n";
      body += "- Result Retcode: `" + IntegerToString((int)result.retcode) + "`\n";
      body += "- Result Deal: `" + IntegerToString((int)result.deal) + "`\n";
      body += "- Result Order: `" + IntegerToString((int)result.order) + "`\n";
      body += "- Result Comment: `" + result.comment + "`\n";
   }

   return body;
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
         result += CharToString((ushort)c);
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