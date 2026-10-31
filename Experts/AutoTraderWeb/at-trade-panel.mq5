//+----------------------------------------------------------------------+
//|                                                 at-trade-panel.mq5 	|
//|                                                       AutoTrader Web 	|
//|                            https://stocksdeveloper.in/               	|
//+----------------------------------------------------------------------+
#property copyright "AutoTrader"
#property link      "https://stocksdeveloper.in/"
#property version   "1.00"
#property description "BUY, SELL and SQUARE OFF buttons on the chart."
#property description "One click places the order in one account or many."

/*********************************************************************
* BUY / SELL / SQUARE OFF buttons, for one account or several.
*
* No programming needed: attach it to a chart, fill in the inputs, and
* click. Each click goes to every account in the list, one after the
* other.
*
* INPUTS
*
* Pseudo account   One account, or several separated by commas:
*                  ACC1,ACC2,ACC3
* Exchange/Symbol  What to trade. This is the symbol the order uses, not
*                  the chart's own name, so the chart can come from any
*                  data feed. Look a symbol up in AutoTrader Web:
*                  Tools -> Instruments.
* Order quantity   Per account. For futures and options, a multiple of
*                  the lot size (1 lot of 75 = 75).
* Order kind       A regular order, or an AutoTrader bracket order with a
*                  target and stoploss watched by AutoTrader Web.
*
* OPTION BUTTONS (optional)
*
* Fill in Option underlying (NIFTY, BANKNIFTY, a stock...) and a second
* row appears: BUY CALL, BUY PUT and SQUARE OFF OPTIONS. AutoTrader Web
* picks the contract from its own option chain using the strike rule
* (ATM, ATM+2, OTM1, ITM1, or an exact strike) and the expiry (weekly,
* next, monthly, or a date). The confirm box shows the exact contract
* before anything is sent, and every account gets that same contract.
* Option lots is in LOTS: 1 means one lot, whatever its size.
*
* SQUARE OFF OPTIONS squares off the contracts bought from this panel,
* not a fresh lookup (by then ATM may be another strike). The panel
* forgets them when it is removed or MetaTrader restarts; square those
* off from AutoTrader Web.
*
* BEFORE THIS WILL WORK
*
* 1. Your API key is in Include/autotrader-http-config.mqh (the download
*    from AutoTrader Web already has it there).
* 2. Tools -> Options -> Expert Advisors -> "Allow WebRequest for listed
*    URL", then add https://apix.stocksdeveloper.in
* 3. Turn on Algo Trading in the toolbar.
*
* Every order is a market order. Your broker no longer accepts a plain
* market order through its API, so AutoTrader Web sends it as a limit
* order close to the live price (market price protection).
*
* What happened to each order is printed in the Experts tab, and the
* last result is shown under the buttons.
*********************************************************************/

#include <autotrader-http.mqh>

enum PanelOrderKind {
	PANEL_REGULAR = 0,		// Regular order
	PANEL_AT_BO = 1		// AutoTrader bracket order (target + stoploss)
};

input PanelOrderKind PANEL_ORDER_KIND = PANEL_REGULAR;	// Order kind

input double PANEL_TARGET = 0;			// Bracket: target, in rupees from entry

input double PANEL_STOPLOSS = 0;		// Bracket: stoploss, in rupees from entry

input double PANEL_TRAILING = 0;		// Bracket: trailing stoploss step (0 = off)

input bool PANEL_CONFIRM = true;		// Ask before sending each click

input string PANEL_OPT_UNDERLYING = "";	// Option underlying, e.g. NIFTY (blank = no option buttons)

input Exchange PANEL_OPT_EXCHANGE = NSE;	// Option exchange (BSE for SENSEX)

input string PANEL_OPT_STRIKE = "ATM";		// Option strike: ATM, ATM+2, OTM1, ITM1 or a number

input string PANEL_OPT_EXPIRY = "weekly";	// Option expiry: weekly, next, monthly or yyyy-MM-dd

input int PANEL_OPT_LOTS = 1;				// Option lots per account (lots, not units)

#define PANEL_PREFIX "atPanel"
#define PANEL_BUY PANEL_PREFIX + "Buy"
#define PANEL_SELL PANEL_PREFIX + "Sell"
#define PANEL_SQOFF PANEL_PREFIX + "SquareOff"
#define PANEL_CALL PANEL_PREFIX + "BuyCall"
#define PANEL_PUT PANEL_PREFIX + "BuyPut"
#define PANEL_OPT_SQOFF PANEL_PREFIX + "SquareOffOptions"
#define PANEL_INFO PANEL_PREFIX + "Info"
#define PANEL_RESULT PANEL_PREFIX + "Result"

string panelAccounts[];

/* Option contracts bought from this panel, per account, for SQUARE OFF OPTIONS. */
string panelCallSymbol[];

string panelPutSymbol[];

Exchange panelOptExchange = NSE;

int OnInit()
  {
	if(!autoTraderReady()) {
		return(INIT_FAILED);
	}

	if(panelReadAccounts() == 0) {
		Print("AutoTrader: SD-ERR-MT-PANEL: No account. Put one or more pseudo accounts, ",
			"separated by commas, in the Pseudo account input.");
		return(INIT_PARAMETERS_INCORRECT);
	}

	if(PANEL_ORDER_KIND == PANEL_AT_BO && (PANEL_TARGET <= 0 || PANEL_STOPLOSS <= 0)) {
		Print("AutoTrader: SD-ERR-MT-PANEL: A bracket order needs both a target and a ",
			"stoploss, in rupees from your entry price.");
		return(INIT_PARAMETERS_INCORRECT);
	}

	if(panelHasOptions() && PANEL_OPT_LOTS <= 0) {
		Print("AutoTrader: SD-ERR-MT-PANEL: Option lots must be 1 or more.");
		return(INIT_PARAMETERS_INCORRECT);
	}

	int total = ArraySize(panelAccounts);
	ArrayResize(panelCallSymbol, total);
	ArrayResize(panelPutSymbol, total);

	panelButton(PANEL_BUY, "BUY", 10, 30, 100, clrWhite, C'16,150,90');
	panelButton(PANEL_SELL, "SELL", 120, 30, 100, clrWhite, C'200,50,50');
	panelButton(PANEL_SQOFF, "SQUARE OFF", 230, 30, 100, clrBlack, C'240,200,40');

	int labelY = 70;

	if(panelHasOptions()) {
		panelButton(PANEL_CALL, "BUY CALL", 10, 72, 100, clrWhite, C'16,150,90');
		panelButton(PANEL_PUT, "BUY PUT", 120, 72, 100, clrWhite, C'200,50,50');
		panelButton(PANEL_OPT_SQOFF, "SQUARE OFF OPTIONS", 230, 72, 160, clrBlack, C'240,200,40');
		labelY = 112;
	}

	panelLabel(PANEL_INFO, panelDescribe(), labelY);
	panelLabel(PANEL_RESULT, "Ready.", labelY + 22);

	ChartRedraw();

	return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
	ObjectsDeleteAll(0, PANEL_PREFIX);
	ChartRedraw();
  }

void OnTick()
  {
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam,
	const string &sparam)
  {
	if(id != CHARTEVENT_OBJECT_CLICK) {
		return;
	}

	if(sparam == PANEL_BUY) {
		panelPlace(BUY);
	} else if(sparam == PANEL_SELL) {
		panelPlace(SELL);
	} else if(sparam == PANEL_SQOFF) {
		panelSquareOff();
	} else if(sparam == PANEL_CALL) {
		panelBuyOption("CE");
	} else if(sparam == PANEL_PUT) {
		panelBuyOption("PE");
	} else if(sparam == PANEL_OPT_SQOFF) {
		panelSquareOffOptions();
	} else {
		return;
	}

	// A button stays pressed until it is released here
	ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
	ChartRedraw();
  }

/*
* Places one order per account. Each order waits for the broker's answer
* before the next is sent, so the result line reports every account.
*/
void panelPlace(const TradeType tradeType)
  {
	string side = EnumToString(tradeType);

	if(!panelConfirm(side + " " + IntegerToString(AT_QUANTITY) + " " + AT_SYMBOL)) {
		return;
	}

	int placed = 0;
	int unconfirmed = 0;
	int total = ArraySize(panelAccounts);

	for(int i = 0; i < total; i++) {
		string account = panelAccounts[i];
		string orderId;

		Print("AutoTrader: panel: ", side, " in account ", i + 1, " of ", total, ": ", account);

		if(PANEL_ORDER_KIND == PANEL_AT_BO) {
			orderId = placeAutoTraderBracketOrder(account, AT_EXCHANGE, AT_SYMBOL,
				tradeType, MARKET, AT_QUANTITY, 0, 0,
				PANEL_TARGET, PANEL_STOPLOSS, PANEL_TRAILING, false);
		} else {
			orderId = placeOrder(account, AT_EXCHANGE, AT_SYMBOL,
				tradeType, MARKET, AT_PRODUCT_TYPE, AT_QUANTITY, 0, 0, false);
		}

		if(orderId == AT_UNCONFIRMED) {
			unconfirmed++;
		} else if(orderId != "") {
			placed++;
		}
	}

	string result = side + ": placed in " + IntegerToString(placed) + " of " +
		IntegerToString(total) + " account(s)";

	if(unconfirmed > 0) {
		result += ", " + IntegerToString(unconfirmed) +
			" NOT CONFIRMED (check the order book, do not click again)";
	}

	panelResult(result, placed == total);
  }

/*
* Squares off this symbol's position in every account. Cancels nothing
* else and touches no other symbol.
*/
void panelSquareOff()
  {
	if(!panelConfirm("SQUARE OFF " + AT_SYMBOL)) {
		return;
	}

	string type = panelPositionType();
	int done = 0;
	int total = ArraySize(panelAccounts);

	for(int i = 0; i < total; i++) {
		Print("AutoTrader: panel: square off in account ", i + 1, " of ", total, ": ",
			panelAccounts[i]);

		if(squareOffPosition(panelAccounts[i], "NET", type, AT_EXCHANGE, AT_SYMBOL)) {
			done++;
		}
	}

	panelResult("SQUARE OFF: sent in " + IntegerToString(done) + " of " +
		IntegerToString(total) + " account(s)", done == total);
  }

bool panelHasOptions()
  {
	return StringLen(PANEL_OPT_UNDERLYING) > 0;
  }

/*
* Looks the contract up ONCE, so every account gets the same one even if
* the price moves while the orders go out, then asks with the exact
* contract on screen before sending anything.
*/
void panelBuyOption(const string optionType)
  {
	string label = (optionType == "CE") ? "BUY CALL" : "BUY PUT";

	if(!resolveOptionContract(panelAccounts[0], PANEL_OPT_EXCHANGE, PANEL_OPT_UNDERLYING,
		optionType, PANEL_OPT_STRIKE, PANEL_OPT_EXPIRY, 0)) {
		panelResult(label + ": " + atHttpMessage, false);
		return;
	}

	string symbol = atOptionSymbol;
	int quantity = PANEL_OPT_LOTS * atOptionLotSize;

	if(!panelConfirm("BUY " + IntegerToString(PANEL_OPT_LOTS) + " lot(s) (" +
		IntegerToString(quantity) + ") of " + symbol)) {
		return;
	}

	panelOptExchange = atOptionExchange;

	int placed = 0;
	int unconfirmed = 0;
	int total = ArraySize(panelAccounts);

	for(int i = 0; i < total; i++) {
		Print("AutoTrader: panel: ", label, " ", symbol, " in account ", i + 1, " of ",
			total, ": ", panelAccounts[i]);

		string orderId = placeOrder(panelAccounts[i], panelOptExchange, symbol,
			BUY, MARKET, AT_PRODUCT_TYPE, quantity, 0, 0, false);

		if(orderId == "") {
			continue;
		}

		// Remembered even when unconfirmed: it may well have gone through
		if(optionType == "CE") {
			panelCallSymbol[i] = symbol;
		} else {
			panelPutSymbol[i] = symbol;
		}

		if(orderId == AT_UNCONFIRMED) {
			unconfirmed++;
		} else {
			placed++;
		}
	}

	string result = label + " " + symbol + ": placed in " + IntegerToString(placed) +
		" of " + IntegerToString(total) + " account(s)";

	if(unconfirmed > 0) {
		result += ", " + IntegerToString(unconfirmed) +
			" NOT CONFIRMED (check the order book, do not click again)";
	}

	panelResult(result, placed == total);
  }

/*
* Squares off the calls and puts bought from this panel, in every account.
*/
void panelSquareOffOptions()
  {
	int total = ArraySize(panelAccounts);
	int pending = 0;

	for(int i = 0; i < total; i++) {
		if(panelCallSymbol[i] != "") pending++;
		if(panelPutSymbol[i] != "") pending++;
	}

	if(pending == 0) {
		panelResult("SQUARE OFF OPTIONS: nothing bought from this panel yet", false);
		return;
	}

	if(!panelConfirm("SQUARE OFF the options bought from this panel")) {
		return;
	}

	string type = panelProductPositionType();
	int done = 0;

	for(int i = 0; i < total; i++) {
		if(panelCallSymbol[i] != "" &&
			squareOffPosition(panelAccounts[i], "NET", type, panelOptExchange, panelCallSymbol[i])) {
			panelCallSymbol[i] = "";
			done++;
		}

		if(panelPutSymbol[i] != "" &&
			squareOffPosition(panelAccounts[i], "NET", type, panelOptExchange, panelPutSymbol[i])) {
			panelPutSymbol[i] = "";
			done++;
		}
	}

	panelResult("SQUARE OFF OPTIONS: sent " + IntegerToString(done) + " of " +
		IntegerToString(pending), done == pending);
  }

/*
* A bracket order goes to the broker as an intraday order, so its position
* is an intraday (MIS) one whatever the product input says.
*/
string panelPositionType()
  {
	if(PANEL_ORDER_KIND == PANEL_AT_BO) {
		return "MIS";
	}

	return panelProductPositionType();
  }

string panelProductPositionType()
  {
	if(AT_PRODUCT_TYPE == DELIVERY) {
		return "CNC";
	}

	if(AT_PRODUCT_TYPE == NORMAL) {
		return "NRML";
	}

	return "MIS";
  }

bool panelConfirm(const string action)
  {
	if(!PANEL_CONFIRM) {
		return true;
	}

	string text = action + "\n\nAccounts: " + AT_ACCOUNT + "\n\nSend now?";

	return MessageBox(text, "AutoTrader Web", MB_YESNO | MB_ICONQUESTION) == IDYES;
  }

int panelReadAccounts()
  {
	string parts[];
	int n = StringSplit(AT_ACCOUNT, ',', parts);

	ArrayResize(panelAccounts, 0);

	for(int i = 0; i < n; i++) {
		string account = parts[i];
		StringTrimLeft(account);
		StringTrimRight(account);

		if(StringLen(account) > 0) {
			int size = ArraySize(panelAccounts);
			ArrayResize(panelAccounts, size + 1);
			panelAccounts[size] = account;
		}
	}

	return ArraySize(panelAccounts);
  }

string panelDescribe()
  {
	string kind = (PANEL_ORDER_KIND == PANEL_AT_BO)
		? "AT bracket, target " + DoubleToString(PANEL_TARGET, 2) +
			", stoploss " + DoubleToString(PANEL_STOPLOSS, 2)
		: EnumToString(AT_PRODUCT_TYPE);

	string text = EnumToString(AT_EXCHANGE) + " " + AT_SYMBOL + "  |  qty " +
		IntegerToString(AT_QUANTITY) + "  |  " + kind + "  |  " +
		IntegerToString(ArraySize(panelAccounts)) + " account(s)";

	if(panelHasOptions()) {
		text += "  |  options: " + PANEL_OPT_UNDERLYING + " " + PANEL_OPT_STRIKE + " " +
			PANEL_OPT_EXPIRY + ", " + IntegerToString(PANEL_OPT_LOTS) + " lot(s)";
	}

	return text;
  }

void panelResult(const string text, const bool allGood)
  {
	ObjectSetString(0, PANEL_RESULT, OBJPROP_TEXT, text);
	ObjectSetInteger(0, PANEL_RESULT, OBJPROP_COLOR, allGood ? clrLimeGreen : clrOrangeRed);
	Print("AutoTrader: panel: ", text);
  }

void panelButton(const string name, const string text, const int x, const int y,
	const int width, const color textColor, const color background)
  {
	ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
	ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
	ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
	ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
	ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
	ObjectSetInteger(0, name, OBJPROP_YSIZE, 34);
	ObjectSetString(0, name, OBJPROP_TEXT, text);
	ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
	ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
	ObjectSetInteger(0, name, OBJPROP_COLOR, textColor);
	ObjectSetInteger(0, name, OBJPROP_BGCOLOR, background);
	ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

void panelLabel(const string name, const string text, const int y)
  {
	ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
	ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
	ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 10);
	ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
	ObjectSetString(0, name, OBJPROP_TEXT, text);
	ObjectSetString(0, name, OBJPROP_FONT, "Arial");
	ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
	ObjectSetInteger(0, name, OBJPROP_COLOR, clrSilver);
	ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }
