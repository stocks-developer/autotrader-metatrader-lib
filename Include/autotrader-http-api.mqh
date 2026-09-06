/******************************************************************************
*
* AutoTrader Web automated trading API functions -- direct (HTTP) version.
* DO NOT MODIFY THIS FILE
* Version: 1.0
*
* The same functions as autotrader.mqh, talking to AutoTrader Web over the
* internet instead of through files. Your strategy code does not change:
* placeOrder(), getOrderStatus(), getPositionMtm() and the rest keep their
* names, their arguments and their meaning.
*
* FOUR DIFFERENCES worth knowing before you switch:
*
* 1. placeOrder() now waits for the broker's answer and returns the BROKER's
*    order id, not an internally generated one. That is the id you pass to
*    getOrderStatus(), modifyOrder() and cancelOrder(), and it is the same id
*    you see in your broker's order book.
*
* 2. placeOrder() can return the word held in AT_UNCONFIRMED. That means the
*    order reached the broker and the broker never confirmed it, so it may be
*    live. Do not send it again -- look at your order book.
*
* 3. The portfolio summary functions (getPortfolioMtm, getPortfolioPnl, the
*    position and order counts) are not part of this version. They were
*    calculated on your own computer by a program this library exists to do
*    without. Use the position and order functions instead.
*
* 4. The repeat-order guard now remembers the last order PER ACCOUNT AND
*    SYMBOL. It used to remember only one order for the whole strategy, so a
*    signal on one symbol suppressed a genuine signal on another. If you were
*    relying on that to throttle a basket, set AT_AVOID_REPEAT_ORDER_DELAY to 0
*    and do the throttling yourself.
*
* And one that is fixed rather than changed: getHolding...() now finds your
* holdings. The file based library matched the symbol against the wrong column
* and always returned blank.
*
******************************************************************************/

#ifndef AUTOTRADER_HTTP_API_MQH
#define AUTOTRADER_HTTP_API_MQH

/***************************** CONSTANTS - START *****************************/

/*
* Column 4 of the orders CSV -- the broker's own order id.
*
* The file based library looks orders up by column 3, the publisher id it
* generated before sending the order. This library never makes one: it is
* handed the broker's id when the order is accepted, so that is what every
* get...Order...() function matches on.
*/
#define AT_ORDER_ID_COLUMN 4

/****************************** CONSTANTS - END ******************************/


/***************************** PARAMETERS - START ****************************/

input string AT_ACCOUNT = "Pseudo Account";	// Pseudo account

input Exchange AT_EXCHANGE = NSE;	// Exchange

input string AT_SYMBOL = "SYMBOL"; 	// Order symbol

input int AT_QUANTITY = 1; 					// Order quantity

input ProductType AT_PRODUCT_TYPE = INTRADAY;	// Product type

input bool AT_DEBUG = false; 				// Print Additional Logs

input int AT_PRICE_PRECISION = 4; 		// Price precision, used for rounding price

/*
* Used for avoiding repeat orders. Repeat orders are back to back buy or
* sell orders. The system will not accept an order in this many seconds,
* if an order for same account, stock and tradeType was sent earlier.
* If you want to execute back to back order then you can set this
* parameter to 0.
* If you want to avoid repeat orders generated due to duplicate signals
* then set this parameter to a value higher than your candle interval.
*
* Example:
* 1. Assume AT_AVOID_REPEAT_ORDER_DELAY value is set for 120 seconds &
* 		your chart uses 1-minute (60 seconds) candle.
* 2. System receives a BUY order for SBIN at time 10:15:15.
* 3. System will place it.
* 4. After 15 seconds, system receives another BUY order for SBIN
* 		at time 10:15:30.
* 5. The system will NOT place this order, as the symbol & tradeType
* 		are same and the order came with 120 seconds of previous order.
*/
input int AT_AVOID_REPEAT_ORDER_DELAY = 26000; 	// Avoid repeat orders (in seconds)

/***************************** PARAMETERS - END *****************************/


/*****************************************************************************/
/************************* REPEAT ORDER GUARD - START ************************/
/*****************************************************************************/

/*
* One remembered order per account and symbol.
*
* The file based library kept a single last-order for the whole program, which
* meant a BUY on one symbol blocked a BUY on the next -- the guard exists to
* swallow the repeated signal MetaTrader gives for every tick of an unfinished
* candle, and that repetition is per symbol.
*/

string atGuardKeys[];

datetime atGuardTime[];

TradeType atGuardTradeType[];

int atGuardSlot(const string account, const string symbol) {
	string key = account + "-" + symbol;
	int total = ArraySize(atGuardKeys);

	for(int i = 0; i < total; i++) {
		if(atGuardKeys[i] == key) {
			return i;
		}
	}

	ArrayResize(atGuardKeys, total + 1);
	ArrayResize(atGuardTime, total + 1);
	ArrayResize(atGuardTradeType, total + 1);

	atGuardKeys[total] = key;
	atGuardTime[total] = 0;
	atGuardTradeType[total] = BUY;

	return total;
}

/*
* Saves last order time.
*/
void saveLastOrderTime(const string account, const string symbol, const datetime time) {
	atGuardTime[atGuardSlot(account, symbol)] = time;
}

/*
* Fetches the last order time (if available).
*/
datetime readLastOrderTime(const string account, const string symbol) {
	return atGuardTime[atGuardSlot(account, symbol)];
}

/*
* Saves last order trade type.
*/
void saveLastOrderTradeType(const string account, const string symbol, const TradeType tradeType) {
	atGuardTradeType[atGuardSlot(account, symbol)] = tradeType;
}

/*
* Fetches the last order trade type (if available).
*/
TradeType readLastOrderTradeType(const string account, const string symbol) {
	return atGuardTradeType[atGuardSlot(account, symbol)];
}

/*
* Converts order to easy to read text format.
*/
string orderString(Variety variety, string symbol, TradeType tradeType,
	OrderType orderType, int quantity, double price, double triggerPrice=0,
	double target=0, double stoploss=0, double trailingStoploss=0) {
	string qty = IntegerToString(quantity);
	string prc = DoubleToString(price, 2);
	string trigPrc = DoubleToString(triggerPrice, 2);
	string t = DoubleToString(target, 2);
	string sl = DoubleToString(stoploss, 2);
	string tsl = DoubleToString(trailingStoploss, 2);
	string tradeTypeStr = EnumToString(tradeType);
	string orderTypeStr = EnumToString(orderType);

	string conciseForm = symbol + "|" + tradeTypeStr + "|" + orderTypeStr + "|" +
		qty + "@" + prc;

	string result;

	if(variety == BO) {
		result = "Bracket Order [" + conciseForm + "|" +
			"t=" + t + "|" + "sl=" + sl + "|" +
			"tr. sl=" + tsl + "]";
	} else if (variety == CO) {
		result = "Cover Order [" + conciseForm + "|" + "trigger=" +
			trigPrc +  "]";
	} else {
		result = "Regular Order [" + conciseForm + "]";
	}

	return result;
}

/*
* Checks whether we have a duplicate signal. This is done to overcome a
* limitation in charting programs, which keep on giving the same signal for
* every tick until the candle is complete.
*/
bool isDuplicateSignal(const string account, const TradeType tradeType, const string symbol) {
	datetime time = readLastOrderTime(account, symbol);

	if(time == 0) {
		return false;
	}

	TradeType lastTradeType = readLastOrderTradeType(account, symbol);
	long difference = TimeLocal() - time;

	if(difference < AT_AVOID_REPEAT_ORDER_DELAY && lastTradeType == tradeType) {
		Print("ERROR: Duplicate signal. Previous order = ", EnumToString(lastTradeType),
			", Current order = ", EnumToString(tradeType), ", symbol = ", symbol);

		if(AT_DEBUG) {
			Print("Last order time is = ", TimeToString(time, TIME_SECONDS));
			Print("Difference of [", difference,
				"] seconds is less than avoid duplicate order duration of [",
				IntegerToString(AT_AVOID_REPEAT_ORDER_DELAY), "] seconds.");
		}

		return true;
	}

	return false;
}

/*****************************************************************************/
/************************** REPEAT ORDER GUARD - END *************************/
/*****************************************************************************/


/*****************************************************************************/
/*********************** PLACE ORDER FUNCTIONS - START ***********************/
/*****************************************************************************/

/*
* An advanced function to place orders.
*
* Returns the BROKER's order id on success. Returns AT_UNCONFIRMED when the
* order reached the broker and the broker never confirmed it -- that order may
* be live, so check the order book rather than sending it again. Returns blank
* only when the order was definitely not placed.
*/
string placeOrderAdvanced(Variety variety, string account,
	Exchange exchange, string symbol,
	TradeType tradeType, OrderType orderType,
	ProductType productType, int quantity,
	double price, double triggerPrice, double target,
	double stoploss, double trailingStoploss,
	int disclosedQuantity, Validity validity, bool amo,
	int strategyId, string comments, bool validate) {

	// Initially order id is blank
	string orderId = "";

	string orderStr = orderString(variety, symbol, tradeType, orderType, quantity,
		price, triggerPrice, target, stoploss, trailingStoploss);

	if(AT_DEBUG) {
		Print("Placing order: ", orderStr);
	}

	if(validate && isDuplicateSignal(account, tradeType, symbol)) {
		Print("Order failed validation: ", orderStr);
		return "";
	}

	// Save order generation time
	string publishTime = IntegerToString(
		convertDateTimeToMillisSinceEpoch(TimeLocal()));

	// Convert data into text in order to build the command
	string priceStr = DoubleToString(price, AT_PRICE_PRECISION);
	string triggerPriceStr = DoubleToString(triggerPrice, AT_PRICE_PRECISION);
	string targetStr = DoubleToString(target, AT_PRICE_PRECISION);
	string stoplossStr = DoubleToString(stoploss, AT_PRICE_PRECISION);
	string trailingStoplossStr = DoubleToString(trailingStoploss, AT_PRICE_PRECISION);

	// Handling for a comma in comments
	StringReplace(comments, AT_COMMA, ";");

	string amoStr = amo ? "true" : "false";

	/*
	* Column three is the publisher id and is deliberately left empty. The file
	* based library generates one so it can refer to an order it has not yet
	* heard back about; here the reply carries the broker's own id, so there is
	* nothing to invent and nothing to reconcile later.
	*
	* Every other column keeps its position, so the server parses this with the
	* same code that has always parsed it.
	*/
	string csv =
		AT_PLACE_ORDER_CMD 		+ AT_COMMA +
		account 								+ AT_COMMA +
		AT_BLANK								+ AT_COMMA +
		EnumToString(variety)			+ AT_COMMA +
		EnumToString(exchange)		+ AT_COMMA +
		symbol 									+ AT_COMMA +
		EnumToString(tradeType)		+ AT_COMMA +
		EnumToString(orderType) 		+ AT_COMMA +
		EnumToString(productType)	+ AT_COMMA +
		IntegerToString(quantity)		+ AT_COMMA +
		priceStr 								+ AT_COMMA +
		triggerPriceStr 						+ AT_COMMA +
		targetStr 								+ AT_COMMA +
		stoplossStr 							+ AT_COMMA +
		trailingStoplossStr 				+ AT_COMMA +
		IntegerToString(disclosedQuantity)		+ AT_COMMA +
		EnumToString(validity) 			+ AT_COMMA +
		amoStr									+ AT_COMMA +
		publishTime							+ AT_COMMA +
		IntegerToString(strategyId)	+ AT_COMMA +
		comments;

	if(AT_DEBUG) {
		Print("Order csv data: ", csv);
	}

	string status = atSendCommand(csv);

	if(status == AT_HTTP_OK) {
		orderId = atPipeField(atHttpResponse, 2);

		saveLastOrderTradeType(account, symbol, tradeType);
		saveLastOrderTime(account, symbol, TimeLocal());

		Print("Order placed: [", orderStr, "], order id: ", orderId);

		return orderId;
	}

	if(atHttpAction == AT_ACTION_CHECK) {
		/*
		* The order reached the broker and nobody confirmed it. This is the one
		* outcome that must not come back as a plain failure: a strategy that
		* treats blank as "it did not go" would place the same order a second
		* time, and both could fill.
		*
		* The repeat order guard is armed as if the order had succeeded, so an
		* unattended chart cannot re-send it on the next tick either.
		*/
		saveLastOrderTradeType(account, symbol, tradeType);
		saveLastOrderTime(account, symbol, TimeLocal());

		Print("AutoTrader: SD-ERR-MT-PLACE: Order NOT CONFIRMED: [", orderStr, "]. ", atHttpMessage);
		Print("AutoTrader: SD-ERR-MT-PLACE: Do not place it again. Check your order book first.");

		return AT_UNCONFIRMED;
	}

	Print("AutoTrader: SD-ERR-MT-PLACE: Order placement failed: [", orderStr, "]. ", atHttpMessage);

	return "";
}

/*
* A function to place regular orders. Returns the broker's order id on
* successful order placement; otherwise returns blank or AT_UNCONFIRMED.
*/
string placeOrder(string account, Exchange exchange, string symbol,
	TradeType tradeType, OrderType orderType, ProductType productType,
	int quantity, double price, double triggerPrice, bool validate) {

	return placeOrderAdvanced(defaultVariety(), account, exchange, symbol,
		tradeType, orderType, productType,
		quantity, price, triggerPrice,
		defaultTarget(), defaultStoploss(), defaultTrailingStoploss(),
		defaultDisclosedQuantity(), defaultValidity(), defaultAmo(),
		defaultStrategyId(), defaultComments(), validate);

}

/*
* A function to place bracket orders. Returns the broker's order id on
* successful order placement; otherwise returns blank or AT_UNCONFIRMED.
*
* If a parameter is not applicable, then either pass blank (for text parameter)
* or zero (for numeric parameter).
*/
string placeBracketOrder(string account, Exchange exchange, string symbol,
	TradeType tradeType, OrderType orderType, int quantity,
	double price, double triggerPrice, double target, double stoploss,
	double trailingStoploss, bool validate) {

	return placeOrderAdvanced(BO, account, exchange, symbol,
		tradeType, orderType, INTRADAY,
		quantity, price, triggerPrice,
		target, stoploss, trailingStoploss,
		defaultDisclosedQuantity(), defaultValidity(), defaultAmo(),
		defaultStrategyId(), defaultComments(), validate);

}

/*
* A function to place cover orders. Returns the broker's order id on
* successful order placement; otherwise returns blank or AT_UNCONFIRMED.
*/
string placeCoverOrder(string account, Exchange exchange, string symbol,
	TradeType tradeType, OrderType orderType, int quantity,
	double price, double triggerPrice, bool validate) {

	return placeOrderAdvanced(CO, account, exchange, symbol,
		tradeType, orderType, INTRADAY,
		quantity, price, triggerPrice,
		defaultTarget(), defaultStoploss(), defaultTrailingStoploss(),
		defaultDisclosedQuantity(), defaultValidity(), defaultAmo(),
		defaultStrategyId(), defaultComments(), validate);

}

/*****************************************************************************/
/************************ PLACE ORDER FUNCTIONS - END ************************/
/*****************************************************************************/


/*****************************************************************************/
/*********************** MODIFY ORDER FUNCTIONS - START **********************/
/*****************************************************************************/

void printOrderModification(string account, string orderId, OrderType orderType,
	int quantity, double price, double triggerPrice) {

	string message = "Modification: ";
	message = message + "[Account = " + account + "]";
	message = message + "[Order Id = " + orderId + "]";

	if(orderType != NULL) {
		message = message + "[OrderType = " + EnumToString(orderType) + "]";
	}

	if(quantity > 0) {
		message = message + "[Quantity = " + IntegerToString(quantity) + "]";
	}

	if(price > 0) {
		message = message + "[Price = " + DoubleToString(price) + "]";
	}

	if(triggerPrice > 0) {
		message = message + "[Trigger Price = " + DoubleToString(triggerPrice) + "]";
	}

	Print(message);
}

/**
* Modifies the order. Returns true only when the server confirms it.
*
* Pass the order id you received from a place...Order() function -- the
* broker's order id.
*
* If a parameter is not applicable, then either pass NULL or zero (for numeric
* parameter).
*/
bool modifyOrder(string account, string orderId, OrderType orderType,
	int quantity, double price, double triggerPrice) {

	string priceStr = DoubleToString(price, AT_PRICE_PRECISION);
	string triggerPriceStr = DoubleToString(triggerPrice, AT_PRICE_PRECISION);
	string orderTypeStr = (orderType == NULL) ? "" : EnumToString(orderType);

	string csv =
		AT_MODIFY_ORDER_BY_ID_CMD	+ AT_COMMA +
		account 									+ AT_COMMA +
		orderId 										+ AT_COMMA +
		orderTypeStr								+ AT_COMMA +
		IntegerToString(quantity)			+ AT_COMMA +
		priceStr 									+ AT_COMMA +
		triggerPriceStr;

	printOrderModification(account, orderId, orderType, quantity, price,
		triggerPrice);

	return atRunCommand(csv, "Order modify [" + orderId + "]");
}

bool modifyOrderPrice(string account, string orderId, double price) {
	return modifyOrder(account, orderId, NULL, 0, price, 0);
}

bool modifyOrderQuantity(string account, string orderId, int quantity) {
	return modifyOrder(account, orderId, NULL, quantity, 0, 0);
}

/*****************************************************************************/
/************************ MODIFY ORDER FUNCTIONS - END ***********************/
/*****************************************************************************/


/*****************************************************************************/
/******************** CANCEL/EXIT ORDER FUNCTIONS - START ********************/
/*****************************************************************************/

/*
* Sends cancel order request to AutoTrader. Pass account & the broker's order
* id. Returns true when the server confirms the cancellation.
*/
bool cancelOrder(string account, string id) {
	if(AT_DEBUG) {
		Print("Cancelling order, order id = ", id);
	}

	string csv =
		AT_CANCEL_ORDER_BY_ID_CMD	+ AT_COMMA +
		account 									+ AT_COMMA +
		id;

	return atRunCommand(csv, "Order cancel [" + id + "]");
}

/*
* Cancels child orders of a bracket or cover order.
* This function is useful for exiting from bracket and cover order.
* Pass the account & the broker's order id you received after placing a
* bracket or cover order.
*/
bool cancelOrderChildren(string account, string id) {
	if(AT_DEBUG) {
		Print("Cancelling child orders, order id = ", id);
	}

	string csv =
		AT_CANCEL_CHILD_ORDER_BY_ID_CMD	+ AT_COMMA +
		account 											+ AT_COMMA +
		id;

	return atRunCommand(csv, "Order cancel children [" + id + "]");
}

/*
* Cancels or exits from order. This function is useful for exiting from bracket
* and cover order. If the order is OPEN, it will be cancelled. If it is
* executed, system will cancel it's child orders; which will result in exiting
* the position.
* Pass account & the broker's order id you received after placing a bracket or
* cover order.
*/
bool cancelOrExitOrder(string account, string id) {
	if(AT_DEBUG) {
		Print("Inside cancelOrExitOrder, order id = ", id);
	}

	// Cancel the Bracket order if it is open
	bool a = cancelOrder(account, id);

	// Exit from bracket order
	bool b = cancelOrderChildren(account, id);

	return (a && b);
}

/*
* Cancels all open orders for the given account. Returns true when the server
* confirms it.
*/
bool cancelAllOrders(string account) {
	if(AT_DEBUG) {
		Print("Cancelling all open orders for account: ", account);
	}

	string csv = AT_CANCEL_ALL_ORDERS_CMD + AT_COMMA + account;

	return atRunCommand(csv, "Cancel all open orders [" + account + "]");
}

/*****************************************************************************/
/********************* CANCEL/EXIT ORDER FUNCTIONS - END *********************/
/*****************************************************************************/


/*****************************************************************************/
/************************ SQUARE OFF FUNCTIONS - START ***********************/
/*****************************************************************************/

/**
* Submits a square-off request for the given position. Returns true when the
* server confirms it.
*
* pseudoAccount - account to which the position belongs
* category - position category (DAY, NET). Pass DAY if you are not sure.
* type - position type (MIS, NRML, CNC, BO, CO)
* exchange - broker independent exchange
* independentSymbol - broker independent symbol
*/
bool squareOffPosition(string pseudoAccount, string category,
	string type, Exchange exchange, string independentSymbol) {

	string positionStr = pseudoAccount 				+ AT_PIPE +
							category							+ AT_PIPE +
							type									+ AT_PIPE +
							EnumToString(exchange)	+ AT_PIPE +
							independentSymbol;

	if(AT_DEBUG) {
		Print("Inside squareOffPosition, position: [", positionStr, "]");
	}

	string csv = AT_SQUARE_OFF_POSITION 		+ AT_COMMA +
			pseudoAccount 							+ AT_COMMA +
			category									+ AT_COMMA +
			type											+ AT_COMMA +
			EnumToString(exchange)			+ AT_COMMA +
			independentSymbol;

	return atRunCommand(csv, "Square-off position [" + positionStr + "]");
}

/**
* Submits a square-off request for the given account. Returns true when the
* server confirms it.
* Server will square-off all open positions in the given account.
*
* pseudoAccount - account to which the position belongs
* category - position category (DAY, NET). Pass DAY if you are not sure.
*/
bool squareOffPortfolio(string pseudoAccount, string category) {

	string portfolioStr = pseudoAccount 	+ AT_PIPE +
						category;

	if(AT_DEBUG) {
		Print("Inside squareOffPortfolio, portfolio: [", portfolioStr, "]");
	}

	string csv = AT_SQUARE_OFF_PORTFOLIO 	+ AT_COMMA +
					pseudoAccount 							+ AT_COMMA +
					category;

	return atRunCommand(csv, "Square-off portfolio [" + portfolioStr + "]");
}

/*****************************************************************************/
/************************* SQUARE OFF FUNCTIONS - END ************************/
/*****************************************************************************/


/*****************************************************************************/
/*********************** ORDER DETAIL FUNCTIONS - START ***********************/
/*****************************************************************************/

/*
* Reads orders and returns a column value for the given order id.
*
* Matched on column 4, the BROKER's order id. The file based library matched on
* column 3, the publisher id it generated before sending the order; this
* library never makes one, because the reply to a placement carries the
* broker's own id.
*/
string readOrderColumn(string pseudoAccount, string orderId, int columnIndex) {
	return atReadColumn(pseudoAccount, AT_DS_ORDERS, orderId, AT_ORDER_ID_COLUMN, columnIndex);
}

/*
* Retrieve order's trading account.
*/
string getOrderTradingAccount(string pseudoAccount, string orderId) {
	return readOrderColumn(pseudoAccount, orderId, 2);
}

/*
* Retrieve order's trading platform id.
*/
string getOrderId(string pseudoAccount, string orderId) {
	return readOrderColumn(pseudoAccount, orderId, 4);
}

/*
* Retrieve order's exchange id.
*/
string getOrderExchangeId(string pseudoAccount, string orderId) {
	return readOrderColumn(pseudoAccount, orderId, 5);
}

/*
* Retrieve order's variety (REGULAR, BO, CO).
*/
Variety getOrderVariety(string pseudoAccount, string orderId) {
	Variety v;
	return StringToEnum(readOrderColumn(pseudoAccount, orderId, 6), v);
}

/*
* Retrieve order's (platform independent) exchange.
*/
Exchange getOrderIndependentExchange(string pseudoAccount, string orderId) {
	Exchange e;
	return StringToEnum(readOrderColumn(pseudoAccount, orderId, 7), e);
}

/*
* Retrieve order's (platform independent) symbol.
*/
string getOrderIndependentSymbol(string pseudoAccount, string orderId) {
	return readOrderColumn(pseudoAccount, orderId, 8);
}

/*
* Retrieve order's trade type (BUY, SELL).
*/
TradeType getOrderTradeType(string pseudoAccount, string orderId) {
	TradeType t;
	return StringToEnum(readOrderColumn(pseudoAccount, orderId, 9), t);
}

/*
* Retrieve order's order type (LIMIT, MARKET, STOP_LOSS, SL_MARKET).
*/
OrderType getOrderOrderType(string pseudoAccount, string orderId) {
	OrderType o;
	return StringToEnum(readOrderColumn(pseudoAccount, orderId, 10), o);
}

/*
* Retrieve order's product type (INTRADAY, DELIVERY, NORMAL).
*/
ProductType getOrderProductType(string pseudoAccount, string orderId) {
	ProductType p;
	return StringToEnum(readOrderColumn(pseudoAccount, orderId, 11), p);
}

/*
* Retrieve order's quantity.
*/
long getOrderQuantity(string pseudoAccount, string orderId) {
	return StringToInteger(readOrderColumn(pseudoAccount, orderId, 12));
}

/*
* Retrieve order's price.
*/
double getOrderPrice(string pseudoAccount, string orderId) {
	return StringToDouble(readOrderColumn(pseudoAccount, orderId, 13));
}

/*
* Retrieve order's trigger price.
*/
double getOrderTriggerPrice(string pseudoAccount, string orderId) {
	return StringToDouble(readOrderColumn(pseudoAccount, orderId, 14));
}

/*
* Retrieve order's filled quantity.
*/
long getOrderFilledQuantity(string pseudoAccount, string orderId) {
	return StringToInteger(readOrderColumn(pseudoAccount, orderId, 15));
}

/*
* Retrieve order's pending quantity.
*/
long getOrderPendingQuantity(string pseudoAccount, string orderId) {
	return StringToInteger(readOrderColumn(pseudoAccount, orderId, 16));
}

/*
* Retrieve order's (platform independent) status.
* (OPEN, COMPLETE, CANCELLED, REJECTED, TRIGGER_PENDING, UNKNOWN)
*/
string getOrderStatus(string pseudoAccount, string orderId) {
	return readOrderColumn(pseudoAccount, orderId, 17);
}

/*
* Retrieve order's status message or rejection reason.
*/
string getOrderStatusMessage(string pseudoAccount, string orderId) {
	return readOrderColumn(pseudoAccount, orderId, 18);
}

/*
* Retrieve order's validity (DAY, IOC).
*/
Validity getOrderValidity(string pseudoAccount, string orderId) {
	Validity v;
	return StringToEnum(readOrderColumn(pseudoAccount, orderId, 19), v);
}

/*
* Retrieve order's average price at which it got traded.
*/
double getOrderAveragePrice(string pseudoAccount, string orderId) {
	return StringToDouble(readOrderColumn(pseudoAccount, orderId, 20));
}

/*
* Retrieve order's parent order id. The id of parent bracket or cover order.
*/
string getOrderParentOrderId(string pseudoAccount, string orderId) {
	return readOrderColumn(pseudoAccount, orderId, 21);
}

/*
* Retrieve order's disclosed quantity.
*/
long getOrderDisclosedQuantity(string pseudoAccount, string orderId) {
	return StringToInteger(readOrderColumn(pseudoAccount, orderId, 22));
}

/*
* Retrieve order's exchange time as a string (YYYY-MM-DD HH:MM:SS.MILLIS).
*/
string getOrderExchangeTime(string pseudoAccount, string orderId) {
	return readOrderColumn(pseudoAccount, orderId, 23);
}

/*
* Retrieve order's platform time as a string (YYYY-MM-DD HH:MM:SS.MILLIS).
*/
string getOrderPlatformTime(string pseudoAccount, string orderId) {
	return readOrderColumn(pseudoAccount, orderId, 24);
}

/*
* Retrieve order's AMO (after market order) flag. (true/false)
*/
bool getOrderAmo(string pseudoAccount, string orderId) {
	string flag = readOrderColumn(pseudoAccount, orderId, 25);
	return (flag == "true" || flag == "True" || flag == "TRUE");	
}

/*
* Retrieve order's comments.
*/
string getOrderComments(string pseudoAccount, string orderId) {
	return readOrderColumn(pseudoAccount, orderId, 26);
}

/*
* Retrieve order's raw (platform specific) status.
*/
string getOrderRawStatus(string pseudoAccount, string orderId) {
	return readOrderColumn(pseudoAccount, orderId, 27);
}

/*
* Retrieve order's (platform specific) exchange.
*/
string getOrderExchange(string pseudoAccount, string orderId) {
	return readOrderColumn(pseudoAccount, orderId, 28);
}

/*
* Retrieve order's (platform specific) symbol.
*/
string getOrderSymbol(string pseudoAccount, string orderId) {
	return readOrderColumn(pseudoAccount, orderId, 29);
}

/*
* Retrieve order's date (DD-MM-YYYY).
*/
string getOrderDay(string pseudoAccount, string orderId) {
	return readOrderColumn(pseudoAccount, orderId, 30);
}

/*
* Retrieve order's trading platform.
*/
string getOrderPlatform(string pseudoAccount, string orderId) {
	return readOrderColumn(pseudoAccount, orderId, 31);
}

/*
* Retrieve order's client id (as received from trading platform).
*/
string getOrderClientId(string pseudoAccount, string orderId) {
	return readOrderColumn(pseudoAccount, orderId, 32);
}

/*
* Retrieve order's stock broker.
*/
string getOrderStockBroker(string pseudoAccount, string orderId) {
	return readOrderColumn(pseudoAccount, orderId, 33);
}

/*
* Checks whether order is open.
* orderId - should be the id returned by placeOrder function when you place an order.
*/
bool isOrderOpen(string pseudoAccount, string orderId) {
	string oStatus = getOrderStatus(pseudoAccount, orderId);
	
	return (StringCompare("OPEN", oStatus, false) == 0) || 
	   (StringCompare("TRIGGER_PENDING", oStatus, false) == 0);
}

/*
* Checks whether order is complete.
* orderId - should be the id returned by placeOrder function when you place an order.
*/
bool isOrderComplete(string pseudoAccount, string orderId) {
	string oStatus = getOrderStatus(pseudoAccount, orderId);
	
	return StringCompare("COMPLETE", oStatus, false) == 0;
}

/*
* Checks whether order is rejected.
* orderId - should be the id returned by placeOrder function when you place an order.
*/
bool isOrderRejected(string pseudoAccount, string orderId) {
	string oStatus = getOrderStatus(pseudoAccount, orderId);
	
	return StringCompare("REJECTED", oStatus, false) == 0;
}

/*
* Checks whether order is cancelled.
* orderId - should be the id returned by placeOrder function when you place an order.
*/
bool isOrderCancelled(string pseudoAccount, string orderId) {
	string oStatus = getOrderStatus(pseudoAccount, orderId);
	
	return StringCompare("CANCELLED", oStatus, false) == 0;
}

/*
* Retrieve order variety.
*/
string getOrderVariety(string pseudoAccount, string orderId) {
	return readOrderColumn(pseudoAccount, orderId, 6);
}

/*
* Retrieve order's broker independent exchange.
*/
string getOrderIndependentExchange(string pseudoAccount, string orderId) {
	return readOrderColumn(pseudoAccount, orderId, 7);
}

/*
* Retrieve order trade type.
*/
string getOrderTradeType(string pseudoAccount, string orderId) {
	return readOrderColumn(pseudoAccount, orderId, 9);
}

/*
* Retrieve order type.
*/
string getOrderOrderType(string pseudoAccount, string orderId) {
	return readOrderColumn(pseudoAccount, orderId, 10);
}

/*
* Retrieve order product type.
*/
string getOrderProductType(string pseudoAccount, string orderId) {
	return readOrderColumn(pseudoAccount, orderId, 11);
}

/*
* Retrieve order validity.
*/
string getOrderValidity(string pseudoAccount, string orderId) {
	return readOrderColumn(pseudoAccount, orderId, 19);
}


/*****************************************************************************/
/*********************** POSITION DETAIL FUNCTIONS - START ***********************/
/*****************************************************************************/

/*
* Reads positions and returns a column value for the given position id.
* Position id is a combination of category, type, independentExchange & independentSymbol.
*
* Column numbers are the same four the file based library used: TYPE is 3,
* CATEGORY 4, INDEPENDENTEXCHANGE 5 and INDEPENDENTSYMBOL 6.
*/
string readPositionColumn(string pseudoAccount,
	string category, string type, Exchange independentExchange,
	string independentSymbol, uint columnIndex) {

	return atReadColumn4(pseudoAccount, AT_DS_POSITIONS,
		category, 4, type, 3,
		EnumToString(independentExchange), 5, independentSymbol, 6,
		(int) columnIndex);
}

/*
* Retrieve positions's trading account.
*/
string getPositionTradingAccount(string pseudoAccount, 
	string category, string type, Exchange independentExchange,	
	string independentSymbol) {
	return readPositionColumn(pseudoAccount, 
		category, type, independentExchange,	independentSymbol, 2);
}

/*
* Retrieve positions's MTM (Mtm calculated by your stock broker).
*/
double getPositionMtm(string pseudoAccount, 
	string category, string type, Exchange independentExchange,	
	string independentSymbol) {
	return StringToDouble(readPositionColumn(pseudoAccount, 
		category, type, independentExchange,	independentSymbol, 7));
}

/*
* Retrieve positions's PNL (Pnl calculated by your stock broker).
*/
double getPositionPnl(string pseudoAccount, 
	string category, string type, Exchange independentExchange,	
	string independentSymbol) {
	return StringToDouble(readPositionColumn(pseudoAccount, 
		category, type, independentExchange,	independentSymbol, 8));
}

/*
* Retrieve positions's AT PNL (Pnl calculated by AutoTrader Web).
*/
double getPositionAtPnl(string pseudoAccount, 
	string category, string type, Exchange independentExchange,	
	string independentSymbol) {
	return StringToDouble(readPositionColumn(pseudoAccount, 
		category, type, independentExchange,	independentSymbol, 31));
}

/*
* Retrieve positions's buy quantity.
*/
long getPositionBuyQuantity(string pseudoAccount, 
	string category, string type, Exchange independentExchange,	
	string independentSymbol) {
	return StringToInteger(readPositionColumn(pseudoAccount, 
		category, type, independentExchange,	independentSymbol, 9));
}

/*
* Retrieve positions's sell quantity.
*/
long getPositionSellQuantity(string pseudoAccount, 
	string category, string type, Exchange independentExchange,	
	string independentSymbol) {
	return StringToInteger(readPositionColumn(pseudoAccount, 
		category, type, independentExchange,	independentSymbol, 10));
}

/*
* Retrieve positions's net quantity.
*/
long getPositionNetQuantity(string pseudoAccount, 
	string category, string type, Exchange independentExchange,	
	string independentSymbol) {
	return StringToInteger(readPositionColumn(pseudoAccount, 
		category, type, independentExchange,	independentSymbol, 11));
}

/*
* Retrieve positions's buy value.
*/
double getPositionBuyValue(string pseudoAccount, 
	string category, string type, Exchange independentExchange,	
	string independentSymbol) {
	return StringToDouble(readPositionColumn(pseudoAccount, 
		category, type, independentExchange,	independentSymbol, 12));
}

/*
* Retrieve positions's sell value.
*/
double getPositionSellValue(string pseudoAccount, 
	string category, string type, Exchange independentExchange,	
	string independentSymbol) {
	return StringToDouble(readPositionColumn(pseudoAccount, 
		category, type, independentExchange,	independentSymbol, 13));
}

/*
* Retrieve positions's net value.
*/
double getPositionNetValue(string pseudoAccount, 
	string category, string type, Exchange independentExchange,	
	string independentSymbol) {
	return StringToDouble(readPositionColumn(pseudoAccount, 
		category, type, independentExchange,	independentSymbol, 14));
}

/*
* Retrieve positions's buy average price.
*/
double getPositionBuyAvgPrice(string pseudoAccount, 
	string category, string type, Exchange independentExchange,	
	string independentSymbol) {
	return StringToDouble(readPositionColumn(pseudoAccount, 
		category, type, independentExchange,	independentSymbol, 15));
}

/*
* Retrieve positions's sell average price.
*/
double getPositionSellAvgPrice(string pseudoAccount, 
	string category, string type, Exchange independentExchange,	
	string independentSymbol) {
	return StringToDouble(readPositionColumn(pseudoAccount, 
		category, type, independentExchange,	independentSymbol, 16));
}

/*
* Retrieve positions's realised pnl.
*/
double getPositionRealisedPnl(string pseudoAccount, 
	string category, string type, Exchange independentExchange,	
	string independentSymbol) {
	return StringToDouble(readPositionColumn(pseudoAccount, 
		category, type, independentExchange,	independentSymbol, 17));
}

/*
* Retrieve positions's unrealised pnl.
*/
double getPositionUnrealisedPnl(string pseudoAccount, 
	string category, string type, Exchange independentExchange,	
	string independentSymbol) {
	return StringToDouble(readPositionColumn(pseudoAccount, 
		category, type, independentExchange,	independentSymbol, 18));
}

/*
* Retrieve positions's overnight quantity.
*/
long getPositionOvernightQuantity(string pseudoAccount, 
	string category, string type, Exchange independentExchange,	
	string independentSymbol) {
	return StringToInteger(readPositionColumn(pseudoAccount, 
		category, type, independentExchange,	independentSymbol, 19));
}

/*
* Retrieve positions's multiplier.
*/
double getPositionMultiplier(string pseudoAccount, 
	string category, string type, Exchange independentExchange,	
	string independentSymbol) {
	return StringToDouble(readPositionColumn(pseudoAccount, 
		category, type, independentExchange,	independentSymbol, 20));
}

/*
* Retrieve positions's LTP.
*/
double getPositionLtp(string pseudoAccount, 
	string category, string type, Exchange independentExchange,	
	string independentSymbol) {
	return StringToDouble(readPositionColumn(pseudoAccount, 
		category, type, independentExchange,	independentSymbol, 21));
}

/*
* Retrieve positions's (platform specific) exchange.
*/
string getPositionExchange(string pseudoAccount, 
	string category, string type, Exchange independentExchange,	
	string independentSymbol) {
	return readPositionColumn(pseudoAccount, 
		category, type, independentExchange,	independentSymbol, 22);
}

/*
* Retrieve positions's (platform specific) symbol.
*/
string getPositionSymbol(string pseudoAccount, 
	string category, string type, Exchange independentExchange,	
	string independentSymbol) {
	return readPositionColumn(pseudoAccount, 
		category, type, independentExchange,	independentSymbol, 23);
}

/*
* Retrieve positions's date (DD-MM-YYYY).
*/
string getPositionDay(string pseudoAccount, 
	string category, string type, Exchange independentExchange,	
	string independentSymbol) {
	return readPositionColumn(pseudoAccount, 
		category, type, independentExchange,	independentSymbol, 24);
}

/*
* Retrieve positions's trading platform.
*/
string getPositionPlatform(string pseudoAccount, 
	string category, string type, Exchange independentExchange,	
	string independentSymbol) {
	return readPositionColumn(pseudoAccount, 
		category, type, independentExchange,	independentSymbol, 25);
}

/*
* Retrieve positions's account id as received from trading platform.
*/
string getPositionAccountId(string pseudoAccount, 
	string category, string type, Exchange independentExchange,	
	string independentSymbol) {
	return readPositionColumn(pseudoAccount, 
		category, type, independentExchange,	independentSymbol, 26);
}

/*
* Retrieve positions's stock broker.
*/
string getPositionStockBroker(string pseudoAccount, 
	string category, string type, Exchange independentExchange,	
	string independentSymbol) {
	return readPositionColumn(pseudoAccount, 
		category, type, independentExchange,	independentSymbol, 28);
}

/*
* Retrieve position state.
*/
string getPositionState(string pseudoAccount,
	string category, string type, Exchange independentExchange,
	string independentSymbol) {

	return readPositionColumn(pseudoAccount, category, type, independentExchange,
		independentSymbol, 29);
}

/*
* Retrieve position direction.
*/
string getPositionDirection(string pseudoAccount,
	string category, string type, Exchange independentExchange,
	string independentSymbol) {

	return readPositionColumn(pseudoAccount, category, type, independentExchange,
		independentSymbol, 30);
}


/*****************************************************************************/
/*********************** MARGIN DETAIL FUNCTIONS - START ***********************/
/*****************************************************************************/

/*
* Reads margins and returns a column value for the given margin category.
*/
string readMarginColumn(string pseudoAccount, string category, uint columnIndex) {
	return atReadColumn(pseudoAccount, AT_DS_MARGINS, category, 3, (int) columnIndex);
}

/*
* Retrieve margin funds.
*/
double getMarginFunds(string pseudoAccount, string category) {
	return StringToDouble(readMarginColumn(pseudoAccount, category, 4));
}

/*
* Retrieve margin utilized.
*/
double getMarginUtilized(string pseudoAccount, string category) {
	return StringToDouble(readMarginColumn(pseudoAccount, category, 5));
}

/*
* Retrieve margin available.
*/
double getMarginAvailable(string pseudoAccount, string category) {
	return StringToDouble(readMarginColumn(pseudoAccount, category, 6));
}

/*
* Retrieve margin funds for equity category.
*/
double getMarginFundsEquity(string pseudoAccount) {
	return StringToDouble(readMarginColumn(pseudoAccount, AT_MARGIN_EQUITY, 4));
}

/*
* Retrieve margin utilized for equity category.
*/
double getMarginUtilizedEquity(string pseudoAccount) {
	return StringToDouble(readMarginColumn(pseudoAccount, AT_MARGIN_EQUITY, 5));
}

/*
* Retrieve margin available for equity category.
*/
double getMarginAvailableEquity(string pseudoAccount) {
	return StringToDouble(readMarginColumn(pseudoAccount, AT_MARGIN_EQUITY, 6));
}

/*
* Retrieve margin funds for commodity category.
*/
double getMarginFundsCommodity(string pseudoAccount) {
	return StringToDouble(readMarginColumn(pseudoAccount, AT_MARGIN_COMMODITY, 4));
}

/*
* Retrieve margin utilized for commodity category.
*/
double getMarginUtilizedCommodity(string pseudoAccount) {
	return StringToDouble(readMarginColumn(pseudoAccount, AT_MARGIN_COMMODITY, 5));
}

/*
* Retrieve margin available for commodity category.
*/
double getMarginAvailableCommodity(string pseudoAccount) {
	return StringToDouble(readMarginColumn(pseudoAccount, AT_MARGIN_COMMODITY, 6));
}

/*
* Retrieve margin funds for entire account.
*/
double getMarginFundsAll(string pseudoAccount) {
	return StringToDouble(readMarginColumn(pseudoAccount, AT_MARGIN_ALL, 4));
}

/*
* Retrieve margin utilized for entire account.
*/
double getMarginUtilizedAll(string pseudoAccount) {
	return StringToDouble(readMarginColumn(pseudoAccount, AT_MARGIN_ALL, 5));
}

/*
* Retrieve margin available for entire account.
*/
double getMarginAvailableAll(string pseudoAccount) {
	return StringToDouble(readMarginColumn(pseudoAccount, AT_MARGIN_ALL, 6));
}

/*
* Retrieve margin total for equity category.
*/
double getMarginTotalEquity(string pseudoAccount) {
	return StringToDouble(readMarginColumn(pseudoAccount, AT_MARGIN_EQUITY, 9));
}

/*
* Retrieve margin total for commodity category.
*/
double getMarginTotalCommodity(string pseudoAccount) {
	return StringToDouble(readMarginColumn(pseudoAccount, AT_MARGIN_COMMODITY, 9));
}

/*
* Retrieve margin total for entire account.
*/
double getMarginTotalAll(string pseudoAccount) {
	return StringToDouble(readMarginColumn(pseudoAccount, AT_MARGIN_ALL, 9));
}

/*
* Retrieve margin net for equity category.
*/
double getMarginNetEquity(string pseudoAccount) {
	return StringToDouble(readMarginColumn(pseudoAccount, AT_MARGIN_EQUITY, 10));
}

/*
* Retrieve margin net for commodity category.
*/
double getMarginNetCommodity(string pseudoAccount) {
	return StringToDouble(readMarginColumn(pseudoAccount, AT_MARGIN_COMMODITY, 10));
}

/*
* Retrieve margin net for entire account.
*/
double getMarginNetAll(string pseudoAccount) {
	return StringToDouble(readMarginColumn(pseudoAccount, AT_MARGIN_ALL, 10));
}

/*
* Retrieve margin span for equity category.
*/
double getMarginSpanEquity(string pseudoAccount) {
	return StringToDouble(readMarginColumn(pseudoAccount, AT_MARGIN_EQUITY, 11));
}

/*
* Retrieve margin span for commodity category.
*/
double getMarginSpanCommodity(string pseudoAccount) {
	return StringToDouble(readMarginColumn(pseudoAccount, AT_MARGIN_COMMODITY, 11));
}

/*
* Retrieve margin span for entire account.
*/
double getMarginSpanAll(string pseudoAccount) {
	return StringToDouble(readMarginColumn(pseudoAccount, AT_MARGIN_ALL, 11));
}

/*
* Retrieve margin exposure for equity category.
*/
double getMarginExposureEquity(string pseudoAccount) {
	return StringToDouble(readMarginColumn(pseudoAccount, AT_MARGIN_EQUITY, 12));
}

/*
* Retrieve margin exposure for commodity category.
*/
double getMarginExposureCommodity(string pseudoAccount) {
	return StringToDouble(readMarginColumn(pseudoAccount, AT_MARGIN_COMMODITY, 12));
}

/*
* Retrieve margin exposure for entire account.
*/
double getMarginExposureAll(string pseudoAccount) {
	return StringToDouble(readMarginColumn(pseudoAccount, AT_MARGIN_ALL, 12));
}

/*
* Retrieve margin collateral for equity category.
*/
double getMarginCollateralEquity(string pseudoAccount) {
	return StringToDouble(readMarginColumn(pseudoAccount, AT_MARGIN_EQUITY, 13));
}

/*
* Retrieve margin collateral for commodity category.
*/
double getMarginCollateralCommodity(string pseudoAccount) {
	return StringToDouble(readMarginColumn(pseudoAccount, AT_MARGIN_COMMODITY, 13));
}

/*
* Retrieve margin collateral for entire account.
*/
double getMarginCollateralAll(string pseudoAccount) {
	return StringToDouble(readMarginColumn(pseudoAccount, AT_MARGIN_ALL, 13));
}

/*
* Retrieve margin payin for equity category.
*/
double getMarginPayinEquity(string pseudoAccount) {
	return StringToDouble(readMarginColumn(pseudoAccount, AT_MARGIN_EQUITY, 14));
}

/*
* Retrieve margin payin for commodity category.
*/
double getMarginPayinCommodity(string pseudoAccount) {
	return StringToDouble(readMarginColumn(pseudoAccount, AT_MARGIN_COMMODITY, 14));
}

/*
* Retrieve margin payin for entire account.
*/
double getMarginPayinAll(string pseudoAccount) {
	return StringToDouble(readMarginColumn(pseudoAccount, AT_MARGIN_ALL, 14));
}

/*
* Retrieve margin payout for equity category.
*/
double getMarginPayoutEquity(string pseudoAccount) {
	return StringToDouble(readMarginColumn(pseudoAccount, AT_MARGIN_EQUITY, 15));
}

/*
* Retrieve margin payout for commodity category.
*/
double getMarginPayoutCommodity(string pseudoAccount) {
	return StringToDouble(readMarginColumn(pseudoAccount, AT_MARGIN_COMMODITY, 15));
}

/*
* Retrieve margin payout for entire account.
*/
double getMarginPayoutAll(string pseudoAccount) {
	return StringToDouble(readMarginColumn(pseudoAccount, AT_MARGIN_ALL, 15));
}

/*
* Retrieve margin adhoc for equity category.
*/
double getMarginAdhocEquity(string pseudoAccount) {
	return StringToDouble(readMarginColumn(pseudoAccount, AT_MARGIN_EQUITY, 16));
}

/*
* Retrieve margin adhoc for commodity category.
*/
double getMarginAdhocCommodity(string pseudoAccount) {
	return StringToDouble(readMarginColumn(pseudoAccount, AT_MARGIN_COMMODITY, 16));
}

/*
* Retrieve margin adhoc for entire account.
*/
double getMarginAdhocAll(string pseudoAccount) {
	return StringToDouble(readMarginColumn(pseudoAccount, AT_MARGIN_ALL, 16));
}

/*
* Retrieve margin realised mtm for equity category.
*/
double getMarginRealisedMtmEquity(string pseudoAccount) {
	return StringToDouble(readMarginColumn(pseudoAccount, AT_MARGIN_EQUITY, 17));
}

/*
* Retrieve margin realised mtm for commodity category.
*/
double getMarginRealisedMtmCommodity(string pseudoAccount) {
	return StringToDouble(readMarginColumn(pseudoAccount, AT_MARGIN_COMMODITY, 17));
}

/*
* Retrieve margin realised mtm for entire account.
*/
double getMarginRealisedMtmAll(string pseudoAccount) {
	return StringToDouble(readMarginColumn(pseudoAccount, AT_MARGIN_ALL, 17));
}

/*
* Retrieve margin unrealised mtm for equity category.
*/
double getMarginUnrealisedMtmEquity(string pseudoAccount) {
	return StringToDouble(readMarginColumn(pseudoAccount, AT_MARGIN_EQUITY, 18));
}

/*
* Retrieve margin unrealised mtm for commodity category.
*/
double getMarginUnrealisedMtmCommodity(string pseudoAccount) {
	return StringToDouble(readMarginColumn(pseudoAccount, AT_MARGIN_COMMODITY, 18));
}

/*
* Retrieve margin unrealised mtm for entire account.
*/
double getMarginUnrealisedMtmAll(string pseudoAccount) {
	return StringToDouble(readMarginColumn(pseudoAccount, AT_MARGIN_ALL, 18));

/*****************************************************************************/
/*********************** HOLDING DETAIL FUNCTIONS - START ***********************/
/*****************************************************************************/

/*
* Reads holdings and returns a column value for the given symbol.
*
* Matched on column 5, SYMBOL. The file based library matched on column 3,
* which is the holding's numeric id -- so a symbol never matched anything and
* every getHolding...() call returned blank. Fixed here rather than carried
* over.
*/
string readHoldingColumn(string pseudoAccount, string symbol, uint columnIndex) {
	return atReadColumn(pseudoAccount, AT_DS_HOLDINGS, symbol, 5, (int) columnIndex);
}

/*
* Retrieve holding exchange.
*/
string getHoldingExchange(string pseudoAccount, string symbol) {
	return readHoldingColumn(pseudoAccount, symbol, 4);
}

/*
* Retrieve holding ISIN.
*/
string getHoldingIsin(string pseudoAccount, string symbol) {
	return readHoldingColumn(pseudoAccount, symbol, 6);
}

/*
* Retrieve holding quantity.
*/
long getHoldingQuantity(string pseudoAccount, string symbol) {
	return StringToInteger(readHoldingColumn(pseudoAccount, symbol, 7));
}

/*
* Retrieve holding T1 quantity.
*/
long getHoldingT1Quantity(string pseudoAccount, string symbol) {
	return StringToInteger(readHoldingColumn(pseudoAccount, symbol, 8));
}

/*
* Retrieve holding PNL.
*/
double getHoldingPnl(string pseudoAccount, string symbol) {
	return StringToDouble(readHoldingColumn(pseudoAccount, symbol, 9));
}

/*
* Retrieve holding product.
*/
string getHoldingProduct(string pseudoAccount, string symbol) {
	return readHoldingColumn(pseudoAccount, symbol, 10);
}

/*
* Retrieve holding collateral type.
*/
string getHoldingCollateralType(string pseudoAccount, string symbol) {
	return readHoldingColumn(pseudoAccount, symbol, 11);
}

/*
* Retrieve holding collateral quantity.
*/
long getHoldingCollateralQuantity(string pseudoAccount, string symbol) {
	return StringToInteger(readHoldingColumn(pseudoAccount, symbol, 12));
}

/*
* Retrieve holding haircut.
*/
double getHoldingHaircut(string pseudoAccount, string symbol) {
	return StringToDouble(readHoldingColumn(pseudoAccount, symbol, 13));
}

/*
* Retrieve holding average price.
*/
double getHoldingAvgPrice(string pseudoAccount, string symbol) {
	return StringToDouble(readHoldingColumn(pseudoAccount, symbol, 14));
}

/*
* Retrieve holding instrument token.
*/
string getHoldingInstToken(string pseudoAccount, string symbol) {
	return readHoldingColumn(pseudoAccount, symbol, 15);
}

/*
* Retrieve holding symbol LTP.
*/
double getHoldingLtp(string pseudoAccount, string symbol) {
	return StringToDouble(readHoldingColumn(pseudoAccount, symbol, 21));
}

/*
* Retrieve holding current value.
*/
double getHoldingCurrentValue(string pseudoAccount, string symbol) {
	return StringToDouble(readHoldingColumn(pseudoAccount, symbol, 22));
}

#endif
