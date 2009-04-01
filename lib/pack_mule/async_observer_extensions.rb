module PackMule
  module AsyncOberserverExtensions

    module WorkerMetaClass
      def new(*args)
        super.extend(Worker)
      end
    end

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
