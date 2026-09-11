//+----------------------------------------------------------------------+
//|                                              at-livecheck-direct.mq5 |
//|                                                       AutoTrader Web |
//+----------------------------------------------------------------------+
#property copyright "AutoTrader"
#property link      "http://stocksdeveloper.in/autotrader-web"
#property version   "1.00"
#property strict

/*********************************************************************
* READ ONLY check that the library can reach the server.
*
* at-selftest-direct.mq5 proves the library reads its own parsed data
* correctly, and deliberately never touches the network. This is the
* other half: it makes one real request and prints what came back.
*
* IT PLACES NOTHING. There is no placeOrder, no modifyOrder, no
* cancelOrder and no square off anywhere in this file. Margins is the
* lightest read there is -- one dataset, one request -- which is why it
* is the one used here.
*
* Attach it to any chart as an Expert Advisor. Not as an indicator and
* not in the Strategy Tester: MetaTrader refuses web requests from
* both, and autoTraderReady() says so rather than leaving you to guess.
*
* It needs, and names whichever is missing:
*
*   1. Your API key in Include/autotrader-http-config.mqh.
*
*   2. https://apix.stocksdeveloper.in added in
*      Tools -> Options -> Expert Advisors -> Allow WebRequest for
*      listed URL. Without it every request fails with error 4014.
*
*   3. An account that is logged in at your broker. A read reaches the
*      server either way, but only a logged in account has numbers.
*
* Set "Pseudo account" in the inputs to the account you want to read.
*********************************************************************/

#include <autotrader-http.mqh>

/*
* This file declares NO inputs of its own, on purpose.
*
* The library declares eight at global scope -- AT_ACCOUNT ("Pseudo
* account"), AT_EXCHANGE, AT_SYMBOL, AT_QUANTITY, AT_PRODUCT_TYPE,
* AT_DEBUG, AT_PRICE_PRECISION and AT_AVOID_REPEAT_ORDER_DELAY -- and
* every program that includes it inherits all eight. Adding another
* input for the account here would put a second account box directly
* beneath the library's one, where filling in only the first leaves
* this reading whatever the second still holds. The log then looks
* perfectly healthy while answering about a different account.
*
* AT_DEBUG is the library's own "Print Additional Logs" switch.
* AT_HTTP_DEBUG, in the config header, is the one the direct transport
* reads. They are separate variables, so tie them together rather than
* adding a second debug box too.
*/

/**
* Prints one labelled number, so a zero that means "nothing there" is
* still visible as an answer rather than as an absence.
*/
void show(const string label, const double value) {
	Print("    ", label, " = ", DoubleToString(value, 2));
}

int OnInit() {
	Print("==================================================");
	Print("AutoTrader live check -- READ ONLY");
	Print("account : ", AT_ACCOUNT);
	Print("base url: ", AT_BASE_URL);
	Print("==================================================");

	AT_HTTP_DEBUG = AT_DEBUG;

	/* Prints its own reason when the answer is no. */
	if(!autoTraderReady()) {
		Print("RESULT: NOT READY. The reason is printed above.");
		return(INIT_SUCCEEDED);
	}

	Print("autoTraderReady : yes");
	Print("");
	Print("Reading margins (one request, no order is placed)...");

	double equityFunds     = getMarginFundsEquity(AT_ACCOUNT);
	double equityUtilized  = getMarginUtilizedEquity(AT_ACCOUNT);
	double equityAvailable = getMarginAvailableEquity(AT_ACCOUNT);

	double commFunds       = getMarginFundsCommodity(AT_ACCOUNT);
	double commUtilized    = getMarginUtilizedCommodity(AT_ACCOUNT);
	double commAvailable   = getMarginAvailableCommodity(AT_ACCOUNT);

	double allFunds        = getMarginFundsAll(AT_ACCOUNT);
	double allUtilized     = getMarginUtilizedAll(AT_ACCOUNT);
	double allAvailable    = getMarginAvailableAll(AT_ACCOUNT);

	Print("  EQUITY");
	show("funds     ", equityFunds);
	show("utilized  ", equityUtilized);
	show("available ", equityAvailable);

	Print("  COMMODITY");
	show("funds     ", commFunds);
	show("utilized  ", commUtilized);
	show("available ", commAvailable);

	Print("  ALL");
	show("funds     ", allFunds);
	show("utilized  ", allUtilized);
	show("available ", allAvailable);

	Print("");

	/*
	* Equity, commodity and all carrying the SAME figure is normal and is
	* not a fault to report. Many brokers pool their segments, and the
	* "all" category is a copy of the pooled figure rather than a sum of
	* the others, because summing pooled segments would count the same
	* money twice.
	*/

	/*
	* A read that reached the server comes back with numbers. All nine
	* landing on exactly zero is far more likely to mean the request never
	* arrived, or that the account is not logged in at the broker, than an
	* account holding nothing at all -- so say which of the two this looks
	* like instead of printing nine zeroes and calling it a pass.
	*/
	bool anyValue = (equityFunds != 0 || equityUtilized != 0 || equityAvailable != 0
		|| commFunds != 0 || commUtilized != 0 || commAvailable != 0
		|| allFunds != 0 || allUtilized != 0 || allAvailable != 0);

	if(anyValue) {
		Print("RESULT: PASS -- the library reached the server and parsed a reply.");
	} else {
		Print("RESULT: every field came back zero.");
		Print("  Either the request did not go out, or this account is not");
		Print("  logged in at the broker. Turn on \"Print Additional Logs\" and");
		Print("  run it again: each request and reply is printed.");
	}

	Print("==================================================");

	return(INIT_SUCCEEDED);
}

void OnTick() {
	/* Nothing. This checks one read, at attach. */
}

void OnDeinit(const int reason) {
	Print("AutoTrader live check detached.");
}
