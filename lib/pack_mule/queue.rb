module PackMule
  # An abstract class representing a queue
  class Queue
    # The default priority for this queue
    def default_priority
      raise "Not Implemented"
    end

    # The default time to run for this queue
    def default_time_to_run
      raise "Not Implemented"
    end

    # call a method on the receiver passing the *args to it.
    # @argument priority [Fixnum] The priority with which to enqueue the job
    # @argument time_to_run [Fixnum] How long to let the job run before deciding it has died
    # @argument delay [Fixnum] Minimum time in seconds to wait before running the job
    # @return Job - an opaque object representing the work to be done.
    def enqueue(receiver, method, priority, time_to_run, delay, *args)
      raise "Not Implemented"
    end

    # @return [true,false] whether the job has finished yet
    def job_complete?(job)
      raise "Not Implemented"
    end

    def rrepr
      raise "Not Implemented"
    end
  end

  # A job is an opaque value that repesents a job that has been queued
  # it will be used to query the queue for status information.
  class Job
    def rrepr
      raise "Not Implemented"
    end
  end

  class AsyncObserverQueue < Queue
    include AsyncObserver::Extensions

    def make_queueable(obj)
      unless obj.is_a?(AsyncObserver::Extensions)
        replace_rrepr = false
        if obj.respond_to?(:rrepr)
          replace_rrepr = true
          class << obj
            alias_method :orig_rrepr, :rrepr
          end
        end
        obj.extend(AsyncObserver::Extensions) 
        if replace_rrepr
          class << obj
            alias_method :rrepr, :orig_rrepr
          end
        end
      end

    end

    def default_priority
      AsyncObserver::Queue.metaclass.const_get("DEFAULT_PRI")
    end
    def default_time_to_run
      AsyncObserver::Queue.metaclass.const_get("DEFAULT_TTR")
    end
    def enqueue(receiver, method, priority, time_to_run, delay, *args)
      make_queueable(receiver)
      opts = {
        :pri => priority,
        :ttr => time_to_run
      }
      opts[:delay] = delay if delay && delay > 0
      AsyncObserverJob.new *receiver.async_send_opts(method, opts, *args)
    end

    # Returns a boolean indicating whether a single job is complete.
    def job_complete?(job)
      stats(job)[:state].to_sym == :completed
    end

    # Get the stats for each job
    def stats(job)
      HashWithIndifferentAccess.new(connection(job.server).job_stats(job.id))
    rescue Beanstalk::NotFoundError
      # XXX Not sure this the best way to deal with this case.
      HashWithIndifferentAccess.new(:id => job.id, :state => "completed")
    end

    def connection(server)
      AsyncObserver::Queue.queue.instance_variable_get("@connections")[server]
    end

    def rrepr
      "#{self.class.name}.new"
    end
  end

  class AsyncObserverJob < Job
    attr_accessor :id, :server
    def initialize(id, server)
      self.id = id
      self.server = server
    end
    def rrepr
      %Q{#{self.class.name}.new(#{id.rrepr},#{server.rrepr})}
    end
  end
end
