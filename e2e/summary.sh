#!/bin/bash
# Turns the JSON report of Playwright into a Markdown summary of the run.
#
#   summary.sh <results.json> <scenario> <excluded-tests.txt>
#
# The CI writes the output to the summary of the job.

set -euo pipefail

RESULTS=$1
SCENARIO=$2
EXCLUDED=$3

echo "## E2E suite ($SCENARIO)"
echo

if [ ! -s "$RESULTS" ]; then
  echo "The suite did not run: there is no report."
  exit 0
fi

jq -r '
  def tests(path):
    (.specs[]? | {
      name: (path + [.title] | join(" › ")),
      status: (.tests | map(.status) | if index("unexpected") then "failed" elif index("flaky") then "flaky" else "other" end),
      error: ([.tests[].results[]?.error.message // empty] | last // ""
              | gsub("\u001b\\[[0-9;]*m"; "") | split("\n")[0])
    }),
    (.suites[]? | . as $suite | tests(path + [$suite.title]));

  def list(title; status; show_error):
    map(select(.status == status))
    | if length == 0 then empty else
        "", "### \(title)", "",
        (.[] | "- \(.name)" + (if show_error and .error != "" then "<br>`\(.error)`" else "" end))
      end;

  (.stats.duration / 1000 | floor) as $seconds
  | [.suites[] | . as $file | tests([$file.title])] as $tests
  | "| Passed | Failed | Flaky | Skipped | Duration |",
    "| ---: | ---: | ---: | ---: | ---: |",
    "| \(.stats.expected) | \(.stats.unexpected) | \(.stats.flaky) | \(.stats.skipped) | \($seconds / 60 | floor)m \($seconds % 60)s |",
    ($tests | list("Failed"; "failed"; true)),
    ($tests | list("Flaky: failed, then passed on retry"; "flaky"; false))
' "$RESULTS"

LEFT_OUT=$(grep -vE '^(#|$)' "$EXCLUDED" || true)
if [ -n "$LEFT_OUT" ]; then
  echo
  echo "### Left out by \`e2e/excluded-tests.txt\`"
  echo
  echo "$LEFT_OUT" | sed 's/^/- /'
fi

echo
echo "Traces and screenshots are in the artifact \`E2E report ($SCENARIO)\`."
