/******************************************************************************
*
* Self test for the direct (HTTP) library.
*
* Feeds the library a portfolio it has already parsed, rather than asking the
* server for one, and checks that every lookup returns the field it was asked
* for. Nothing here touches the network, so it needs no API key, no allowlist
* entry and no broker account, and it places no orders.
*
* The rows below carry the server's real column order for each dataset, so a
* lookup that reads the wrong column shows up as a wrong VALUE rather than as a
* blank that could equally mean "you do not hold that stock".
*
* Attach it to any chart as a Script and read the Experts tab.
*
******************************************************************************/

#property script_show_inputs
#property strict

#include <autotrader-http.mqh>

int atTestsRun = 0;
int atTestsFailed = 0;

/**
* Checks one text answer and records the outcome.
*/
void atCheck(const string label, const string actual, const string expected) {
	atTestsRun++;

	if(actual == expected) {
		Print("  ok   ", label, " = '", actual, "'");
	} else {
		atTestsFailed++;
		Print("  FAIL ", label, " = '", actual, "' -- expected '", expected, "'");
	}
}

/**
* The same for a number, compared with a tolerance because these arrive as
* text and come back as doubles.
*/
void atCheckNum(const string label, const double actual, const double expected) {
	atTestsRun++;

	if(MathAbs(actual - expected) < 0.0001) {
		Print("  ok   ", label, " = ", DoubleToString(actual, 4));
	} else {
		atTestsFailed++;
		Print("  FAIL ", label, " = ", DoubleToString(actual, 4),
			" -- expected ", DoubleToString(expected, 4));
	}
}

void atCheckTrue(const string label, const bool actual, const bool expected) {
	atTestsRun++;

	if(actual == expected) {
		Print("  ok   ", label, " = ", actual ? "true" : "false");
	} else {
		atTestsFailed++;
		Print("  FAIL ", label, " = ", actual ? "true" : "false",
			" -- expected ", expected ? "true" : "false");
	}
}

/**
* Puts a parsed dataset straight into the cache and marks it fresh, so no
* request is ever made for it.
*/
void atSeed(const string pseudoAccount, const string dataset, const string csv) {
	int slot = atCacheSlot(pseudoAccount, dataset);

	atStoreRows(slot, csv);

	atCacheFilled[slot] = true;
	atCacheStatus[slot] = AT_HTTP_CSV;
	atCacheStamp[slot] = GetTickCount();

	/* 0 means "never fetched", so a tick count landing on it must not lie. */
	if(atCacheStamp[slot] == 0) {
		atCacheStamp[slot] = 1;
	}
}

void OnStart() {
	string account = "SELFTEST";

	/*
	* The freshness gate would otherwise re-read orders and positions two
	* seconds in, and this test must never reach the network.
	*/
	AT_TTL_ORDERS = 86400;
	AT_TTL_POSITIONS = 86400;
	AT_TTL_MARGINS = 86400;
	AT_TTL_HOLDINGS = 86400;

	Print("AutoTrader direct library self test");
	Print("");

	/*************************** HOLDINGS *********************************/

	/*
	* Column 5 is the BROKER symbol and column 19 the independent one. A
	* lookup that matches the wrong one finds nothing, which is why the
	* holding here is deliberately one whose two symbols differ.
	*/
	atSeed(account, AT_DS_HOLDINGS,
		"PSEUDOACCOUNT,TRADINGACCOUNT,ID,EXCHANGE,SYMBOL,ISIN,QUANTITY,T1QTY,PNL,"
		"PRODUCT,COLLATERALTYPE,COLLATERALQTY,HAIRCUT,AVGPRICE,INSTRUMENTTOKEN,DAY,"
		"PLATFORM,STOCKBROKER,INDEPENDENTSYMBOLNSE,INDEPENDENTSYMBOLBSE,LTP,CURRENTVALUE\n"
		"SELFTEST,FA0001,9001,NSE,IOC-EQ,INE242A01010,7,0,-5.15,C,,0,0,140.40,1624,"
		"2026-09-10,FINVASIA,FINVASIA,IOC,IOC,135.25,946.75\n"
		"SELFTEST,FA0001,9002,BSE,500325,INE002A01018,3,0,12.00,C,,0,0,1400.00,2885,"
		"2026-09-10,FINVASIA,FINVASIA,,RELIANCE,1412.00,4236.00\n");

	Print("holdings -- the old getters, which took the independent symbol all along");
	atCheckNum("getHoldingQuantity(IOC)", getHoldingQuantity(account, "IOC"), 7);
	atCheck("getHoldingIsin(IOC)", getHoldingIsin(account, "IOC"), "INE242A01010");
	atCheck("getHoldingExchange(IOC)", getHoldingExchange(account, "IOC"), "NSE");
	atCheck("getHoldingProduct(IOC)", getHoldingProduct(account, "IOC"), "C");
	atCheckNum("getHoldingLtp(IOC)", getHoldingLtp(account, "IOC"), 135.25);
	atCheckNum("getHoldingCurrentValue(IOC)", getHoldingCurrentValue(account, "IOC"), 946.75);

	Print("holdings -- a BSE only holding, reachable through the second column");
	atCheckNum("getHoldingQuantity(RELIANCE)", getHoldingQuantity(account, "RELIANCE"), 3);

	Print("holdings -- a stock that is genuinely not held stays blank");
	atCheckNum("getHoldingQuantity(TCS)", getHoldingQuantity(account, "TCS"), 0);

	Print("holdings -- by name");
	string h = atFindHolding(account, "NSE", "IOC");
	atCheckTrue("atFound(IOC)", atFound(h), true);
	atCheckNum("atNum(QUANTITY)", atNum(h, "QUANTITY"), 7);
	atCheckNum("atNum(AVGPRICE)", atNum(h, "AVGPRICE"), 140.40);
	atCheck("atText(ISIN)", atText(h, "ISIN"), "INE242A01010");
	atCheck("atText lower case name", atText(h, "isin"), "INE242A01010");
	atCheck("atText unknown field is blank", atText(h, "NO_SUCH_FIELD"), "");
	atCheckTrue("atFound(TCS)", atFound(atFindHolding(account, "NSE", "TCS")), false);
	atCheck("atText on a handle that found nothing", atText("", "QUANTITY"), "");

	Print("holdings -- walking the list");
	atCheckNum("atHoldingCount", atHoldingCount(account), 2);
	atCheck("atHoldingAt(1)", atText(atHoldingAt(account, 1), "INDEPENDENTSYMBOLNSE"), "IOC");
	atCheck("atHoldingAt(2) BSE", atText(atHoldingAt(account, 2), "INDEPENDENTSYMBOLBSE"), "RELIANCE");
	atCheck("atHoldingAt(0) is blank", atHoldingAt(account, 0), "");
	atCheck("atHoldingAt past the end is blank", atHoldingAt(account, 99), "");

	/**************************** ORDERS **********************************/

	/*
	* The status message deliberately contains a comma inside quotes. A parser
	* that split on every comma would shift every column after it, so
	* AVERAGEPRICE would come back as a piece of the broker's error text.
	*/
	atSeed(account, AT_DS_ORDERS,
		"PSEUDOACCOUNT,TRADINGACCOUNT,PUBLISHERID,ID,EXCHANGEORDERID,VARIETY,"
		"INDEPENDENTEXCHANGE,INDEPENDENTSYMBOL,TRADETYPE,ORDERTYPE,PRODUCTTYPE,QUANTITY,"
		"PRICE,TRIGGERPRICE,FILLEDQUANTITY,PENDINGQUANTITY,STATUS,STATUSMESSAGE,VALIDITY,"
		"AVERAGEPRICE,PARENTORDERID,DISCLOSEDQUANTITY,EXCHANGETIME,PLATFORMTIME,AMO,"
		"COMMENTS,RAWSTATUS,EXCHANGE,SYMBOL,DAY,PLATFORM,CLIENTID,STOCKBROKER\n"
		"SELFTEST,FA0001,,26091000179573,1234,REGULAR,NSE,SBIN,BUY,MARKET,INTRADAY,1,"
		"0,0,1,0,COMPLETE,\"RMS: margin shortfall, order rejected\",DAY,1006.30,,0,,,false,,"
		"COMPLETE,NSE,SBIN-EQ,2026-09-10,FINVASIA,FA0001,FINVASIA\n");

	Print("orders -- read back by the broker's own id");
	atCheck("getOrderStatus", getOrderStatus(account, "26091000179573"), "COMPLETE");
	atCheckNum("getOrderAveragePrice", getOrderAveragePrice(account, "26091000179573"), 1006.30);
	atCheckNum("getOrderFilledQuantity", getOrderFilledQuantity(account, "26091000179573"), 1);
	atCheck("getOrderIndependentSymbol",
		getOrderIndependentSymbol(account, "26091000179573"), "SBIN");
	atCheckTrue("isOrderComplete", isOrderComplete(account, "26091000179573"), true);
	atCheckTrue("isOrderOpen", isOrderOpen(account, "26091000179573"), false);

	Print("orders -- a quoted field containing a comma does not shift the columns");
	atCheck("getOrderStatusMessage", getOrderStatusMessage(account, "26091000179573"),
		"RMS: margin shortfall, order rejected");

	Print("orders -- by name");
	string o = atFindOrder(account, "26091000179573");
	atCheckTrue("atFound(order)", atFound(o), true);
	atCheck("atText(STATUS)", atText(o, "STATUS"), "COMPLETE");
	atCheckNum("atNum(AVERAGEPRICE)", atNum(o, "AVERAGEPRICE"), 1006.30);
	atCheckTrue("atFound(unknown id)", atFound(atFindOrder(account, "does-not-exist")), false);
	atCheckNum("atOrderCount", atOrderCount(account), 1);

	/*************************** POSITIONS ********************************/

	atSeed(account, AT_DS_POSITIONS,
		"PSEUDOACCOUNT,TRADINGACCOUNT,TYPE,CATEGORY,INDEPENDENTEXCHANGE,INDEPENDENTSYMBOL,"
		"MTM,PNL,BUYQUANTITY,SELLQUANTITY,NETQUANTITY,BUYVALUE,SELLVALUE,NETVALUE,"
		"BUYAVGPRICE,SELLAVGPRICE,REALISEDPNL,UNREALISEDPNL,OVERNIGHTQUANTITY,MULTIPLIER,"
		"LTP,EXCHANGE,SYMBOL,DAY,PLATFORM,ACCOUNTID,ID,STOCKBROKER,STATE,DIRECTION,ATPNL\n"
		"SELFTEST,FA0001,MIS,NET,NSE,SBIN,-0.30,-0.30,1,0,1,1006.30,0,1006.30,1006.30,0,"
		"0,-0.30,0,1,1006.00,NSE,SBIN-EQ,2026-09-10,FINVASIA,FA0001,,FINVASIA,OPEN,LONG,-0.30\n");

	Print("positions -- identified by four columns at once");
	atCheckNum("getPositionNetQuantity",
		getPositionNetQuantity(account, "NET", "MIS", NSE, "SBIN"), 1);
	atCheckNum("getPositionBuyAvgPrice",
		getPositionBuyAvgPrice(account, "NET", "MIS", NSE, "SBIN"), 1006.30);
	atCheckNum("getPositionLtp",
		getPositionLtp(account, "NET", "MIS", NSE, "SBIN"), 1006.00);

	Print("positions -- by name");
	string p = atFindPosition(account, "NET", "MIS", "NSE", "SBIN");
	atCheckTrue("atFound(position)", atFound(p), true);
	atCheck("atText(DIRECTION)", atText(p, "DIRECTION"), "LONG");
	atCheckNum("atNum(NETQUANTITY)", atNum(p, "NETQUANTITY"), 1);
	atCheckNum("atNum(MULTIPLIER)", atNum(p, "MULTIPLIER"), 1);
	atCheckTrue("atFound(wrong product)",
		atFound(atFindPosition(account, "NET", "NRML", "NSE", "SBIN")), false);
	atCheckNum("atPositionCount", atPositionCount(account), 1);

	/**************************** MARGINS *********************************/

	atSeed(account, AT_DS_MARGINS,
		"PSEUDOACCOUNT,TRADINGACCOUNT,CATEGORY,FUNDS,UTILIZED,AVAILABLE,DAY,STOCKBROKER,"
		"TOTAL,NET,SPAN,EXPOSURE,COLLATERAL,PAYIN,PAYOUT,ADHOC,REALISEDMTM,UNREALISEDMTM\n"
		"SELFTEST,FA0001,EQUITY,30000,650.63,29349.37,2026-09-10,FINVASIA,30000,29349.37,"
		"0,0,0,0,0,0,0,-0.30\n"
		"SELFTEST,FA0001,COMMODITY,0,0,0,2026-09-10,FINVASIA,0,0,0,0,0,0,0,0,0,0\n");

	Print("margins");
	atCheckNum("getMarginAvailableEquity", getMarginAvailableEquity(account), 29349.37);
	atCheckNum("getMarginUtilizedEquity", getMarginUtilizedEquity(account), 650.63);
	atCheckNum("getMarginAvailableCommodity", getMarginAvailableCommodity(account), 0);

	Print("margins -- by name");
	string m = atFindMargin(account, "EQUITY");
	atCheckTrue("atFound(margin)", atFound(m), true);
	atCheckNum("atNum(AVAILABLE)", atNum(m, "AVAILABLE"), 29349.37);
	atCheckNum("atNum(UNREALISEDMTM)", atNum(m, "UNREALISEDMTM"), -0.30);

	/************************ TRANSPORT DETAILS ***************************/

	Print("transport");
	atCheck("atUrlEncode keeps unreserved characters",
		atUrlEncode("SBIN-EQ_1.0~x"), "SBIN-EQ_1.0~x");
	atCheck("atUrlEncode escapes an ampersand", atUrlEncode("M&M"), "M%26M");
	atCheck("atUrlEncode escapes a space", atUrlEncode("a b"), "a%20b");

	/*
	* The last pipe field carries whatever line ending the reader left behind,
	* and that field is the order id. An id with a newline stuck to it still
	* prints correctly and still matches nothing.
	*/
	atCheck("atPipeField trims the last field",
		atPipeField("OK|26091000179573\n", 2), "26091000179573");
	atCheck("atPipeField keeps a message containing commas",
		atPipeField("SD-ERROR|SD-ERR-1|RMS: shortfall, rejected", 3),
		"RMS: shortfall, rejected");
	atCheck("atPipeField past the end is blank", atPipeField("OK|1", 9), "");

	atCheckNum("atColumnOf resolves a name",
		atColumnOf(account, AT_DS_HOLDINGS, "QUANTITY"), 7);
	atCheckNum("atColumnOf is case insensitive",
		atColumnOf(account, AT_DS_HOLDINGS, "quantity"), 7);
	atCheckNum("atColumnOf finds the independent symbol column",
		atColumnOf(account, AT_DS_HOLDINGS, "INDEPENDENTSYMBOLNSE"), 19);
	atCheckNum("atColumnOf on an unknown name is 0",
		atColumnOf(account, AT_DS_HOLDINGS, "NO_SUCH_FIELD"), 0);
	atCheckNum("atColumnOf answers the same the second time",
		atColumnOf(account, AT_DS_HOLDINGS, "NO_SUCH_FIELD"), 0);

	/*
	* A dataset that is empty first and fills up later.
	*
	* An empty reply carries no header, because the server has no rows to write
	* one from. If a lookup against that remembered "there is no such column",
	* it would keep saying so after the first order arrived, and the order could
	* never be read back -- on the day's first order, every time.
	*/
	Print("transport -- a dataset that starts empty and fills up later");

	string later = "SELFTEST_LATER";
	atSeed(later, AT_DS_ORDERS, "");

	atCheckNum("atColumnOf while empty is 0",
		atColumnOf(later, AT_DS_ORDERS, "ID"), 0);
	atCheckNum("atOrderCount while empty", atOrderCount(later), 0);
	atCheckTrue("atFindOrder while empty finds nothing",
		atFound(atFindOrder(later, "26091000179573")), false);

	atSeed(later, AT_DS_ORDERS,
		"PSEUDOACCOUNT,TRADINGACCOUNT,PUBLISHERID,ID,EXCHANGEORDERID,VARIETY,"
		"INDEPENDENTEXCHANGE,INDEPENDENTSYMBOL,TRADETYPE,ORDERTYPE,PRODUCTTYPE,QUANTITY,"
		"PRICE,TRIGGERPRICE,FILLEDQUANTITY,PENDINGQUANTITY,STATUS,STATUSMESSAGE,VALIDITY,"
		"AVERAGEPRICE,PARENTORDERID,DISCLOSEDQUANTITY,EXCHANGETIME,PLATFORMTIME,AMO,"
		"COMMENTS,RAWSTATUS,EXCHANGE,SYMBOL,DAY,PLATFORM,CLIENTID,STOCKBROKER\n"
		"SELFTEST_LATER,FA0001,,26091000179573,1234,REGULAR,NSE,SBIN,BUY,LIMIT,INTRADAY,1,"
		"950,0,0,1,OPEN,,DAY,0,,0,,,false,,OPEN,NSE,SBIN-EQ,2026-09-10,FINVASIA,FA0001,FINVASIA\n");

	atCheckNum("atColumnOf once the rows arrive",
		atColumnOf(later, AT_DS_ORDERS, "ID"), 4);
	atCheckTrue("atFindOrder once the rows arrive",
		atFound(atFindOrder(later, "26091000179573")), true);
	atCheck("getOrderStatus once the rows arrive",
		getOrderStatus(later, "26091000179573"), "OPEN");

	/******************************* RESULT *******************************/

	Print("");

	if(atTestsFailed == 0) {
		Print("PASS -- ", atTestsRun, " checks, 0 failures");
	} else {
		Print("FAIL -- ", atTestsRun, " checks, ", atTestsFailed, " failures");
	}
}
