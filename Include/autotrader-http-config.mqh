/******************************************************************************
*
* AutoTrader Web -- settings for the direct (HTTP) library.
*
* THIS IS THE ONLY FILE YOU EDIT. Put your API key in it, save, and recompile
* your Expert Advisor.
*
* Get your API key from your account settings:
*   https://webx.stocksdeveloper.in/
*
* Version: 1.0
*
******************************************************************************/

#ifndef AUTOTRADER_HTTP_CONFIG_MQH
#define AUTOTRADER_HTTP_CONFIG_MQH

/******************************************************************************
* YOUR API KEY.
*
* Treat it like a password. Anyone holding it can place orders in your
* accounts. Do not share a strategy file that still has your key in it, and do
* not post it on a forum when asking for help.
******************************************************************************/

string AT_API_KEY = "<API_KEY>";

/******************************************************************************
* Where the requests go. Leave this alone unless support asks you to change it.
*
* MetaTrader will refuse to call any address that is not on its own allowed
* list. Add this exact address in:
*
*   Tools -> Options -> Expert Advisors -> Allow WebRequest for listed URL
*
* If you skip that step every request fails with error 4014 and nothing is
* sent. The library says so in plain words the first time it happens.
******************************************************************************/

string AT_BASE_URL = "https://apix.stocksdeveloper.in";

/******************************************************************************
* How long the library re-uses portfolio data before asking the server again,
* in seconds.
*
* Your strategy may call twenty different get...() functions on every tick.
* Each one is answered from the copy held here, so a tick costs one request per
* dataset instead of twenty.
*
* Lowering these does NOT get you fresher data. The server allows roughly one
* portfolio request per second per account and answers anything faster than
* that from its own copy, so a smaller number here buys extra requests and the
* same numbers. Raise them if you trade slowly and want less traffic.
*
* Holdings barely move during the day, which is why they are refreshed rarely.
******************************************************************************/

int AT_TTL_ORDERS = 2;

int AT_TTL_POSITIONS = 2;

int AT_TTL_MARGINS = 30;

int AT_TTL_HOLDINGS = 300;

/******************************************************************************
* How long to wait for the server, in milliseconds.
*
* A read is quick. A command is not: the server sends the order to your broker
* and waits for the broker's answer before replying, so it needs the longer
* allowance.
*
* AT_HTTP_TIMEOUT_COMMAND must stay ABOVE the server's own 25 second deadline.
* If MetaTrader gives up first you lose the one thing worth having -- the
* server's own account of what happened to the order -- and are left unable to
* tell a rejected order from a live one.
******************************************************************************/

int AT_HTTP_TIMEOUT_READ = 10000;

int AT_HTTP_TIMEOUT_COMMAND = 30000;

/******************************************************************************
* Safety limit on how many rows one dataset may hold. A portfolio never comes
* close to this; it exists so a malformed reply can never spin a chart.
******************************************************************************/

int AT_HTTP_MAX_ROWS = 2000;

/******************************************************************************
* How far to read along the header when resolving a column name.
*
* The widest dataset the server sends is orders, at 33 columns, so this is
* generous. It is only a stop so that a malformed header cannot spin a chart:
* the scan ends at the first empty column anyway.
******************************************************************************/

int AT_HTTP_MAX_COLUMNS = 60;

/******************************************************************************
* Print every request and reply to the Experts tab.
*
* Useful when setting up, noisy afterwards. It does NOT print your API key.
******************************************************************************/

bool AT_HTTP_DEBUG = false;

#endif
