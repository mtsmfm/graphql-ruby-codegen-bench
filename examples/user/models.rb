# Plain Ruby data for the schema in schema.rb.
class User
  attr_reader :name

  def initialize(name)
    @name = name
  end
end

USERS = [User.new("Alice"), User.new("Bob")]
