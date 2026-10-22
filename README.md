# graphql-ruby's profile_large_result: graphql-ruby vs. Ruby generated from the schema

This repository runs graphql-ruby's own benchmark `profile_large_result`
(in graphql-ruby's `benchmark/run.rb`) three ways and compares them:

- graphql-ruby, with the legacy runtime (`Schema.execute`) and the new one (`Schema.execute_next`)
- plain Ruby generated from the same schema by `tools/gen_executor.rb`, in two shapes:
  depth-first and breadth-first
- the same generated Ruby compiled to a native binary by [Spinel](https://github.com/matz/spinel)

The generated code does not use graphql-ruby at run time. It parses and
validates the query with `runtime/gql_runtime.rb` (independent of the schema)
and executes it with one method per object type, in which the way each field is
read and the way each value is turned into JSON were decided from the schema
while generating. It implements only what this schema uses.

## Layout

```
tools/gen_executor.rb      generator (depth-first executor)
tools/batch_emitter.rb     generator, breadth-first part (GQL_MODE=batch)
runtime/gql_runtime.rb     schema-independent runtime: parser, validator, helpers
profile_large_result/
  reproduce.sh             runs everything below
  extract.rb               cuts the benchmark's schema and data out of benchmark/run.rb
  queries.rb               the benchmark's two queries, as text
  run.rb, batch/run_batch.rb        print data and results, for check.rb
  check.rb                 replays the data through graphql-ruby and compares
  bench.rb, batch/bench_batch.rb    time the generated executors
  bench_graphql.rb         times graphql-ruby (execute, execute_next)
  timing.rb                shared timing loop
  compare.sh, summarize.rb timing rounds and their minimum
```

## Requirements

- Ruby 4.0 with YJIT (tested with 4.0.7), and the gems graphql-ruby needs:
  `gem install base64 fiber-storage logger`. Prism is bundled with Ruby.
- A graphql-ruby checkout. graphql-ruby is loaded with `-I lib`, not as a gem.
  Tested at 61759ed0641d893b171b00dd10a225997f59b622 (2026-10-07).
- Spinel, built from https://github.com/matz/spinel as its README describes
  (GNU make). Tested at e95ce05feb4aa37b027328fca75503a9c0446dec (2026-10-14), unmodified.
- A C compiler for Spinel (tested with GCC 13.3).

## Reproduce

```sh
cd profile_large_result
GRAPHQL_RUBY=/path/to/graphql-ruby SPINEL=/path/to/spinel/spinel ./reproduce.sh
```

It does everything from scratch and stops at the first failure:

1. `extract.rb` cuts `ProfileLargeResult` out of graphql-ruby's
   `benchmark/run.rb` into `data.rb` (the data) and `schema.rb` (the types and
   the two queries). No line is edited; only one level of indentation is removed.
2. `tools/gen_executor.rb` generates `large_exec.rb` (depth-first) and, with
   `GQL_MODE=batch`, `batch/exec_batch.rb` (breadth-first).
3. Spinel compiles `run.rb`, `bench.rb`, `batch/run_batch.rb` and `batch/bench_batch.rb`.
4. Each executor, on CRuby and as a Spinel binary, prints its data and its
   results. `check.rb` rebuilds the same data, runs it through graphql-ruby
   (`execute` and `execute_next`) and requires byte-identical output. This is
   done with lazy and with eager data, 16 checks in all.
5. `compare.sh` times everything `ROUNDS` times, interleaved, into `compare.out`.
6. `summarize.rb` prints the minimum over the rounds.

| variable | meaning | default |
|---|---|---|
| `GRAPHQL_RUBY` | graphql-ruby checkout | required |
| `SPINEL` | the `spinel` command | required |
| `SPINEL_CC` | C compiler Spinel calls (`--cc=`) | `gcc` |
| `ROUNDS` | timing rounds (one process each) | `5` |

The generated files contain absolute `require_relative` paths, so
`reproduce.sh` regenerates them on every run.

### Lazy and eager data

`benchmark/run.rb` wraps most values in procs unless `EAGER` is set,

```ruby
def self.eager_or_proc(value)
  ENV["EAGER"] ? value : -> { value }
end
```

and the schema declares `lazy_resolve Proc, :call`, so graphql-ruby calls a
proc wherever it finds one. This stands in for an application's batch loading.
Lazy is the benchmark's default. The test is for truthiness, so an empty
`EAGER=` also means eager: the lazy rounds unset `EAGER` instead.

### How a number is measured

One measurement is one process (`timing.rb`): after 3 warm-up calls it runs the
query repeatedly for about 1 second, 5 times, and takes the median time per
call. As in `profile_large_result`, the query is parsed once; validation and
execution are timed. `compare.sh` repeats this `ROUNDS` times, interleaving all
variants, and `summarize.rb` reports the minimum.

## Results

Times in ms per execution of the benchmark's first query (1,000 objects of 10
fields, three of them lists of 10, about 37,000 values). Spinel built the
binaries with `--cc=gcc` at its default `-O2`.

Lazy data (the benchmark's default):

| | interpreter | YJIT | Spinel |
|---|---:|---:|---:|
| graphql-ruby legacy (`execute`) | 213.99 | 74.79 | – |
| graphql-ruby next (`execute_next`) | 31.51 | 14.23 | – |
| generated, depth-first | 11.67 | 4.53 | 3.92 |
| generated, breadth-first | 8.96 | 3.68 | 4.22 |

Eager data (`EAGER=1`):

| | interpreter | YJIT | Spinel |
|---|---:|---:|---:|
| graphql-ruby legacy (`execute`) | 148.15 | 30.33 | – |
| graphql-ruby next (`execute_next`) | 18.47 | 9.43 | – |
| generated, depth-first | 9.27 | 3.45 | 3.32 |
| generated, breadth-first | 7.25 | 2.75 | 3.72 |

From one run of `reproduce.sh` on 2026-10-22 (load average 1.0–1.4). Between
runs on the same machine the numbers moved by a few percent.

Beyond implementing only this schema's features, the generated code skips two
checks graphql-ruby makes when turning values into JSON: that an Int fits in 32
bits, and that a String is UTF-8. Putting them back cost 5–11% in a separate
experiment.

## Environment

| | |
|---|---|
| CPU | AMD Ryzen 5 3600 (6 cores, 12 threads) |
| Memory | 20 GB |
| OS | Ubuntu 24.04.5 LTS container, run by wslc on Windows (Linux kernel 6.18.54.1-microsoft-standard-WSL2) |
| Sandbox | OpenShell (seccomp filters active) |
| Ruby | 4.0.7 (2026-09-15 revision 229531a6cf) +PRISM, YJIT via `--yjit` |
| graphql-ruby | 61759ed0641d893b171b00dd10a225997f59b622 |
| Spinel | e95ce05feb4aa37b027328fca75503a9c0446dec, unmodified |
| C compiler | GCC 13.3.0 (Ubuntu 13.3.0-6ubuntu2~24.04.1) |
