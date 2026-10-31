//+----------------------------------------------------------------------+
//|                                             at-optioncheck-direct.mq5 |
//|                                                       AutoTrader Web |
//+----------------------------------------------------------------------+
#property copyright "AutoTrader"
#property link      "https://stocksdeveloper.in/"
#property version   "1.00"
#property description "Maintainer's check: option contract lookups against the live server. Places NO order."

/*********************************************************************
* Asks the live server which option contract a few strike rules pick,
* using the API key in autotrader-http-config.mqh.
*
* It calls resolveOptionContract() ONLY. It never calls an order
* function, so nothing reaches a broker. The account must be live in
* AutoTrader Web (the lookup checks it, like a portfolio read).
*
* Not part of the library download.
*********************************************************************/

#include <autotrader-http.mqh>

input string CHECK_ACCOUNT = "";	// Pseudo account (must be live)

int checkRun = 0;

int checkFailed = 0;

void checkLookup(const string label, const Exchange exchange, const string underlying,
	const string optionType, const string strike, const string expiry, const bool expectOk) {

	checkRun++;

	bool ok = resolveOptionContract(CHECK_ACCOUNT, exchange, underlying, optionType,
		strike, expiry, 0);

	if(ok == expectOk) {
		Print("  ok   ", label, ok
			? " -> " + atOptionSymbol + " lot " + IntegerToString(atOptionLotSize) +
				" strike " + DoubleToString(atOptionStrike, 2) + " expiry " + atOptionExpiry
			: " refused: " + atHttpMessage);
	} else {
		checkFailed++;
		Print("  FAIL ", label, " expected ", expectOk ? "a contract" : "a refusal",
			", got ", ok ? atOptionSymbol : atHttpMessage);
	}
}

void OnStart() {
	if(!autoTraderReady()) {
		Print("FAIL -- library not ready (API key or WebRequest address)");
		return;
	}

	if(CHECK_ACCOUNT == "") {
		Print("FAIL -- set \"Pseudo account\" in the inputs to a live account");
		return;
	}

	Print("Option lookups for ", CHECK_ACCOUNT, " (no orders are placed)");

	checkLookup("NIFTY CE ATM weekly", NSE, "NIFTY", "CE", "ATM", "weekly", true);
	checkLookup("NIFTY PE OTM1 weekly", NSE, "NIFTY", "PE", "OTM1", "weekly", true);
	checkLookup("BANKNIFTY CE ATM+1 monthly", NSE, "BANKNIFTY", "CE", "ATM+1", "monthly", true);
	checkLookup("blank strike and expiry mean ATM weekly", NSE, "NIFTY", "CE", "", "", true);
	checkLookup("unknown strike rule", NSE, "NIFTY", "CE", "ATM++", "weekly", false);
	checkLookup("SENSEX on NSE", NSE, "SENSEX", "CE", "ATM", "weekly", false);

	Print("");

	if(checkFailed == 0) {
		Print("PASS -- ", checkRun, " lookups, 0 failures");
	} else {
		Print("FAIL -- ", checkRun, " lookups, ", checkFailed, " failures");
	}
}
