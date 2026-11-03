#property script_show_inputs

#include <autotrader-http.mqh>

void OnStart()
  {
	string p = atFindPosition(AT_ACCOUNT, "NET", "MIS",
		EnumToString(AT_EXCHANGE), AT_SYMBOL);

	if(atFound(p)) {
		Print("Net Qty before: ", atText(p, "NETQUANTITY"));
	}

	if(squareOffPosition(AT_ACCOUNT, "NET", "MIS", AT_EXCHANGE, AT_SYMBOL)) {
		Print("Square-off sent.");
	}
  }
