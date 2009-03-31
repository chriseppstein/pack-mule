# Jobs::FibonacciRunner.new("fib1").fibonacci(10)
class FibonacciRunner < PackMule::Runner
  def initialize(*args)
    super
    @record_return_values = true
  end

  # Be careful, this is a really good way to swamp your workers.
  def fibonacci(n)
    if n <= 0
      0
    elsif n == 1
      1
    elsif n == 2
      3
    else
      # TODO: This could be optimized by recording which job is going to calculate fibonacci(n) and
      # deferring to that one instead of a new one.
      j1 = enqueue :fibonacci, n - 1
      j2 = enqueue :fibonacci, n - 2
      deferred_result :add_together, [j1, j2]
    end
  end

  def add_together(values)
    values.first + values.last
  end
end