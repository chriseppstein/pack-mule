require 'pack_mule'

# This runner enqueue some jobs to sleep for a short time and returns the total time spent asleep.
class SleepyRunner < PackMule::Runner

  def initialize(*args)
    super
    @record_return_values = true
  end

  def run_async(nap_count = 100)
    enqueue :run
  end

  def run(nap_count = 100)
    jobs = []
    nap_count.times do
      jobs << enqueue :snooze, rand(2)
    end
    deferred_result :wakeup, jobs
  end

  def wakeup(durations)
    durations.inject(0){|total, duration| total + duration}
  end

  def snooze(duration)
    sleep duration
  end
end