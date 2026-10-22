# Shared timing: ROUNDS rounds of about SEC seconds each; median ms per call.
def median_ms(sec, rounds)
  results = []
  r = 0
  while r < rounds
    n = 0
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    t = t0
    while t - t0 < sec
      yield
      n += 1
      t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
    results << (t - t0) * 1000.0 / n
    r += 1
  end
  results.sort[rounds / 2]
end
