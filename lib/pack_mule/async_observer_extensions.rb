module PackMule
  module AsyncOberserverExtensions

    # This module is extended on the AsyncObserver::Worker class
    # it overrides new so that it can extend all returned instances
    # with the PackMule::AsyncOberserverExtensions::Worker module.
    module WorkerMetaClass
      def new(*args)
        super.extend(Worker)
      end
    end

    # This module is extended onto instances of the AsyncObserver::Worker class.
    # It wraps safe_dispatch to track the current job as a global variable.
    module Worker
      def safe_dispatch(job)
        old_current_job, $current_job = $current_job, [job.id, job.conn.addr]
        super(job)
      ensure
        $current_job = old_current_job
      end
    end
  end
end
