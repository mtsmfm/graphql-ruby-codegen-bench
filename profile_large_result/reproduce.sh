#!/bin/sh
# Reproduce the profile_large_result comparison from scratch:
#   1. cut graphql-ruby's benchmark/run.rb into data.rb and schema.rb (no line edited)
#   2. generate the depth-first and breadth-first executors from the schema
#   3. compile them with Spinel
#   4. check every executor's output against graphql-ruby, with lazy and eager data
#   5. time graphql-ruby (legacy, next) and the executors (interpreter, YJIT, Spinel)
#   6. print the minimum of the rounds
#
# Settings (environment):
#   GRAPHQL_RUBY  graphql-ruby checkout            (required)
#   SPINEL        the spinel command               (required)
#   SPINEL_CC     C compiler Spinel calls          (default gcc)
#   ROUNDS        timing rounds, one process each  (default 5)
set -e
cd "$(dirname "$0")"
: "${GRAPHQL_RUBY:?set GRAPHQL_RUBY to a graphql-ruby checkout}"
: "${SPINEL:?set SPINEL to the spinel command}"
export GRAPHQL_RUBY=$(cd "$GRAPHQL_RUBY" && pwd)
SPINEL_CC=${SPINEL_CC:-gcc}
GQL=$GRAPHQL_RUBY/lib

echo "== environment"
ruby -v
ruby --yjit -e 'puts "YJIT enabled: #{RubyVM::YJIT.enabled?}"'
echo "graphql-ruby $(git -C "$GRAPHQL_RUBY" rev-parse --short HEAD)"
sdir=$(dirname "$(readlink -f "$SPINEL")")
echo "spinel $(git -C "$sdir" rev-parse --short HEAD 2>/dev/null || echo '?'), $(git -C "$sdir" status --short --untracked-files=no 2>/dev/null | wc -l) locally modified files"
echo "C compiler for Spinel: $($SPINEL_CC --version | head -1)"

echo "== extract and generate"
ruby extract.rb "$GRAPHQL_RUBY/benchmark/run.rb"
ruby -I "$GQL" ../tools/gen_executor.rb schema.rb ProfileLargeResult::Schema data.rb large_exec.rb
GQL_MODE=batch ruby -I "$GQL" ../tools/gen_executor.rb schema.rb ProfileLargeResult::Schema data.rb batch/exec_batch.rb

echo "== compile with Spinel (--cc=$SPINEL_CC)"
for pair in "run.rb run_spinel" "bench.rb bench_spinel" "batch/run_batch.rb batch/run_batch.spinel" "batch/bench_batch.rb batch/bench_batch.spinel"; do
  set -- $pair
  start=$(date +%s)
  "$SPINEL" --cc="$SPINEL_CC" "$1" -o "$2" > "$2.log" 2>&1 || { echo "spinel failed on $1 (see $2.log)"; exit 1; }
  echo "$2: $(( $(date +%s) - start ))s"
done

echo "== check outputs against graphql-ruby"
for eager in "" 1; do
  # benchmark/run.rb tests ENV["EAGER"] for truthiness: lazy means unset, not empty
  if [ -n "$eager" ]; then export EAGER=1; label=eager; else unset EAGER; label=lazy; fi
  for pair in "ruby run.rb" "./run_spinel" "ruby batch/run_batch.rb" "./batch/run_batch.spinel"; do
    echo "[$label] $pair"
    $pair | ruby -I "$GQL" check.rb
  done
done
unset EAGER

echo "== timing (ROUNDS=${ROUNDS:-5}) -> compare.out"
./compare.sh > compare.out
ruby summarize.rb compare.out
