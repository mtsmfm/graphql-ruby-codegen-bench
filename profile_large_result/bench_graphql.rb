# graphql-ruby on the same data: the four reports of profile_large_result.
require_relative "schema"
require_relative "timing"
s = ProfileLargeResult::Schema
doc = ProfileLargeResult::ALL_FIELDS
mdoc = ProfileLargeResult::ALL_METHOD_FIELDS
[["exec", -> { s.execute(document: doc) }], ["exec method", -> { s.execute(document: mdoc) }],
 ["exec_next", -> { s.execute_next(document: doc) }], ["exec_next method", -> { s.execute_next(document: mdoc) }]].each do |name, run|
  3.times { run.call }
  puts "#{name}\t#{median_ms(1.0, 5) { run.call }.round(3)} ms"
end
