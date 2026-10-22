# The Spinel program: build DATA as benchmark/run.rb does (SecureRandom), print
# it with every lazy value resolved (line 1), then the two documents' results.
# check.rb replays line 1 through graphql-ruby and compares the rest.
require_relative "exec_batch"
require_relative "../queries"

def plain_value(v)
  while v.is_a?(Proc)
    v = v.call
  end
  if v.is_a?(Hash)
    h = {}
    v.each { |k, x| h[k] = plain_value(x) }
    h
  elsif v.is_a?(Array)
    a = []
    v.each { |x| a << plain_value(x) }
    a
  else
    v
  end
end

p plain_value(ProfileLargeResult::DATA)
i = 0
while i < LARGE_QUERIES.size
  p gql_execute(LARGE_QUERIES[i], {}, {})
  i += 1
end
