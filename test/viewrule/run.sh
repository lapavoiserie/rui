#!/usr/bin/env bash
#
# Checks `rui.macros.ViewRule` on small fixtures.
#
# A macro whose job is to *refuse to compile* cannot be tested by calling it:
# what has to be observed is the compiler's verdict. So each fixture is compiled
# on its own and judged on the **exit code** -- not on whether some string
# appears in the output. Counting lines that match "error" is exactly how three
# broken examples were once reported green: Haxe says "Unexpected )", and the
# filter scored zero.
#
# For a fixture that must be refused, the exit code is not enough either: any
# compile error would satisfy it, including one that has nothing to do with the
# rule. So the refusal must also *name the field*.
#
#   ./test/viewrule/run.sh

set -u
cd "$(dirname "$0")/fixtures"

failures=0

# check <fixture> <pass|reject> [field the refusal must name] [rawcells]
#
# The optional 4th argument registers with rawCells=true -- the portable-mui
# stance `mui.macros.Bind` takes -- where a raw Signal/State read is refused.
# The default registration is a backend author's, where it is the idiom.
check() {
	local fixture="$1" expect="$2" field="${3:-}" raw="${4:-}"
	local out code reg

	reg='rui.macros.ViewRule.register("viewrule.App", "body")'
	[ "$raw" = "rawcells" ] && reg='rui.macros.ViewRule.register("viewrule.App", "body", true)'

	out=$(haxe -cp . -cp ../../../src \
		--macro "$reg" \
		-main "$fixture" -js /dev/null --no-output 2>&1)
	code=$?

	if [ "$expect" = "pass" ]; then
		if [ $code -eq 0 ]; then
			echo "  ok   $fixture compile"
		else
			failures=$((failures + 1))
			echo "  FAIL $fixture should have compiled"
			echo "$out" | sed 's/^/         /'
		fi
		return
	fi

	if [ $code -eq 0 ]; then
		failures=$((failures + 1))
		echo "  FAIL $fixture should have been refused"
	elif ! echo "$out" | grep -q "\"$field\""; then
		# Refused, but possibly for an unrelated reason.
		failures=$((failures + 1))
		echo "  FAIL $fixture refused, but without naming \"$field\""
		echo "$out" | sed 's/^/         /'
	else
		echo "  ok   $fixture refused, naming \"$field\""
	fi
}

echo "ViewRule"

# What the rule accepts.
check ObservableState    pass
check FinalField         pass
check ImmutableCollection pass
check LocalOnly          pass

# An action is not a view: the closure returns Void and runs on an event, so
# nothing on screen depends on it.
check ActionClosure      pass

# What it refuses.
check MutableRead        reject count

# A raw reactive cell is refused even though it *is* observable: its writes
# notify subscribers, and on the backends that rebuild from their own dirty
# flag nothing subscribes the tree. Only under rawCells -- ObservableState
# above shows the same read *accepted* under a backend author's registration.
check RawSignalRead      reject ticks rawcells

# The guard on the point above: a closure that *returns* a view is part of
# rendering, so it stays judged. Without this case, skipping every closure would
# pass unnoticed.
check BuilderClosure     reject hidden

if [ $failures -eq 0 ]; then
	echo ""
	echo "all good"
	exit 0
else
	echo ""
	echo "$failures failed"
	exit 1
fi
