#property script_show_inputs

#include <autotrader-http.mqh>

input string ACCOUNTS = "ACC1,ACC2";	// Accounts, separated by commas

void OnStart()
  {
	string accounts[];
	StringSplit(ACCOUNTS, ',', accounts);

	// Ask once which contract "ATM weekly" means. This places no order.
	if(!resolveOptionContract(accounts[0], NSE, "NIFTY",
		"CE", "ATM", "weekly", 0)) {
		Print("No contract: ", atHttpMessage);
		return;
	}

	// Keep it: by the time you square off, ATM may be another strike.
	string symbol = atOptionSymbol;
	Exchange exchange = atOptionExchange;
	int quantity = 1 * atOptionLotSize;

	Print("Contract: ", symbol);

	// Every account gets the same contract.
	for(int i = 0; i < ArraySize(accounts); i++) {
		placeOrder(accounts[i], exchange, symbol,
			BUY, MARKET, INTRADAY, quantity, 0, 0, true);
	}

	// This example waits one minute, then squares off that same contract.
	Sleep(60000);

	for(int i = 0; i < ArraySize(accounts); i++) {
		squareOffPosition(accounts[i], "NET", "MIS", exchange, symbol);
	}
  }
