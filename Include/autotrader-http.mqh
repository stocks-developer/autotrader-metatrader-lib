/******************************************************************************
*
* AutoTrader Web API library -- direct (HTTP) version.
* DO NOT MODIFY THIS FILE
* Version: 1.0
*
* Include this INSTEAD OF autotrader.mqh to trade without any extra program on
* your computer:
*
*     #include <autotrader-http.mqh>
*
* Then put your API key in autotrader-http-config.mqh. That is the whole setup
* -- there is no folder to configure and nothing else to keep running.
*
* Everything else stays as it was. The function names, their arguments and what
* they return are the same, so an existing strategy changes one line. The
* differences are listed at the top of autotrader-http-api.mqh; the important
* one is that placeOrder() now returns the broker's own order id.
*
* TWO THINGS METATRADER NEEDS FROM YOU
*
* 1. Allow the address. Tools -> Options -> Expert Advisors -> "Allow WebRequest
*    for listed URL", then add:
*
*        https://apix.stocksdeveloper.in
*
*    Without it MetaTrader blocks every request and nothing is sent.
*
* 2. Run your strategy as an Expert Advisor or a Script. MetaTrader does not
*    allow web requests from a custom indicator, and the Strategy Tester cannot
*    make them at all -- so a back-test places no orders.
*
* Works with MetaTrader 4 (build 600 or newer) and MetaTrader 5.
*
******************************************************************************/

#ifndef AUTOTRADER_HTTP_MQH
#define AUTOTRADER_HTTP_MQH

/* Import public metatrader libraries */

#include <conversion-util.mqh>

/* Import AutoTrader specific metatrader libraries */

#include <autotrader-defaults.mqh>
#include <autotrader-http-config.mqh>
#include <autotrader-http-transport.mqh>
#include <autotrader-http-api.mqh>

/**
* Says plainly when the key has not been filled in.
*
* Without this the first symptom is an order that does not appear, and the
* reason for it is a rejection nobody sees. Better to be told once, in the
* Experts tab, that the one setup step was missed.
*
* Call it from OnInit(). It returns false when the library cannot work, so a
* strategy can refuse to start rather than run blind.
*/
bool autoTraderReady() {
	if(AT_API_KEY == "<API_KEY>" || StringLen(AT_API_KEY) == 0) {
		Print("AutoTrader: SD-ERR-MT-CONFIG: No API key. Open autotrader-http-config.mqh ",
			"and set AT_API_KEY to the key from your AutoTrader Web account settings.");

		return false;
	}

	/* Prints its own reason when the answer is no. */
	return atHttpCanSend();
}

#endif
