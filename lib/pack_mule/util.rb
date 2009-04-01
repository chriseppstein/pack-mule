module PackMule
  module Util
    extend self

    def pretty_progress(runner)
      prog = runner.update_progress
      counts = prog.split(" / ")
      remaining = (counts[1].to_f - counts[0].to_f).round
      percent = (eval(prog)* 10000).round.to_f / 100
      "#{percent}% Complete - #{remaining} Jobs Remaining of #{counts[1].round} Jobs"
    end

    # Useful for tracking progress from the console.
    def track_progress(runner, sleep_time = 1)
      loop do
        puts pretty_progress(runner)
        sleep sleep_time
      end
    end
  end
end