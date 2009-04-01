module PackMule
  module AsyncOberserverExtensions
    def self.included(base)
      base.alias_method_chain :run_ao_job, :a_pack_mule
    end

    def run_ao_job_with_a_pack_mule(job)
      old_current_job, $current_job = $current_job, [job.id, job.conn.addr]
      run_ao_job_without_a_pack_mule(job)
    ensure
      $current_job = old_current_job
    end
  end
end
