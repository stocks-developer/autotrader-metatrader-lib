#property script_show_inputs

#include <autotrader-http.mqh>

input double LIMIT_PRICE = 5;	// Limit price (far from the market, so it stays open)
input double NEW_PRICE = 6;		// New limit price

void OnStart()
  {
	string orderId = placeOrder(AT_ACCOUNT, AT_EXCHANGE, AT_SYMBOL,
		BUY, LIMIT, AT_PRODUCT_TYPE, AT_QUANTITY, LIMIT_PRICE, 0, true);

	if(orderId == "" || orderId == AT_UNCONFIRMED) {
		return;
	}

	Print("Status: ", getOrderStatus(AT_ACCOUNT, orderId));
	Sleep(20000);

	if(modifyOrderPrice(AT_ACCOUNT, orderId, NEW_PRICE)) {
		Print("Price changed.");
	}

	Sleep(20000);

	if(cancelOrder(AT_ACCOUNT, orderId)) {
		Print("Order cancelled.");
	}
  }
