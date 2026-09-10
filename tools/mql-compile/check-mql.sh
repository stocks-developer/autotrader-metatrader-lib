#!/bin/bash
#
# Compiles every MQL file in this repository and fails if any of them has an
# error.
#
# MQL is compiled, not interpreted, so a mistake that a reading would not catch
# -- a name defined twice, a body left unclosed, an argument of the wrong type
# -- stops the library building and nothing in it can run. Reading the source
# cannot tell you it builds; only the compiler can.
#
# Needs MetaEditor, which comes with MetaTrader 5. That is a free download and
# needs no account:
#
#     https://www.metatrader5.com/en/download
#
# Usage, from the repository root:
#
#     tools/mql-compile/check-mql.sh
#
# Set METAEDITOR to point somewhere else if yours is not in the usual place.
#
set -u

REPO=$(cd "$(dirname "$0")/../.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

METAEDITOR=${METAEDITOR:-"$HOME/AppData/Roaming/MetaTrader 5/MetaEditor64.exe"}

if [ ! -f "$METAEDITOR" ]; then
	echo "MetaEditor not found at:"
	echo "  $METAEDITOR"
	echo
	echo "Install MetaTrader 5 (free, no account needed) from"
	echo "https://www.metatrader5.com/en/download, or set METAEDITOR to its path."
	exit 2
fi

# MetaEditor resolves <angle bracket> includes against the Include directory of
# the root it is given. That root does NOT have to be MetaTrader's own data
# folder -- any directory laid out the same way will do, which is what keeps
# this from needing a terminal or a logged in account.
mkdir -p "$WORK/Include" "$WORK/Experts/AutoTraderWeb"
cp "$REPO"/Include/*.mqh "$WORK/Include/"
cp "$REPO"/Experts/AutoTraderWeb/*.mq5 "$WORK/Experts/AutoTraderWeb/"

if [ -d "$REPO/tools/mql-compile/tests" ]; then
	cp "$REPO"/tools/mql-compile/tests/*.mq5 "$WORK/Experts/AutoTraderWeb/" 2>/dev/null
fi

ROOT_WIN=$(cygpath -w "$WORK" 2>/dev/null || echo "$WORK")

failed=0
checked=0

for source in "$WORK"/Experts/AutoTraderWeb/*.mq5; do
	name=$(basename "$source")
	log="$WORK/$name.log"

	SRC_WIN=$(cygpath -w "$source" 2>/dev/null || echo "$source")
	LOG_WIN=$(cygpath -w "$log" 2>/dev/null || echo "$log")

	# MetaEditor always exits 0, whatever happened. The log is the only verdict.
	"$METAEDITOR" /compile:"$SRC_WIN" /inc:"$ROOT_WIN" /log:"$LOG_WIN" >/dev/null 2>&1
	sleep 1

	checked=$((checked + 1))

	if [ ! -f "$log" ]; then
		echo "$name: NO LOG -- the compile did not run"
		failed=$((failed + 1))
		continue
	fi

	# The log is UTF-16, so it has to be decoded before anything can read it.
	result=$(python -c "
import sys, re
raw = open(sys.argv[1], 'rb').read().decode('utf-16-le', errors='replace')
errors = [l.strip() for l in raw.splitlines() if ': error' in l]
for line in errors:
    print('    ' + re.sub(r'^.*[\\\\/]([A-Za-z0-9._-]+\.mq[h5])', r'\1', line))
print('ERRORS=%d' % len(errors))
" "$log")

	count=$(echo "$result" | sed -n 's/^ERRORS=//p')
	detail=$(echo "$result" | grep -v '^ERRORS=')

	if [ "$count" = "0" ]; then
		echo "$name: ok"
	else
		echo "$name: $count error(s)"
		echo "$detail"
		failed=$((failed + 1))
	fi
done

echo
echo "compiled $checked file(s), $failed with errors"

if [ "$failed" -ne 0 ]; then
	exit 1
fi

exit 0
