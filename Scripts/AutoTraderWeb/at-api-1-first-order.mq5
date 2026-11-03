#property script_show_inputs

#include <autotrader-http.mqh>

void OnStart()
  {
	if(!autoTraderReady()) {
		return;
	}

	string orderId = placeOrder(AT_ACCOUNT, AT_EXCHANGE, AT_SYMBOL,
		BUY, MARKET, AT_PRODUCT_TYPE, AT_QUANTITY, 0, 0, true);

	if(orderId == AT_UNCONFIRMED) {
		// It may be live. Do NOT send it again: check your order book.
		Print("Sent but not confirmed. Check the order book.");
	} else if(orderId == "") {
		// Not placed. The Experts tab says why.
		Print("Order was not placed.");
	} else {
		// Placed. This is your broker's own order id.
		Print("Order placed: ", orderId);
	}
  }
