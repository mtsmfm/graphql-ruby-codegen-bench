#!/bin/sh
# Same schema, same data shape: graphql-ruby classic and Next, the generated
# breadth-first (Next-style) and depth-first executors, on the interpreter,
# YJIT and Spinel. ROUNDS interleaved rounds; raw lines go to compare.out.
cd "$(dirname "$0")"
GQL=${GRAPHQL_RUBY:?set GRAPHQL_RUBY to a graphql-ruby checkout}/lib
ROUNDS=${ROUNDS:-5}
r=1
while [ $r -le $ROUNDS ]; do
  for e in "" 1; do
    m=${e:+eager}; m=${m:-lazy}
    # benchmark/run.rb checks ENV["EAGER"] for truthiness, so an empty EAGER= is eager too:
    # unset it for the lazy rounds.
    if [ -n "$e" ]; then export EAGER=1; else unset EAGER; fi
    echo "R$r $m load $(uptime | sed 's/.*load average: //')"
    echo "R$r $m graphql-ruby interp $(ruby -I $GQL bench_graphql.rb | tr '\n\t' ' |')"
    echo "R$r $m graphql-ruby yjit $(ruby --yjit -I $GQL bench_graphql.rb | tr '\n\t' ' |')"
    echo "R$r $m gen-batch interp $(ruby batch/bench_batch.rb | tr '\n\t' ' |')"
    echo "R$r $m gen-batch yjit $(ruby --yjit batch/bench_batch.rb | tr '\n\t' ' |')"
    echo "R$r $m gen-batch spinel $(./batch/bench_batch.spinel | tr '\n\t' ' |')"
    echo "R$r $m gen-depth interp $(ruby bench.rb | tr '\n\t' ' |')"
    echo "R$r $m gen-depth yjit $(ruby --yjit bench.rb | tr '\n\t' ' |')"
    echo "R$r $m gen-depth spinel $(./bench_spinel | tr '\n\t' ' |')"
  done
  r=$((r + 1))
done
