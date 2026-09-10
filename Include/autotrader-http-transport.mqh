/******************************************************************************
*
* AutoTrader Web -- HTTP transport for the direct MetaTrader library.
* DO NOT MODIFY THIS FILE
* Version: 1.0
*
* Everything that talks to the network lives here. The functions above it in
* autotrader-http-api.mqh never call WebRequest directly, so there is exactly
* one place where a request is built, sent, judged and remembered.
*
* WHAT METATRADER DEMANDS BEFORE ANY OF THIS WORKS
*
* 1. The address must be on the terminal's allowed list:
*      Tools -> Options -> Expert Advisors -> Allow WebRequest for listed URL
*    Without it every call fails with error 4014 and nothing leaves the
*    machine. This is the single most common setup mistake, so it gets its own
*    message rather than being reported as "could not connect".
*
* 2. WebRequest cannot be called from a custom INDICATOR, on either MT4 or MT5.
*    Put your strategy in an Expert Advisor or a Script. The library says so
*    once, on start-up, rather than letting every call fail silently.
*
* 3. WebRequest does not work in the Strategy Tester. A back-test therefore
*    places no orders and reads no portfolio -- which is the safe outcome, and
*    much better than a back-test quietly sending live orders. Detected and
*    reported once.
*
******************************************************************************/

#ifndef AUTOTRADER_HTTP_TRANSPORT_MQH
#define AUTOTRADER_HTTP_TRANSPORT_MQH

/******************************* CONSTANTS ***********************************/

/*
* How a reply is classified. Every response falls into exactly one of these,
* decided on the first few characters -- see atClassify() for why that is
* enough to tell them apart.
*/
#define AT_HTTP_CSV                 "CSV"
#define AT_HTTP_EMPTY               "EMPTY"
#define AT_HTTP_OK                  "OK"
#define AT_HTTP_ERROR               "ERROR"
#define AT_HTTP_AUTH                "AUTH"
#define AT_HTTP_UNREACHABLE         "UNREACHABLE"
#define AT_HTTP_BLOCKED             "BLOCKED"

/* What the server says to do about a failure. */
#define AT_ACTION_RETRY             "retry"
#define AT_ACTION_USER              "user"
#define AT_ACTION_CHECK             "check"

/*
* Returned by placeOrder() when the order reached the broker and the broker
* never confirmed it. It is deliberately NOT blank: a strategy that reads blank
* as failure would place the order a second time, and there is real money on
* the other side of that. See the note on placeOrder().
*/
#define AT_UNCONFIRMED              "UNCONFIRMED"

/* First field of every structured reply. */
#define AT_SD_ERROR                 "SD-ERROR"
#define AT_SD_OK                    "SD-OK"

/*
* First column of every portfolio CSV we serve, and the positive test for "this
* is data". Orders, positions, margins and holdings all begin their header row
* with it, and no error reply can: an error starts with SD-, an authentication
* failure with a brace, a gateway page with an angle bracket.
*/
#define AT_CSV_HEADER               "PSEUDOACCOUNT"

/*
* Command verbs that address an order by the BROKER's order id.
*
* Defined here rather than beside the others in autotrader-defaults.mqh because
* only a direct client can use them: they exist for a client that has no
* publisher id to give, which is exactly what this transport is. The file based
* library keeps AT_MODIFY_ORDER_CMD and friends, untouched.
*/
#define AT_MODIFY_ORDER_BY_ID_CMD          "MODIFY_ORDER_BY_ID"
#define AT_CANCEL_ORDER_BY_ID_CMD          "CANCEL_ORDER_BY_ID"
#define AT_CANCEL_CHILD_ORDER_BY_ID_CMD    "CANCEL_CHILD_ORDER_BY_ID"

/* Dataset names. These are the paths under /csv as well. */
#define AT_DS_ORDERS                "orders"
#define AT_DS_POSITIONS             "positions"
#define AT_DS_MARGINS               "margins"
#define AT_DS_HOLDINGS              "holdings"

/*
* MetaTrader's error for "this call is not allowed", which is what a missing
* entry in the allowed-URL list produces. Named here so the one setup mistake
* everybody makes is reported as itself.
*/
#define AT_ERR_WEBREQUEST_BLOCKED   4014

static string AT_HTTP_HEX = "0123456789ABCDEF";

/******************************* STATE ***************************************/

/*
* Set by atHttpPost(): false when the request never left the machine at all.
*
* Needed because an unreachable server and an account with no orders both hand
* back an empty string, and treating a dead connection as "you have no orders"
* is how a strategy ends up trading on the belief that its position is flat.
*/
bool atHttpReached = false;

/* Details of the last failure, for the caller to log or show. */
string atHttpMessage = "";

string atHttpAction = "";

/* The last reply, for a caller that needs the order id out of it. */
string atHttpResponse = "";

/* Last HTTP status code, or -1 when the request never left the machine. */
int atHttpStatusCode = 0;

/* So the start-up warnings are printed once, not on every tick. */
bool atHttpEnvironmentReported = false;

/******************************* PLUMBING ************************************/

void atHttpTrace(const string message) {
	if(AT_HTTP_DEBUG) {
		Print("AutoTrader: ", message);
	}
}

/**
* Says once whether this program can use the network at all.
*
* Both answers are worth having early. In the Strategy Tester nothing will ever
* be sent, and a trader watching a back-test place no orders deserves to be
* told why rather than left guessing. In an indicator nothing will ever be sent
* either, and that one is a mistake to correct rather than a limitation to
* accept.
*
* Returns true when requests can actually go out.
*/
bool atHttpCanSend() {
	bool tester = (bool) MQLInfoInteger(MQL_TESTER);
	bool indicator = (MQLInfoInteger(MQL_PROGRAM_TYPE) == PROGRAM_INDICATOR);

	if(tester || indicator) {
		if(!atHttpEnvironmentReported) {
			atHttpEnvironmentReported = true;

			if(tester) {
				Print("AutoTrader: SD-ERR-MT-ENV: the Strategy Tester cannot make web requests, ",
					"so no orders are placed and no portfolio is read during a back-test.");
			} else {
				Print("AutoTrader: SD-ERR-MT-ENV: MetaTrader does not allow web requests from an ",
					"indicator. Move your strategy into an Expert Advisor or a Script.");
			}
		}

		return false;
	}

	return true;
}

/**
* Percent-encodes a value for a form body.
*
* Not optional. Symbols legitimately contain characters that would otherwise
* end the field or start a new one -- M&M is a real NSE symbol, and an
* unencoded ampersand there would silently truncate the order.
*
* Encodes BYTES rather than characters, so a non-ASCII character in a comment
* survives the trip instead of being mangled into something the server cannot
* decode.
*/
string atUrlEncode(const string text) {
	if(StringLen(text) == 0) {
		return "";
	}

	uchar bytes[];

	/*
	* WHOLE_ARRAY includes the terminating zero, which must not be sent -- hence
	* the -1. Getting this wrong appends a %00 to every field, and the server
	* rejects the symbol without ever saying why.
	*/
	int total = StringToCharArray(text, bytes, 0, WHOLE_ARRAY, CP_UTF8) - 1;

	if(total < 0) {
		total = 0;
	}

	string result = "";

	for(int i = 0; i < total; i++) {
		uchar code = bytes[i];

		if((code >= '0' && code <= '9') || (code >= 'A' && code <= 'Z') ||
			(code >= 'a' && code <= 'z') || code == '-' || code == '_' ||
			code == '.' || code == '~') {

			result = result + CharToString(code);
		} else {
			result = result + "%" +
				StringSubstr(AT_HTTP_HEX, code / 16, 1) +
				StringSubstr(AT_HTTP_HEX, code % 16, 1);
		}
	}

	return result;
}

/**
* Returns the n-th pipe separated field of a structured reply, 1 based.
*
* Written out rather than using StringSplit because the message field of an
* error routinely contains commas ("RMS: margin shortfall, order rejected").
* The server guarantees the reverse -- it replaces any pipe inside a message --
* so splitting on the pipe is always safe.
*/
string atPipeField(const string line, const int index) {
	string rest = line;
	string result = "";

	for(int i = 1; i <= index; i++) {
		int position = StringFind(rest, "|");

		if(i == index) {
			if(position >= 0) {
				result = StringSubstr(rest, 0, position);
			} else {
				result = rest;
			}

			break;
		}

		if(position >= 0) {
			rest = StringSubstr(rest, position + 1);
		} else {
			/* Asked for a field past the end of the line. */
			return "";
		}
	}

	/*
	* The last field is trimmed because it carries whatever line ending the
	* reader left on the reply, and that field is the broker's order id.
	*
	* An untrimmed id is still returned by placeOrder() and still looks right
	* when printed, but every getOrderStatus()/getOrderPrice() call made with it
	* silently returns blank, because no row matches an id with a newline stuck
	* to it. That is exactly what happened in the AmiBroker library, whose
	* reader hands back each line WITH its newline.
	*
	* WebRequest gives MetaTrader the raw body rather than lines, so this is a
	* guard rather than a fix for an observed fault -- but the cost of being
	* wrong about that is a whole class of silently blank reads.
	*/
	StringTrimLeft(result);
	StringTrimRight(result);

	return result;
}

/**
* Sends a POST and returns the whole response body.
*
* MetaTrader hands back the HTTP status code as well, which is more than the
* AmiBroker library gets, but the body is still what decides the outcome: the
* server states every result inside it so that all three client libraries read
* one contract rather than three.
*/
string atHttpPost(const string path, const string postBody, const int timeoutMs) {
	atHttpReached = false;
	atHttpStatusCode = -1;

	if(!atHttpCanSend()) {
		return "";
	}

	string url = AT_BASE_URL + path;
	string headers = "Content-Type: application/x-www-form-urlencoded\r\n";

	uchar data[];
	uchar result[];
	string resultHeaders = "";

	/* Same terminating-zero trap as in atUrlEncode(). */
	int length = StringToCharArray(postBody, data, 0, WHOLE_ARRAY, CP_UTF8) - 1;

	if(length < 0) {
		length = 0;
	}

	ArrayResize(data, length);

	ResetLastError();

	int code = WebRequest("POST", url, headers, timeoutMs, data, result, resultHeaders);

	atHttpStatusCode = code;

	if(code == -1) {
		int error = GetLastError();

		if(error == AT_ERR_WEBREQUEST_BLOCKED) {
			/*
			* Not a network problem, and saying "could not connect" would send
			* the user to check a connection that is perfectly fine.
			*/
			atHttpMessage = "MetaTrader blocked the request. Add " + AT_BASE_URL +
				" in Tools -> Options -> Expert Advisors -> Allow WebRequest for listed URL.";
			atHttpTrace("WebRequest blocked (error 4014) for " + url);
		} else {
			atHttpTrace("WebRequest failed with error " + IntegerToString(error) + " for " + url);
		}

		return "";
	}

	atHttpReached = true;

	return CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
}

/**
* Decides what kind of reply this is, by positive identification.
*
* Order matters, and so does what counts as empty. A blank body is a dataset
* with no rows -- an account with no orders has always produced an empty file,
* and the server writes no header when there is nothing to write. It is NOT a
* valid answer to a command: every command is answered SD-OK or SD-ERROR, so a
* blank reply to one means the answer was lost on the way back, and the order
* may well have been placed.
*
* That is why isCommand decides the tail of this. For a read, anything
* unrecognised is a transport problem worth retrying. For a command it is the
* one case that must never be retried automatically.
*/
string atClassify(const string response, const bool isCommand) {
	if(!atHttpReached) {
		if(atHttpStatusCode == -1 && StringLen(atHttpMessage) > 0 &&
			StringFind(atHttpMessage, "Allow WebRequest") >= 0) {
			return AT_HTTP_BLOCKED;
		}

		return AT_HTTP_UNREACHABLE;
	}

	if(StringFind(response, AT_SD_ERROR) == 0) {
		return AT_HTTP_ERROR;
	}

	if(StringFind(response, AT_SD_OK) == 0) {
		return AT_HTTP_OK;
	}

	if(StringFind(response, "{") == 0) {
		/*
		* Authentication failed before any of our code ran. The key is wrong or
		* missing, and sending the same key again cannot help.
		*/
		return AT_HTTP_AUTH;
	}

	if(isCommand) {
		/* Nothing else is a valid reply to a command, blank included. */
		return AT_HTTP_UNREACHABLE;
	}

	if(StringLen(response) == 0) {
		return AT_HTTP_EMPTY;
	}

	if(StringFind(response, AT_CSV_HEADER) == 0) {
		return AT_HTTP_CSV;
	}

	return AT_HTTP_UNREACHABLE;
}

/**
* Pulls the action and message out of an SD-ERROR line and remembers them.
*/
void atRecordError(const string response) {
	atHttpAction = atPipeField(response, 3);
	atHttpMessage = atPipeField(response, 4);

	if(StringLen(atHttpMessage) == 0) {
		atHttpMessage = response;
	}
}

/**
* Turns a classification into the message a user should see, and remembers the
* action so a caller can tell "try later" from "fix something".
*
* The one judgement here is what an unreachable server means, and it is not the
* same for the two kinds of request. A read that did not arrive can simply be
* asked for again. A command that did not arrive may in fact have arrived, with
* only the answer lost -- so it is CHECK, and the caller must not resend it.
*/
void atRecordStatus(const string status, const string response, const bool isCommand) {
	if(status == AT_HTTP_ERROR) {
		atRecordError(response);
		return;
	}

	if(status == AT_HTTP_AUTH) {
		atHttpAction = AT_ACTION_USER;
		atHttpMessage = "API key was not accepted. Check AT_API_KEY in autotrader-http-config.mqh.";
		return;
	}

	if(status == AT_HTTP_BLOCKED) {
		/*
		* atHttpPost() already wrote the message, and it names the exact setting
		* to change. Nothing here should overwrite it with something vaguer.
		*/
		atHttpAction = AT_ACTION_USER;
		return;
	}

	if(status == AT_HTTP_UNREACHABLE) {
		if(isCommand) {
			atHttpAction = AT_ACTION_CHECK;
			atHttpMessage = "No usable reply from " + AT_BASE_URL +
				". The request may still have gone through -- check your order book.";
		} else {
			atHttpAction = AT_ACTION_RETRY;
			atHttpMessage = "Could not reach " + AT_BASE_URL + ". Check the internet connection.";
		}

		return;
	}

	atHttpAction = "";
	atHttpMessage = "";
}

/******************************** CSV READING ********************************/

/**
* Returns one field of a CSV line, 1 based, honouring quoted fields.
*
* Quotes are not decoration here. The server quotes any field that contains a
* comma, and two fields routinely do: an order's status message ("RMS: margin
* shortfall, order rejected") and its comments. Splitting on every comma would
* shift every column after such a field, so getOrderAveragePrice() would
* quietly return a piece of the broker's error text.
*
* Doubled quotes inside a quoted field are one literal quote, as in every other
* CSV reader.
*/
string atCsvField(const string line, const int column) {
	int total = StringLen(line);
	int field = 1;
	bool quoted = false;
	string value = "";

	for(int i = 0; i < total; i++) {
		ushort c = StringGetCharacter(line, i);

		if(quoted) {
			if(c == '"') {
				if(i + 1 < total && StringGetCharacter(line, i + 1) == '"') {
					value = value + "\"";
					i++;
				} else {
					quoted = false;
				}
			} else {
				value = value + ShortToString(c);
			}

			continue;
		}

		if(c == '"' && StringLen(value) == 0) {
			quoted = true;
			continue;
		}

		if(c == ',') {
			if(field == column) {
				return value;
			}

			field++;
			value = "";
			continue;
		}

		value = value + ShortToString(c);
	}

	if(field == column) {
		return value;
	}

	return "";
}

/**
* Returns the n-th line of a body, 1 based, or blank when there is no such line.
*/
string atBodyLine(const string body, const int index) {
	int start = 0;
	int total = StringLen(body);

	for(int i = 1; i <= index; i++) {
		if(start >= total) {
			return "";
		}

		int position = StringFind(body, "\n", start);
		string line;

		if(position >= 0) {
			line = StringSubstr(body, start, position - start);
			start = position + 1;
		} else {
			line = StringSubstr(body, start);
			start = total;
		}

		if(i == index) {
			return line;
		}
	}

	return "";
}

/**
* Counts the lines of a body.
*/
int atBodyLineCount(const string body) {
	if(StringLen(body) == 0) {
		return 0;
	}

	int count = 1;
	int position = StringFind(body, "\n", 0);

	while(position >= 0 && count < AT_HTTP_MAX_ROWS) {
		count++;
		position = StringFind(body, "\n", position + 1);
	}

	return count;
}

/******************************** THE CACHE **********************************/

/*
* Portfolio data is held per running program, one entry per account and
* dataset.
*
* A strategy calling twenty get...() functions on a tick would otherwise make
* twenty requests for the same four datasets; and the server allows about one
* portfolio request per second per account, so a chart doing that would spend
* its whole allowance re-asking for data it already had.
*
* Unlike the AmiBroker library this cache is NOT shared between charts.
* MetaTrader gives a program no way to share text with another program -- its
* global variables hold numbers only -- so two Expert Advisors on the same
* account keep two copies and make two requests. That is why the default TTLs
* matter more here: leave them alone unless you have a reason.
*/

string atCacheKeys[];

uint atCacheStamp[];

string atCacheStatus[];

string atCacheBody[];

int atCacheRows[];

/*
* The CSV header row, KEPT rather than discarded.
*
* It names every column, which is what lets a lookup ask for "QUANTITY"
* instead of counting to seven. Throwing it away is what let the holdings
* getters match the broker symbol column while the caller passed an
* independent symbol -- a silent wrong answer that no amount of reading the
* code would show.
*/
string atCacheHeader[];

/* True once a slot has been filled, so an unfetched slot is never trusted. */
bool atCacheFilled[];

/*
* Resolved column positions, as "slot|NAME" -> position.
*
* A strategy may ask for twenty fields on every tick, and re-scanning the
* header each time would be twenty scans for an answer that never changes
* within a session.
*/
string atColumnKeys[];

int atColumnPos[];

/**
* Finds the slot for one account and dataset, creating it the first time.
*/
int atCacheSlot(const string pseudoAccount, const string dataset) {
	string key = dataset + "|" + pseudoAccount;
	int total = ArraySize(atCacheKeys);

	for(int i = 0; i < total; i++) {
		if(atCacheKeys[i] == key) {
			return i;
		}
	}

	ArrayResize(atCacheKeys, total + 1);
	ArrayResize(atCacheStamp, total + 1);
	ArrayResize(atCacheStatus, total + 1);
	ArrayResize(atCacheBody, total + 1);
	ArrayResize(atCacheRows, total + 1);
	ArrayResize(atCacheHeader, total + 1);
	ArrayResize(atCacheFilled, total + 1);

	atCacheKeys[total] = key;
	atCacheStamp[total] = 0;
	atCacheStatus[total] = "";
	atCacheBody[total] = "";
	atCacheRows[total] = 0;
	atCacheHeader[total] = "";
	atCacheFilled[total] = false;

	return total;
}

int atTtlFor(const string dataset) {
	if(dataset == AT_DS_ORDERS) {
		return AT_TTL_ORDERS;
	}

	if(dataset == AT_DS_POSITIONS) {
		return AT_TTL_POSITIONS;
	}

	if(dataset == AT_DS_MARGINS) {
		return AT_TTL_MARGINS;
	}

	return AT_TTL_HOLDINGS;
}

/**
* Separates the header row from the records, returning how many records were
* kept.
*
* Row 1 of the stored body is the first real record, so the column numbers used
* by the get...() functions match the file based library exactly. The header
* itself is no longer thrown away: it is kept on the slot, which is what lets
* atColumnOf() resolve a column NAME.
*/
int atStoreRows(const int slot, const string body) {
	string rest = body;

	/* Carriage returns removed once, so no row can end with a stray one. */
	StringReplace(rest, "\r", "");

	int position = StringFind(rest, "\n");

	if(position < 0) {
		/*
		* Header only, or a single line with nothing after it: no data rows,
		* but the header is still worth keeping so a name can be resolved
		* against an empty dataset without a re-fetch.
		*/
		atCacheHeader[slot] = rest;
		atCacheBody[slot] = "";
		atCacheRows[slot] = 0;
		return 0;
	}

	atCacheHeader[slot] = StringSubstr(rest, 0, position);

	string rows = StringSubstr(rest, position + 1);

	/* A trailing newline would otherwise count as an extra, empty row. */
	while(StringLen(rows) > 0 && StringGetCharacter(rows, StringLen(rows) - 1) == '\n') {
		rows = StringSubstr(rows, 0, StringLen(rows) - 1);
	}

	atCacheBody[slot] = rows;
	atCacheRows[slot] = atBodyLineCount(rows);

	return atCacheRows[slot];
}

/**
* Asks the server for one dataset and replaces what is cached for it.
*
* On any failure the previous rows are LEFT ALONE and only the status changes.
* A strategy mid-position should not suddenly see an empty order book because
* one request timed out; the caller decides what to do about the status.
*/
string atFetchDataset(const string pseudoAccount, const string dataset) {
	int slot = atCacheSlot(pseudoAccount, dataset);

	string postBody = "api-key=" + atUrlEncode(AT_API_KEY) +
		"&pseudoAccount=" + atUrlEncode(pseudoAccount);

	atHttpTrace("reading " + dataset + " for " + pseudoAccount);

	string response = atHttpPost("/csv/" + dataset, postBody, AT_HTTP_TIMEOUT_READ);
	string status = atClassify(response, false);
	atRecordStatus(status, response, false);

	if(status == AT_HTTP_CSV) {
		int rows = atStoreRows(slot, response);
		atCacheFilled[slot] = true;

		atHttpTrace(dataset + ": " + IntegerToString(rows) + " rows");

	} else if(status == AT_HTTP_EMPTY) {
		/* A real answer: this account has nothing in this dataset right now. */
		atCacheBody[slot] = "";
		atCacheRows[slot] = 0;
		atCacheFilled[slot] = true;

		atHttpTrace(dataset + ": empty");

	} else {
		Print("AutoTrader: SD-ERR-MT-READ: ", dataset, " for ", pseudoAccount,
			" failed [", status, "] ", atHttpMessage);
	}

	atCacheStatus[slot] = status;

	return status;
}

/**
* Makes sure the cached copy of a dataset is recent enough to use.
*
* The timestamp is written whatever the outcome, including failures. Without
* that, a chart that cannot reach the server would retry on every single
* get...() call -- hundreds of hanging requests per tick, at the moment the
* network is already in trouble.
*
* GetTickCount() rather than the clock: it cannot jump backwards when the
* machine syncs its time, and unsigned subtraction stays correct across the
* wrap it does roughly every 49 days.
*/
string atEnsureFresh(const string pseudoAccount, const string dataset) {
	int slot = atCacheSlot(pseudoAccount, dataset);

	uint now = GetTickCount();
	uint ttlMs = (uint) atTtlFor(dataset) * 1000;

	if(atCacheStamp[slot] > 0 && (uint)(now - atCacheStamp[slot]) < ttlMs) {
		return atCacheStatus[slot];
	}

	string status = atFetchDataset(pseudoAccount, dataset);

	/*
	* Stamped on failure too. A chart that cannot reach the server must not
	* retry on every get...() call -- that is hundreds of hanging requests a
	* tick, produced exactly when the network is already struggling.
	*/
	atCacheStamp[slot] = GetTickCount();

	/* 0 means "never fetched", so a wrap landing exactly on it must not lie. */
	if(atCacheStamp[slot] == 0) {
		atCacheStamp[slot] = 1;
	}

	return status;
}

/**
* Reads one column of the row whose key column equals the given value.
*
* Same contract as the file based library's fileReadCsvColumnByRowId: columns
* are numbered from 1, and a row that is not there gives a blank rather than an
* error, so a strategy asking about an order that has not appeared yet behaves
* the same as it always has.
*/
string atReadColumn(const string pseudoAccount, const string dataset,
	const string keyValue, const int keyColumn, const int column) {

	atEnsureFresh(pseudoAccount, dataset);

	int slot = atCacheSlot(pseudoAccount, dataset);
	int total = atCacheRows[slot];

	for(int i = 1; i <= total; i++) {
		string line = atBodyLine(atCacheBody[slot], i);

		if(keyValue == atCsvField(line, keyColumn)) {
			return atCsvField(line, column);
		}
	}

	return "";
}

/**
* The same, for rows identified by four columns at once.
*
* A position has no id of its own; it is identified by category, type, exchange
* and symbol together, which is how at-desktop has always addressed one.
*/
string atReadColumn4(const string pseudoAccount, const string dataset,
	const string value1, const int column1, const string value2, const int column2,
	const string value3, const int column3, const string value4, const int column4,
	const int column) {

	atEnsureFresh(pseudoAccount, dataset);

	int slot = atCacheSlot(pseudoAccount, dataset);
	int total = atCacheRows[slot];

	for(int i = 1; i <= total; i++) {
		string line = atBodyLine(atCacheBody[slot], i);

		if(value1 == atCsvField(line, column1) &&
			value2 == atCsvField(line, column2) &&
			value3 == atCsvField(line, column3) &&
			value4 == atCsvField(line, column4)) {

			return atCsvField(line, column);
		}
	}

	return "";
}

/**
* Number of rows currently held for a dataset. Refreshes first.
*/
int atRowCount(const string pseudoAccount, const string dataset) {
	atEnsureFresh(pseudoAccount, dataset);

	return atCacheRows[atCacheSlot(pseudoAccount, dataset)];
}

/**
* Reads a column from a row by its position, 1 for the first record.
*/
string atReadRowColumn(const string pseudoAccount, const string dataset,
	const int row, const int column) {

	atEnsureFresh(pseudoAccount, dataset);

	int slot = atCacheSlot(pseudoAccount, dataset);

	if(row < 1 || row > atCacheRows[slot]) {
		return "";
	}

	return atCsvField(atBodyLine(atCacheBody[slot], row), column);
}

/***************************** LOOKUP BY NAME ********************************/

/**
* A column name reduced to its comparable form: upper case, no padding.
*
* StringToUpper and the trims all work in place and return a flag rather than
* the string, so the copy is deliberate, not an oversight.
*/
string atNormaliseName(const string text) {
	string result = text;

	StringTrimLeft(result);
	StringTrimRight(result);
	StringToUpper(result);

	return result;
}

/**
* Position of a named column in a dataset, 1 based. 0 when there is no such
* column.
*
* This is the whole point of keeping the header. Every lookup that identifies a
* row goes through a NAME, so a change to the server's column order cannot
* quietly make a getter return the wrong field -- the worst it can do is return
* 0 here, which is visible.
*
* The answer is cached per slot, because a strategy may ask for twenty fields
* on every tick and re-scanning the header each time would be twenty scans for
* an answer that never changes within a session.
*
* Names are compared without regard to case, so "quantity" and "QUANTITY" are
* the same column.
*/
int atColumnOf(const string pseudoAccount, const string dataset,
	const string fieldName) {

	atEnsureFresh(pseudoAccount, dataset);

	int slot = atCacheSlot(pseudoAccount, dataset);
	string wanted = atNormaliseName(fieldName);
	string key = IntegerToString(slot) + "|" + wanted;
	int total = ArraySize(atColumnKeys);

	for(int i = 0; i < total; i++) {
		if(atColumnKeys[i] == key) {
			/*
			* -1 records "looked and it is not there", so a missing column is
			* not re-scanned on every call.
			*/
			if(atColumnPos[i] < 0) {
				return 0;
			}

			return atColumnPos[i];
		}
	}

	int found = 0;

	for(int i = 1; i <= AT_HTTP_MAX_COLUMNS; i++) {
		string colName = atNormaliseName(atCsvField(atCacheHeader[slot], i));

		if(colName == "") {
			/* Past the end of the header. */
			break;
		}

		if(colName == wanted) {
			found = i;
			break;
		}
	}

	/*
	* A miss is only worth remembering when there WAS a header to miss in. An
	* account with no orders yet gets an empty reply, and an empty reply carries
	* no header at all -- the server has no rows to write one from. Remembering
	* "not there" at that moment would keep the column unresolvable for the rest
	* of the session, so the first order placed afterwards could never be read
	* back.
	*/
	if(found == 0 && atCacheHeader[slot] == "") {
		return 0;
	}

	ArrayResize(atColumnKeys, total + 1);
	ArrayResize(atColumnPos, total + 1);

	atColumnKeys[total] = key;

	if(found == 0) {
		atColumnPos[total] = -1;
	} else {
		atColumnPos[total] = found;
	}

	return found;
}

/**
* One field of one row, addressed by column NAME. Blank when the dataset has no
* such column or the row is out of range.
*/
string atFieldByName(const string pseudoAccount, const string dataset,
	const int row, const string fieldName) {

	int column = atColumnOf(pseudoAccount, dataset, fieldName);

	if(column < 1) {
		return "";
	}

	return atReadRowColumn(pseudoAccount, dataset, row, column);
}

/**
* The first row whose named column equals a value, as a row number. 0 when
* nothing matches.
*/
int atFindRowByName(const string pseudoAccount, const string dataset,
	const string fieldName, const string value) {

	int column = atColumnOf(pseudoAccount, dataset, fieldName);

	if(column < 1) {
		return 0;
	}

	int total = atRowCount(pseudoAccount, dataset);
	int slot = atCacheSlot(pseudoAccount, dataset);

	for(int i = 1; i <= total; i++) {
		if(value == atCsvField(atBodyLine(atCacheBody[slot], i), column)) {
			return i;
		}
	}

	return 0;
}

/**
* The first row matching TWO named columns at once. 0 when nothing matches.
*/
int atFindRowByName2(const string pseudoAccount, const string dataset,
	const string field1, const string value1,
	const string field2, const string value2) {

	int col1 = atColumnOf(pseudoAccount, dataset, field1);
	int col2 = atColumnOf(pseudoAccount, dataset, field2);

	if(col1 < 1 || col2 < 1) {
		return 0;
	}

	int total = atRowCount(pseudoAccount, dataset);
	int slot = atCacheSlot(pseudoAccount, dataset);

	for(int i = 1; i <= total; i++) {
		string line = atBodyLine(atCacheBody[slot], i);

		if(value1 == atCsvField(line, col1) &&
			value2 == atCsvField(line, col2)) {

			return i;
		}
	}

	return 0;
}

/**
* The first row matching FOUR named columns at once.
*
* A position has no id of its own -- it is identified by category, type,
* exchange and symbol together.
*/
int atFindRowByName4(const string pseudoAccount, const string dataset,
	const string field1, const string value1,
	const string field2, const string value2,
	const string field3, const string value3,
	const string field4, const string value4) {

	int col1 = atColumnOf(pseudoAccount, dataset, field1);
	int col2 = atColumnOf(pseudoAccount, dataset, field2);
	int col3 = atColumnOf(pseudoAccount, dataset, field3);
	int col4 = atColumnOf(pseudoAccount, dataset, field4);

	if(col1 < 1 || col2 < 1 || col3 < 1 || col4 < 1) {
		return 0;
	}

	int total = atRowCount(pseudoAccount, dataset);
	int slot = atCacheSlot(pseudoAccount, dataset);

	for(int i = 1; i <= total; i++) {
		string line = atBodyLine(atCacheBody[slot], i);

		if(value1 == atCsvField(line, col1) &&
			value2 == atCsvField(line, col2) &&
			value3 == atCsvField(line, col3) &&
			value4 == atCsvField(line, col4)) {

			return i;
		}
	}

	return 0;
}

/******************************** COMMANDS ***********************************/

/**
* Sends one command and returns how it went, as one of the AT_HTTP_ values.
*
* The reply itself is left in atHttpResponse for a caller that needs the order
* id out of it.
*/
string atSendCommand(const string csv) {
	string postBody = "api-key=" + atUrlEncode(AT_API_KEY) +
		"&command=" + atUrlEncode(csv);

	atHttpTrace("command: " + csv);

	atHttpResponse = atHttpPost("/csv/command", postBody, AT_HTTP_TIMEOUT_COMMAND);

	string status = atClassify(atHttpResponse, true);
	atRecordStatus(status, atHttpResponse, true);

	atHttpTrace("reply: " + atHttpResponse);

	return status;
}

/**
* Runs a command that has nothing to return but success or failure -- modify,
* cancel, square off. Returns true only if the server confirmed it.
*
* Anything else is false AND logged with the reason, because the caller is a
* strategy that cannot ask a question: if a square-off did not happen, the only
* way anyone finds out is the log.
*/
bool atRunCommand(const string csv, const string description) {
	string status = atSendCommand(csv);

	if(status == AT_HTTP_OK) {
		if(AT_HTTP_DEBUG) {
			Print("AutoTrader: ", description, " done.");
		}

		return true;
	}

	Print("AutoTrader: SD-ERR-MT-CMD: ", description, " failed [", status, "] ", atHttpMessage);

	if(atHttpAction == AT_ACTION_CHECK) {
		/*
		* The request reached the broker and was never confirmed. Reporting
		* false is right -- we did not see it succeed -- but a bare false would
		* let a strategy quietly assume nothing happened, and something may
		* well have.
		*/
		Print("AutoTrader: SD-ERR-MT-CMD: ", description,
			" may still have gone through. Check your order book before repeating it.");
	}

	return false;
}

#endif
