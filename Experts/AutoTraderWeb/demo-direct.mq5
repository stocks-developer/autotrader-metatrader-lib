//+----------------------------------------------------------------------+
//|                                                  demo-direct.mq5 					|
//|                                                       AutoTrader Web 				|
//|                            http://stocksdeveloper.in/autotrader-web 	|
//+----------------------------------------------------------------------+
#property copyright "AutoTrader"
#property link      "http://stocksdeveloper.in/autotrader-web"
#property version   "1.00"

/*********************************************************************
* The direct version of demo.mq5. One line differs -- the include --
* and there is no other program to install or keep running.
*
* BEFORE THIS WILL WORK
*
* 1. Put your API key in Include/autotrader-http-config.mqh.
*
* 2. Allow the address in MetaTrader:
*    Tools -> Options -> Expert Advisors -> "Allow WebRequest for listed
*    URL", then add https://apix.stocksdeveloper.in
*
* 3. Run this as an Expert Advisor, not as an indicator, and not in the
*    Strategy Tester -- MetaTrader does not allow web requests from
*    either.
*********************************************************************/

#include <autotrader-http.mqh>

int OnInit()
  {
	/*
	* Says in the Experts tab exactly what is missing -- an unset API key,
	* an indicator, the tester -- rather than letting every later call fail
	* for a reason nobody can see.
	*/
	if(!autoTraderReady()) {
		return(INIT_FAILED);
	}

	// placeOrderExample();

	// readOrderExample();

	// readPositionExample();

	// readMarginExample();

	// readHoldingExample();

	// modifyOrderPriceExample();

	// cancelOrderExample();

	return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
  }

void OnTick()
  {
  }

/*********************************************************************
* Placing an order, and the three answers you can get back.
*
* This is the one real difference from the bridge library, and it is
* worth handling properly: an order id means it is placed, a blank means
* it is not, and AT_UNCONFIRMED means nobody knows yet.
*********************************************************************/
void placeOrderExample()
  {
	string orderId = placeOrder(AT_ACCOUNT, AT_EXCHANGE, AT_SYMBOL,
		BUY, MARKET, AT_PRODUCT_TYPE, AT_QUANTITY, 0, 0, true);

	handleOrderResult(orderId);
  }

/*
* The three outcomes, spelled out.
*/
void handleOrderResult(const string orderId)
  {
	if(orderId == AT_UNCONFIRMED) {
		/*
		* The order reached your broker and the broker never confirmed it.
		* It may well be live. DO NOT place it again from here -- look at
		* your order book, and let a human decide.
		*/
		Print("Order was sent but not confirmed. Check the order book before repeating it.");
		return;
	}

	if(orderId == "") {
		// Definitely not placed. Safe to retry if your strategy wants to.
		Print("Order was not placed.");
		return;
	}

	// Placed. This is the BROKER's order id, the same one your broker shows.
	Print("Order placed, id = ", orderId);

	string status = getOrderStatus(AT_ACCOUNT, orderId);
	Print("Order status = ", status);
  }

/*********************************************************************
* Reading your portfolio. Identical to the bridge library.
*********************************************************************/
void readOrderExample()
  {
	string orderId = "REPLACE-WITH-A-REAL-ORDER-ID";

	Print("Status          = ", getOrderStatus(AT_ACCOUNT, orderId));
	Print("Filled quantity = ", getOrderFilledQuantity(AT_ACCOUNT, orderId));
	Print("Average price   = ", getOrderAveragePrice(AT_ACCOUNT, orderId));
	Print("Status message  = ", getOrderStatusMessage(AT_ACCOUNT, orderId));
  }

void readPositionExample()
  {
	string category = "DAY";
	string type = "MIS";

	Print("Net quantity = ", getPositionNetQuantity(AT_ACCOUNT, category, type,
		AT_EXCHANGE, AT_SYMBOL));
	Print("M2M          = ", getPositionMtm(AT_ACCOUNT, category, type,
		AT_EXCHANGE, AT_SYMBOL));
	Print("P&L          = ", getPositionPnl(AT_ACCOUNT, category, type,
		AT_EXCHANGE, AT_SYMBOL));
  }

void readMarginExample()
  {
	Print("Funds     = ", getMarginFunds(AT_ACCOUNT, AT_MARGIN_EQUITY));
	Print("Utilized  = ", getMarginUtilized(AT_ACCOUNT, AT_MARGIN_EQUITY));
	Print("Available = ", getMarginAvailable(AT_ACCOUNT, AT_MARGIN_EQUITY));
  }

void readHoldingExample()
  {
	Print("Quantity   = ", getHoldingQuantity(AT_ACCOUNT, AT_SYMBOL));
	Print("Avg price  = ", getHoldingAvgPrice(AT_ACCOUNT, AT_SYMBOL));
	Print("P&L        = ", getHoldingPnl(AT_ACCOUNT, AT_SYMBOL));
  }

/*********************************************************************
* Modifying and cancelling.
*
* Pass the order id that placeOrder() returned -- the broker's id.
*********************************************************************/
void modifyOrderPriceExample()
  {
	string orderId = "REPLACE-WITH-A-REAL-ORDER-ID";

	if(modifyOrderPrice(AT_ACCOUNT, orderId, 100.50)) {
		Print("Price modified.");
	}
  }

void cancelOrderExample()
  {
	string orderId = "REPLACE-WITH-A-REAL-ORDER-ID";

	if(cancelOrder(AT_ACCOUNT, orderId)) {
		Print("Order cancelled.");
	}
  }
