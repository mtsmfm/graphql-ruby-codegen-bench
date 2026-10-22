# The two documents of graphql-ruby's profile_large_result, as text
# (check.rb checks they parse to ALL_FIELDS / ALL_METHOD_FIELDS).
LARGE_QUERIES = [
  "query($skip: Boolean = false) {
  foos {
    id @skip(if: $skip)
    int1
    int2
    string1
    string2
    boolean1
    boolean2
    stringArray
    intArray
    booleanArray
  }
}",
  "query($skip: Boolean = false) {
  foos: methodFoos {
    id @skip(if: $skip)
    int1
    int2
    string1
    string2
    boolean1
    boolean2
    stringArray
    intArray
    booleanArray
  }
}",
]
