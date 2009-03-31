# This class is built on top of:
# AsyncObserver for all its syntactic sugar
# Beanstalkd for job queueing and tracking
# Memcached for publishing progress and keeping a global list of tasks running
# Elockd for mutex server to keep the task list correct at all times.
# Metaid -- because how can you live without it?
#
# Code Example:
# class Jobs::SleepyRunner < Jobs::Runner
#   def run
#     100.times do
#       enqueue :snooze, rand(2)
#     end
#   end
# 
#   def snooze(duration)
#     sleep duration
#   end
# end
#
# To perform a job:
# Jobs::SleepyRunner.new("any_temporally_unique_name").run
#
# To monitor that job:
# runner = Jobs::SleepyRunner.new("any_temporally_unique_name")
# loop do puts "#{runner.update_progress} - #{eval(runner.current_progress) rescue 'Pending'}"; sleep 1 end
# runner.current_progress
# => "0.0 / 0.0"
# runner.current_progress
# => "0.0 / 12.0"
# runner.current_progress
# => "1.0 / 100.0"
# eval(runner.current_progress) * 100
# => 15.0

module Jobs
  class NoRemoteRepresentationError < StandardError
  end

  class ResultPending < StandardError
  end

  class ResultMissing < StandardError
  end

  class JobReference
    attr_accessor :id, :server
    def initialize(id, server)
      self.id = id
      self.server = server
    end
    def to_a
      [id, server]
    end
    alias dereference to_a
    def rrepr
      "#{self.class.rrepr}.new(#{id.rrepr}, #{server.rrepr})"
    end
  end

  class Runner

    include AsyncObserver::Extensions

    attr_accessor :name, :priority, :time_to_run
    attr_accessor :current_task_id
    attr_accessor :record_return_values
    attr_accessor :push_progress_updates

    def default_priority
      AsyncObserver::Queue.metaclass.const_get("DEFAULT_PRI")
    end

    def default_time_to_run
      AsyncObserver::Queue.metaclass.const_get("DEFAULT_TTR")
    end

    def initialize(name, priority = default_priority, record_return_values = false, push_progress_updates = false, time_to_run = default_time_to_run)
      @name = name
      @priority = priority
      @record_return_values = record_return_values
      @push_progress_updates = push_progress_updates
      @time_to_run = time_to_run
    end

    # Instantiate this object remotely.
    def rrepr
      "#{self.class.name}.new(#{name.rrepr}, #{priority.rrepr}, #{record_return_values.rrepr}, #{push_progress_updates.rrepr}, #{time_to_run.rrepr})"
    end

    def self.to_param
      name
    end

    def to_param
      name
    end

    def enqueue_each(method, list, *args)
      jobs = []
      list.each do |obj|
        log "Enqueueing job #{method.inspect} #{worker? ? "from within worker" : "from producer"} for #{obj.inspect}."
        jobs << async_send_opts(:process, {:pri => priority, :ttr => time_to_run}, method, [obj]+args)
      end
      add_jobs jobsd
    end

    # Enqueue a task related to this job, the total
    # amount of work remaining will be incremented by one.
    # Returns a reference to the job
    def enqueue(method, *args)
      add_job *async_send_opts(:process, {:pri => priority, :ttr => time_to_run}, method, args)
    end

    # Processes the enqueued tasks, records the return value,
    # and ensures that the progress gets updated shortly after it returns
    def process(method, args)
      begin
        @deferred = nil
        rv = send(method, *args)
        set_return_value(rv) if record_return_values unless @deferred
      rescue => e
        if respond_to?(:handle_error)
          increment_error_count
          rv = handle_error(e)
          set_return_value(rv) if record_return_values
        else
          raise
        end
      end
    ensure
      update_progress_in_bit if push_progress_updates
    end

    # Returns the number of errors that have occurred
    def get_error_count
      CACHE[error_count_key] || 0
    end

    # Access the cached progress as set by the last update_progress call.
    def current_progress
      CACHE[progress_key] || "0 / 0"
    end

    # Returns the number of missing results
    def get_missing_result_count
      CACHE[missing_result_count_key] || 0
    end

    # Returns the completion status of this entire runner.
    def complete?
      !!job_states.detect{|state| state != :completed}
    end

    def jobs
      eval(CACHE[jobs_key] || "[]")
    end
  
    # Returns an array of the current states of all the jobs related to this runner.
    def job_states
      stats = jobs.map{|job| stats(*job)}
      stats.map{|s| s[:state].to_sym}
    end

    # Compute and return the current progress
    def update_progress
      states = job_states
      completed, pending = states.partition{|state| state == :completed}
      CACHE[progress_key] = "#{completed.size.to_f} / #{states.size.to_f}"
    end

    # This method defers until the dependencies complete.
    def deferred_result_as_worker(method, jobs, options, *args)
      @deferred = true
      begin
        log "Defer for #{$current_job.inspect}: Processing"
        return_values = get_return_values!(jobs, options)
        log "Defer for #{$current_job.inspect}: Return Values: #{return_values.rrepr}"
        rv = send(method, return_values, *args)
        log "Defer for #{$current_job.inspect}: Deferred Value: #{rv.rrepr}"
        set_return_value rv
      rescue ResultPending
        # We post a new job, because AO doesn't have a good way for the job
        # code to delay itself. If we get an API enhancement, this could be made
        # more efficient.
        opts = {
          :pri => (priority + 1),
          :ttr => time_to_run,
          :delay => options.fetch(:sleep_time, 1).round
        }
        log "Defer for #{$current_job.inspect}: Some results are pending. Requeueing."
        new_job = async_send_opts(:deferred_result_as_worker, opts, method, jobs, options, *args)
        add_job *new_job
        set_return_value JobReference.new(*new_job)
      rescue => e
        if respond_to?(:handle_error)
          increment_error_count
          rv = handle_error(e)
          set_return_value(rv) if record_return_values
        else
          if e.is_a?(ResultMissing)
            # We can't recover from this error. Raising here will cause an AO requeue loop.
            log "ERROR: A result went mising and there was no error handler to deal with it. shucks.", :error
          else
            raise
          end
        end
      end
    ensure
      update_progress_in_bit if push_progress_updates
    end

    # Returns a boolean indicating whether a single job is complete.
    def job_complete?(id, server)
      stats(id, server)[:state].to_sym == :completed
    end

    # Gets all the return values for all the jobs provided
    # Raises a ResultPending error if there are any pending jobs
    # If :halt_on_data_loss is set to false missing values are returned with the value :__missing
    # Otherwise, it raises a ResultMissing error if a result gets lost for any reason.
    def get_return_values!(jobs, options)
      return_values = evaluated_return_values
      values = jobs.map {|j| get_return_value!(j, return_values) }
      missing_jobs = jobs.zip(values).select{|job, value| value == :__missing}.map(&:first)

      if missing_jobs.any?
        if options.fetch(:halt_on_data_loss, true)
          raise ResultMissing.new(missing_jobs.rrepr)
        else
          increment_missing_result_count missing_jobs.size
        end
      end
      values
    end

    # Fetch one return value from a return value hash
    # If the return value is a reference to another job, recurse on that job
    # Deal with missing values in the following way:
    # If the job is pending raise ResultPending
    # If the job is complete and we don't have a return value, returns :__missing
    def get_return_value!(job = first_job_queued, return_values = evaluated_return_values)
      v = return_values.fetch(job, :__missing)
      if v == :__missing
        if job_complete?(*job)
          :__missing
        else
          raise ResultPending.new(job.rrepr)
        end
      elsif v.is_a?(JobReference)
        get_return_value!(v.dereference, return_values)
      else
        v
      end
    end

    # Returns the first job we queued. It's likely to be the primary task for this runner.
    def first_job_queued
      jobs.first
    end

    # Get the stats for each job
    def stats(id, server)
      HashWithIndifferentAccess.new(connection(server).job_stats(id))
    rescue Beanstalk::NotFoundError
      HashWithIndifferentAccess.new(:id => id, :state => "completed")
    end

    protected

    def base_cache_key
      @base_cache_key ||= "#{self.class.name.underscore}:#{name}"
    end

    def progress_key
      @progress_key ||= "#{base_cache_key}:progress"
    end

    def return_values_key
      @return_values_key ||= "#{base_cache_key}:return_values"
    end

    def jobs_key
      @jobs_key ||= "#{base_cache_key}:jobs"
    end

    def error_count_key
      @error_count_key ||= "#{base_cache_key}:error_count"
    end

    def missing_result_count_key
      @missing_result_count_key ||= "#{base_cache_key}:missing_result_count"
    end

    def increment_error_count
      synchronized(error_count_key) do
        CACHE[error_count_key] = get_error_count + 1
      end
    end

    def increment_missing_result_count(by = 1)
      synchronized(missing_result_count_key) do
        CACHE[missing_result_count_key] = get_missing_result_count + by
      end
    end

    def add_jobs(jobs)
      synchronized(jobs_key) do
        log "Adding #{jobs.size} jobs #{worker? ? "from within worker" : "from producer"}."
        existing_jobs = self.jobs
        existing_jobs += jobs
        CACHE[jobs_key] = existing_jobs.rrepr
      end
      jobs
    ensure
      update_progress if push_progress_updates
    end

    def add_job(id, server)
      synchronized(jobs_key) do
        log "Adding Job #{worker? ? "from within worker" : "from producer"}: #{id}"
        jobs = self.jobs
        jobs << [id, server]
        CACHE[jobs_key] = jobs.rrepr
      end
      [id, server]
    ensure
      update_progress if push_progress_updates
    end

    def with_deferral_options(opts)
      @deferral_options = opts
      yield
    ensure
      @deferral_options = nil
    end

    def deferred_result(method, jobs, *args)
      deferred_result_opts(method, jobs, @deferral_options || {}, *args)
    end

    def deferred_result_opts(method, jobs, options, *args)
      if worker?
        deferred_result_as_worker(method, jobs, options, *args)
      else
        deferred_result_as_publisher(method, jobs, options, *args)
      end
    end

    # This method blocks until it completes.
    # I guess you have a bunch of processing power
    def deferred_result_as_publisher(method, jobs, options, *args)
      loop do
        begin
          return send(method, get_return_values!(jobs, options), *args)
        rescue ResultPending
          sleep options.fetch(:sleep_time, 1)
        end
      end
    end

    def worker?
      !$current_job.nil?
    end

    # This can only be called from within the worker
    def set_return_value(rv)
      job = $current_job
      log "Setting return value for #{job.rrepr}: #{rv.rrepr}"
      synchronized(return_values_key) do
        return_values = CACHE[return_values_key] || {}
        return_values[job] = rv.rrepr
        CACHE[return_values_key] = return_values
      end
    rescue NoMethodError => nme
      if $! =~ /rrepr/
        raise NoRemoteRepresentationError.new($!)
      else
        raise
      end
    end

    def evaluated_return_values
      returning(CACHE[return_values_key] || Hash.new) do |rvs|
        for key in rvs.keys
          rvs.update(key => eval(rvs[key]))
        end
      end
    end

    def connection(server)
      AsyncObserver::Queue.queue.instance_variable_get("@connections")[server]
    end

    def update_progress_in_bit
      # Queue a higher priority job to update the progress in memcached
      async_send_opts(:update_progress, :pri => (priority - 10))
    end

    def synchronized(key)
      loop do
        begin
          LOCK_SERVICE.with_lock(key, 2) do
            return yield
          end
        rescue Locked
          log("Failed to get lock for #{key}. Trying again.", :warn)
        end
      end
    end

    def log(message, level = :info)
      RAILS_DEFAULT_LOGGER.send(level, message)
    end

  end
end