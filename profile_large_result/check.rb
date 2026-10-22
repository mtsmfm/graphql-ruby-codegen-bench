# Check a run.rb output (stdin) against graphql-ruby: rebuild DATA from line 1,
# wrapped in lambdas where benchmark/run.rb wraps them (unless EAGER), run both
# documents with execute and execute_next, and compare with the other lines.
require_relative "schema"
require_relative "queries"
lines = $stdin.readlines
raw = eval(lines.fetch(0)) # our own output: an Array of Symbol-keyed Hashes
lazy = ->(v) { ProfileLargeResult.eager_or_proc(v) }
data = raw.map do |h|
  lazy.(h.merge(string1: lazy.(h[:string1]), int_array: lazy.(h[:int_array].map { |x| lazy.(x) })))
end
ProfileLargeResult.send(:remove_const, :DATA)
ProfileLargeResult.const_set(:DATA, data)
s = ProfileLargeResult::Schema
docs = [ProfileLargeResult::ALL_FIELDS, ProfileLargeResult::ALL_METHOD_FIELDS]
ok = true
docs.each_with_index do |doc, i|
  abort "queries.rb[#{i}] differs from the benchmark document" unless GraphQL.parse(LARGE_QUERIES[i]) == doc
  want = s.execute(document: doc).to_h
  abort "execute_next differs from execute" unless s.execute_next(document: doc).to_h == want
  got = lines.fetch(i + 1)
  if got == want.inspect + "\n"
    puts "  doc #{i}: identical to graphql-ruby (#{got.bytesize} bytes, #{want["data"]["foos"].size} foos)"
  else
    ok = false
    puts "  doc #{i}: DIFFERS"
  end
end
exit(ok ? 0 : 1)
