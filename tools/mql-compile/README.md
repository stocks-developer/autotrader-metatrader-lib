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
and read the Experts tab. It prints one line per check and a `PASS` or `FAIL`
summary at the end.

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
