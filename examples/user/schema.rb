# The smallest schema: one object type with one field.
require "graphql"
require_relative "models"

class UserType < GraphQL::Schema::Object
  graphql_name "User"
  field :name, String, null: false
end

class QueryType < GraphQL::Schema::Object
  graphql_name "Query"
  field :users, [UserType], null: false
  def users = USERS
end

class UserSchema < GraphQL::Schema
  query QueryType
end
