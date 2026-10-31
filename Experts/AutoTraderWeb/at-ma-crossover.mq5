//+----------------------------------------------------------------------+
//|                                                 at-ma-crossover.mq5 	|
//|                                                       AutoTrader Web 	|
//|                            https://stocksdeveloper.in/               	|
//+----------------------------------------------------------------------+
#property copyright "AutoTrader"
#property link      "https://stocksdeveloper.in/"
#property version   "1.00"
#property description "Sample strategy: moving average crossover, for one account or many."
#property description "A starting point for your own rules, not a recommendation."

/*********************************************************************
* A SAMPLE strategy that shows where your own rules go.
*
* It is an example of how to wire a strategy to AutoTrader Web, not a
* trading recommendation. Replace the rules in atSignal() with your own.
*
* WHAT IT DOES
*
* - When a candle CLOSES with the fast average above the slow one, after
*   being below it: BUY. The opposite: SELL.
* - Already in a position the other way? It squares that off first, then
*   enters the new side. Set Long only to true to never go short.
* - At the square-off time it squares off and stops trading for the day.
* - It acts once per closed candle. A signal never repeats on every tick
*   of an unfinished candle.
*
* Orders go to every account in the Pseudo account input, separated by
* commas: ACC1,ACC2,ACC3
*
* WHAT IT TRADES
*
* - The Exchange/Symbol inputs (the default): BUY buys that symbol, SELL
*   sells it.
* - Options: BUY buys a CALL, SELL buys a PUT, on the Option underlying
*   (NIFTY, BANKNIFTY...). It never sells an option. AutoTrader Web picks
*   the contract from its own option chain using the strike rule and the
*   expiry, once per signal, and every account gets that same contract.
*   Option lots is in LOTS: 1 means one lot, whatever its size. The exit
*   squares off the contract it bought, not a fresh lookup.
*
* It remembers its own position while it runs. If you restart it while in
* a trade, square off from AutoTrader Web first, or it starts as flat.
*
* BEFORE THIS WILL WORK: the same three steps as at-trade-panel.mq5 (API
* key, allowed address, Algo Trading on). Every order is a market order,
* sent by AutoTrader Web as a protected limit order near the live price.
*********************************************************************/

#include <autotrader-http.mqh>

input int MA_FAST = 20;					// Fast moving average (candles)

input int MA_SLOW = 50;				// Slow moving average (candles)

input bool MA_LONG_ONLY = false;		// Long only (never go short)

input bool MA_USE_AT_BO = false;		// Use an AutoTrader bracket order

input double MA_TARGET = 0;			// Bracket: target, in rupees from entry

input double MA_STOPLOSS = 0;			// Bracket: stoploss, in rupees from entry

input double MA_TRAILING = 0;			// Bracket: trailing stoploss step (0 = off)

input string MA_SQUARE_OFF_TIME = "15:15";	// Square off at (your computer's time, HH:MM)

enum MaTradeWhat {
	MA_TRADE_SYMBOL = 0,	// The Exchange/Symbol inputs
	MA_TRADE_OPTIONS = 1	// Options: BUY buys a call, SELL buys a put
};

input MaTradeWhat MA_TRADE = MA_TRADE_SYMBOL;	// What to trade

input string MA_OPT_UNDERLYING = "NIFTY";	// Option underlying, e.g. NIFTY

input Exchange MA_OPT_EXCHANGE = NSE;		// Option exchange (BSE for SENSEX)

input string MA_OPT_STRIKE = "ATM";		// Option strike: ATM, ATM+2, OTM1, ITM1 or a number

input string MA_OPT_EXPIRY = "weekly";		// Option expiry: weekly, next, monthly or yyyy-MM-dd

input int MA_OPT_LOTS = 1;					// Option lots per account (lots, not units)

string maAccounts[];

/* What each account holds now, per account: the symbol and its exchange. */
string maHeldSymbol[];

Exchange maHeldExchange = NSE;

int maFastHandle = INVALID_HANDLE;

int maSlowHandle = INVALID_HANDLE;

datetime maLastBar = 0;

/* The strategy's own position: 1 long, -1 short, 0 flat. */
int maSide = 0;

/* The day the square-off time was reached; no new trades after it. */
int maDoneDay = -1;

int OnInit()
  {
	if(!autoTraderReady()) {
		return(INIT_FAILED);
	}

	if(maReadAccounts() == 0) {
		Print("AutoTrader: SD-ERR-MT-STRATEGY: No account. Put one or more pseudo accounts, ",
			"separated by commas, in the Pseudo account input.");
		return(INIT_PARAMETERS_INCORRECT);
	}

	if(MA_USE_AT_BO && (MA_TARGET <= 0 || MA_STOPLOSS <= 0)) {
		Print("AutoTrader: SD-ERR-MT-STRATEGY: A bracket order needs both a target and a ",
			"stoploss, in rupees from your entry price.");
		return(INIT_PARAMETERS_INCORRECT);
	}

	if(MA_TRADE == MA_TRADE_OPTIONS && (StringLen(MA_OPT_UNDERLYING) == 0 || MA_OPT_LOTS <= 0)) {
		Print("AutoTrader: SD-ERR-MT-STRATEGY: Options need an Option underlying and ",
			"Option lots of 1 or more.");
		return(INIT_PARAMETERS_INCORRECT);
	}

	ArrayResize(maHeldSymbol, ArraySize(maAccounts));

	// A new string array element is NULL, and NULL != "": set them empty
	for(int i = 0; i < ArraySize(maHeldSymbol); i++) {
		maHeldSymbol[i] = "";
	}

	maFastHandle = iMA(_Symbol, _Period, MA_FAST, 0, MODE_EMA, PRICE_CLOSE);
	maSlowHandle = iMA(_Symbol, _Period, MA_SLOW, 0, MODE_EMA, PRICE_CLOSE);

	if(maFastHandle == INVALID_HANDLE || maSlowHandle == INVALID_HANDLE) {
		Print("AutoTrader: SD-ERR-MT-STRATEGY: Could not create the moving averages.");
		return(INIT_FAILED);
	}

	/* Start from the candle now forming; never act on history. */
	maLastBar = iTime(_Symbol, _Period, 0);

	string what = (MA_TRADE == MA_TRADE_OPTIONS)
		? MA_OPT_UNDERLYING + " options (" + MA_OPT_STRIKE + " " + MA_OPT_EXPIRY + ", " +
			IntegerToString(MA_OPT_LOTS) + " lot(s))"
		: EnumToString(AT_EXCHANGE) + " " + AT_SYMBOL;

	Print("AutoTrader: strategy started on ", _Symbol, ", orders for ", what, " in ",
		ArraySize(maAccounts), " account(s)");

	// A chart fed by a data vendor's plugin (a custom symbol) may never call
	// OnTick, so a one-second timer checks for a new candle too
	EventSetTimer(1);

	return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
	EventKillTimer();
	IndicatorRelease(maFastHandle);
	IndicatorRelease(maSlowHandle);
  }

void OnTick()
  {
	maOnCandle();
  }

void OnTimer()
  {
	maOnCandle();
  }

/* Acts once when a new candle starts, whether a tick or the timer sees it first. */
void maOnCandle()
  {
	if(maSquareOffTimeReached()) {
		return;
	}

	datetime bar = iTime(_Symbol, _Period, 0);

	if(bar == maLastBar) {
		return;
	}

	/* A new candle has started, so the previous one has closed. */
	maLastBar = bar;

	int signal = atSignal();

	if(signal == 1 && maSide != 1) {
		maEnter(BUY);
	} else if(signal == -1 && maSide == 1) {
		maExit();

		if(!MA_LONG_ONLY) {
			maEnter(SELL);
		}
	} else if(signal == -1 && maSide == 0 && !MA_LONG_ONLY) {
		maEnter(SELL);
	}
  }

/*
* YOUR RULES GO HERE. Return 1 to buy, -1 to sell, 0 to do nothing.
*
* Reads only closed candles (shift 1 and 2), so a signal cannot appear and
* vanish within one candle.
*/
int atSignal()
  {
	double fast[], slow[];

	if(CopyBuffer(maFastHandle, 0, 1, 2, fast) != 2 ||
		CopyBuffer(maSlowHandle, 0, 1, 2, slow) != 2) {
		return 0;
	}

	/* index 0 = two candles ago, index 1 = the candle that just closed */
	if(fast[0] <= slow[0] && fast[1] > slow[1]) {
		return 1;
	}

	if(fast[0] >= slow[0] && fast[1] < slow[1]) {
		return -1;
	}

	return 0;
  }

void maEnter(const TradeType tradeType)
  {
	if(maSide != 0) {
		maExit();
	}

	/* Options: BUY buys a call and SELL buys a put; looked up once for every account. */
	Exchange exchange = AT_EXCHANGE;
	string symbol = AT_SYMBOL;
	TradeType side = tradeType;
	int quantity = AT_QUANTITY;

	if(MA_TRADE == MA_TRADE_OPTIONS) {
		string optionType = (tradeType == BUY) ? "CE" : "PE";

		if(!resolveOptionContract(maAccounts[0], MA_OPT_EXCHANGE, MA_OPT_UNDERLYING,
			optionType, MA_OPT_STRIKE, MA_OPT_EXPIRY, 0)) {
			Print("AutoTrader: SD-ERR-MT-STRATEGY: no ", optionType, " contract, nothing sent: ",
				atHttpMessage);
			return;
		}

		exchange = atOptionExchange;
		symbol = atOptionSymbol;
		side = BUY;
		quantity = MA_OPT_LOTS * atOptionLotSize;
	}

	maHeldExchange = exchange;

	int placed = 0;

	for(int i = 0; i < ArraySize(maAccounts); i++) {
		string orderId;

		if(MA_USE_AT_BO) {
			orderId = placeAutoTraderBracketOrder(maAccounts[i], exchange, symbol,
				side, MARKET, quantity, 0, 0,
				MA_TARGET, MA_STOPLOSS, MA_TRAILING, false);
		} else {
			orderId = placeOrder(maAccounts[i], exchange, symbol,
				side, MARKET, AT_PRODUCT_TYPE, quantity, 0, 0, false);
		}

		/* AT_UNCONFIRMED may be live, so it counts as in the position. */
		if(orderId != "") {
			maHeldSymbol[i] = symbol;
			placed++;
		}
	}

	if(placed > 0) {
		maSide = (tradeType == BUY) ? 1 : -1;
	}

	Print("AutoTrader: strategy: ", EnumToString(side), " ", symbol, " sent to ", placed, " of ",
		ArraySize(maAccounts), " account(s)");
  }

void maExit()
  {
	string type = MA_USE_AT_BO ? "MIS" : maPositionType();

	for(int i = 0; i < ArraySize(maAccounts); i++) {
		if(maHeldSymbol[i] != "") {
			squareOffPosition(maAccounts[i], "NET", type, maHeldExchange, maHeldSymbol[i]);
			maHeldSymbol[i] = "";
		}
	}

	maSide = 0;
  }

bool maSquareOffTimeReached()
  {
	MqlDateTime now;
	TimeToStruct(TimeLocal(), now);

	if(maDoneDay == now.day_of_year) {
		return true;
	}

	string hhmm = StringFormat("%02d:%02d", now.hour, now.min);

	if(hhmm < MA_SQUARE_OFF_TIME) {
		return false;
	}

	if(maSide != 0) {
		Print("AutoTrader: strategy: square-off time ", MA_SQUARE_OFF_TIME, " reached");
		maExit();
	}

	maDoneDay = now.day_of_year;

	return true;
  }

string maPositionType()
  {
	if(AT_PRODUCT_TYPE == DELIVERY) {
		return "CNC";
	}

	if(AT_PRODUCT_TYPE == NORMAL) {
		return "NRML";
	}

	return "MIS";
  }

int maReadAccounts()
  {
	string parts[];
	int n = StringSplit(AT_ACCOUNT, ',', parts);

	ArrayResize(maAccounts, 0);

	for(int i = 0; i < n; i++) {
		string account = parts[i];
		StringTrimLeft(account);
		StringTrimRight(account);

		if(StringLen(account) > 0) {
			int size = ArraySize(maAccounts);
			ArrayResize(maAccounts, size + 1);
			maAccounts[size] = account;
		}
	}

	return ArraySize(maAccounts);
  }
