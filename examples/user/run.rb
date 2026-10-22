# Runs a query with the generated user_exec.rb (no graphql-ruby needed).
#   ruby run.rb '{ users { name } }'
require "json"
require_relative "user_exec"
puts JSON.generate(gql_execute(ARGV.fetch(0, "{ users { name } }"), {}, {}))
