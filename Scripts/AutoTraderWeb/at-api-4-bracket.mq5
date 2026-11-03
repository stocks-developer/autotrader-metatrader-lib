#property script_show_inputs

#include <autotrader-http.mqh>

input double TARGET = 20;		// Target, in rupees from entry
input double STOPLOSS = 10;		// Stoploss, in rupees from entry
input double TRAILING = 0;		// Trailing stoploss step (0 = off)

void OnStart()
  {
	string orderId = placeAutoTraderBracketOrder(AT_ACCOUNT,
		AT_EXCHANGE, AT_SYMBOL, BUY, MARKET, AT_QUANTITY,
		0, 0, TARGET, STOPLOSS, TRAILING, true);

	Print("Bracket order id: ", orderId);
  }
