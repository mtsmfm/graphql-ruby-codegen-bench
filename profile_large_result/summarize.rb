# Minimum over the rounds of compare.sh's output, per data mode, runner and engine (ms).
rows = Hash.new { |h, k| h[k] = [] }
File.foreach(ARGV.fetch(0)) do |line|
  next unless line =~ /\AR\d+ (lazy|eager) (\S+) (\S+) (.*)/
  mode, engine, runner, rest = $1, $2, $3, $4
  rest.scan(/([a-z_ ]+?)\|([\d.]+) ms/) { |name, ms| rows[[mode, engine, runner, name.strip]] << ms.to_f }
end
%w[lazy eager].each do |mode|
  puts "#{mode} (min of #{rows.values.first&.size} rounds, ms)"
  printf("  %-22s %8s %8s %8s\n", "", "interp", "yjit", "spinel")
  [["graphql-ruby legacy", "graphql-ruby", "exec"], ["graphql-ruby next", "graphql-ruby", "exec_next"],
   ["generated depth-first", "gen-depth", "exec"], ["generated breadth-first", "gen-batch", "exec"]].each do |label, engine, name|
    cells = %w[interp yjit spinel].map do |runner|
      v = rows[[mode, engine, runner, name]]
      v.empty? ? "-" : format("%.2f", v.min)
    end
    printf("  %-22s %8s %8s %8s\n", label, *cells)
  end
end
