# Generated executor, as profile_large_result runs graphql-ruby: the document
# is parsed once, each call validates and executes it.
require_relative "large_exec"
require_relative "queries"
require_relative "timing"
names = ["exec", "exec method"]
i = 0
while i < LARGE_QUERIES.size
  doc = GQLParser.new(LARGE_QUERIES[i]).parse
  3.times { gql_execute_doc(doc, {}, {}) }
  ms = median_ms(1.0, 5) { gql_execute_doc(doc, {}, {}) }
  puts "#{names[i]}\t#{ms.round(3)} ms"
  i += 1
end
