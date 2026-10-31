# Compile check

Compiles every MQL file in this repository and fails if any of them has an
error.

This is a maintainer's tool. It is not part of the library and is not included
in the download, so nothing here needs to be installed to use AutoTrader Web.

```
tools/mql-compile/check-mql.sh
```

```
at-selftest-direct.mq5: ok
demo-direct.mq5: ok
demo.mq5: ok

compiled 3 file(s), 0 with errors
```

Exit code is 0 when everything compiles and 1 when anything does not, so it
works as a pre-push check.

## What it needs

MetaEditor, which comes with MetaTrader 5. That is a free download and needs no
account or broker login:

<https://www.metatrader5.com/en/download>

The script looks for it at
`~/AppData/Roaming/MetaTrader 5/MetaEditor64.exe`. Set `METAEDITOR` to override
that.

## Why a compiler and not a reading

MQL is compiled. A name defined twice, a body left unclosed, or an argument of
the wrong type stops the whole library building, and then none of it runs — the
fault is not in one function, it is in all of them. No amount of reading the
source establishes that it builds. The compiler is the only thing that can say
so, and it takes under a second.

## Two things about MetaEditor worth knowing

**It always exits 0**, whatever happened, so the exit code tells you nothing.
The log file is the only verdict. This script reads the log and derives its own
exit code from it.

**The log is UTF-16**, so `grep` finds nothing in it without a decode first.
That is why the script pipes it through Python rather than matching it directly.

## The include root

`/inc:` points MetaEditor at a directory laid out like MetaTrader's data folder
— an `Include` directory and an `Experts` directory. It does not have to *be*
MetaTrader's data folder. The script builds a temporary one from the repository
and compiles against that, which is why it needs no terminal running and no
account logged in.

## tests/

`tests/at-selftest-direct.mq5` checks the library's behaviour rather than just
its syntax. It puts a portfolio straight into the library's cache instead of
asking the server for one, then checks that every lookup returns the field it
asked for, using the server's real column order. It makes no network request,
needs no API key, and places no orders.

`check-mql.sh` compiles it along with everything else. To run it, copy it into
`MQL5/Experts` in MetaTrader's data folder, attach it to any chart as a Script,
and read the Experts tab.

To run it without clicking, compile it in the data folder
(`MetaEditor64.exe /compile:<file> /log:<log>`), then start the terminal with
`terminal64.exe /config:<ini>`, where the ini holds `[StartUp]`,
`Script=AutoTraderWeb\at-selftest-direct`, `Symbol=EURUSD`, `Period=H1` and
`ShutdownTerminal=1`. The terminal runs the script and closes; the result is in
`MQL5/Logs/<date>.log` (UTF-16). Write the ini with an editor, not `printf`:
the shell turns `\a` into a control character. Copy only the changed library
files into the data folder: its `autotrader-http-config.mqh` holds a real key. It prints one line per check and a `PASS` or `FAIL`
summary at the end.

**Never start an order-placing Expert Advisor this way (`[StartUp] Expert=`).**
MetaTrader saves an EA started from the ini into the chart profile, so it runs
again on every later launch, including the relaunch after an automatic update.
A place-check EA did exactly this on 2026-10-31 and placed two real orders
(both rejected). Use `Script=` for anything unattended; before any launch, read
the journal for `expert ... loaded` lines; and remove an EA from the chart when
you are done with it.

`tests/at-livecheck-direct.mq5` is the other half. The self test never touches
the network; this one makes a single real request — it reads margins for one
account and prints what came back — so between them they separate "the library
handles data correctly" from "the library can reach the server at all".

**It places nothing.** There is no `placeOrder`, `modifyOrder`, `cancelOrder` or
square off anywhere in it, and margins is the lightest read there is: one
dataset, one request.

Unlike the self test it needs real credentials, so it cannot run unattended:

- an API key in `Include/autotrader-http-config.mqh`,
- `https://apix.stocksdeveloper.in` in **Tools → Options → Expert Advisors →
  Allow WebRequest for listed URL**, without which every request fails with
  error 4014,
- an account logged in at the broker, otherwise the read still reaches the
  server but every figure is zero.

Copy it into `MQL5/Experts`, set **Pseudo account** in the inputs, and attach it
to any chart **as an Expert Advisor** — not as an indicator and not in the
Strategy Tester, because MetaTrader refuses web requests from both.

Equity, commodity and all carrying the same figure is normal: many brokers pool
their segments, and the *all* category is a copy of that pooled figure rather
than a sum, since summing pooled segments would count the same money twice.

## MetaTrader behaviour to design around (found in dry runs, 2026-10-31)

- **A custom symbol fed by a program (`CustomTicksAdd`, as data-vendor plugins do)
  never calls an Expert Advisor's `OnTick`**: the bars grow, the EA hears nothing.
  A sample that acts on candles must also check on a timer (`at-ma-crossover`
  uses `EventSetTimer(1)`), or it does nothing on most Indian users' charts.
- **Chart objects are sized in screen pixels, fonts are not**: at 150% / 200%
  Windows scaling, button text overflows unless positions and sizes are scaled by
  `TERMINAL_SCREEN_DPI / 96` (`panelPx` in `at-trade-panel`).
- **A chart label shows at most 63 characters**; longer text is cut silently. Wrap it.
- **A new element of a string array is NULL, and NULL != ""**: set them to `""` after
  `ArrayResize`, or a "nothing here" test passes for empty slots.
- **MetaTrader compiles every `.mq5` without an `.ex5` when it starts**, so the
  download (sources only) needs no compile step from the user.
- **Never recompile an EA while MetaTrader is running it**: the terminal stopped taking
  input and ignored WM_CLOSE until killed. Close the terminal first. The terminal also
  sometimes ignores WM_CLOSE after running a while; `taskkill /F` works, but then it does
  not save the chart profile.
