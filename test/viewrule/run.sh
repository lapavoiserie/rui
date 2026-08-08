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

# check <fixture> <pass|reject> [field the refusal must name]
check() {
	local fixture="$1" expect="$2" field="${3:-}"
	local out code

	out=$(haxe -cp . -cp ../../../src \
		--macro 'rui.macros.ViewRule.register("viewrule.App", "body")' \
		-main "$fixture" -js /dev/null --no-output 2>&1)
	code=$?

	if [ "$expect" = "pass" ]; then
		if [ $code -eq 0 ]; then
			echo "  ok   $fixture compile"
		else
			failures=$((failures + 1))
			echo "  FAIL $fixture aurait du compiler"
			echo "$out" | sed 's/^/         /'
		fi
		return
	fi

	if [ $code -eq 0 ]; then
		failures=$((failures + 1))
		echo "  FAIL $fixture aurait du etre refuse"
	elif ! echo "$out" | grep -q "\"$field\""; then
		# Refused, but possibly for an unrelated reason.
		failures=$((failures + 1))
		echo "  FAIL $fixture refuse, mais sans nommer \"$field\""
		echo "$out" | sed 's/^/         /'
	else
		echo "  ok   $fixture refuse en nommant \"$field\""
	fi
}

echo "ViewRule"

# Ce que la regle accepte.
check ObservableState    pass
check FinalField         pass
check ImmutableCollection pass
check LocalOnly          pass

# Une action n'est pas une vue : la closure rend Void et s'execute a
# l'evenement, donc rien a l'ecran n'en depend.
check ActionClosure      pass

# Ce qu'elle refuse.
check MutableRead        reject count

# Le garde-fou du point precedent : une closure qui *rend* une vue fait partie
# du rendu, donc elle reste jugee. Sans ce cas, ignorer toutes les closures
# passerait inapercu.
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
