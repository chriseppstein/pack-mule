Pack Mule
=========

Pack Mule give you the facilities you need to run your code for hours or seconds in parallel across your cluster of Beanstalk workers. You can monitor the progress, coordinate tasks, and get results back when they complete.

Usage Example
-------------
We name our runner so that we can query it later. The false argument tells the runner not to
publish progress updates -- instead we'll be asking for it when we need it.

    >> runner = SleepyRunner.new("this_is_an_arbitrary_name", false)
    => #<SleepyRunner:0x6444c>

First we can run the tasks in the background and block until they are done:

    >> runner.run
    => 51

Or we can run it in the background:

    >> task = runner.run_async
    => [1, 'localhost:11300']
The enqueue method returns a job reference which is just a tuple of a job id and a beanstalk server.

We can now ask for overall progress:

    >> runner.update_progress
    => "53.0 / 101.0"

progress is returned as a string that can be eval'd to give a percentage
or you can split on " / " to get the number of jobs completed and queued.

Any instance with the same name will work:

    >> SleepyRunner.new("this_is_an_arbitrary_name").update_progress
    => "59.0 / 101.0"

So we wait a while and ask for an updated progress

    >> runner.update_progress
    => "101.0 / 101.0"

Now that it's finished, we can access our return value now:

    >> runner.get_return_value!
    => 53

Building Your Mule
------------------

Your mule is any class that inherits from PackMule::Runner

    require 'pack_mule'
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

You really only need to know about two special methods to build your mule:

### <code>enqueue(method_name, *args)</code>

The enqueue method has the same syntax as <code>send</code> but instead of calling the method immediately, it queues the method call through beanstalk and it will run as a separate job. Enqueue returns a reference to the job instead of a return value. Hold on to that, because you will need it later. Enqueue may be called any number of times, but if you plan to call it a lot, you might consider using <code>enqueue_each(method, list, *args)</code> because it will run faster.

### <code>deferred\_result(method_name, jobs, *args)</code>

The deferred\_result method will call the method you specify passing the return values for the jobs and any additional arguments you passed to it. If you call deferred\_result from a synchronous context, it will block until all the jobs have completed and return the result of the deferred method. If you call it from within an asynchronous context, it will not block -- instead it returns a JobReference instance to the job that will check for results later. PackMule knows about JobReferences and will take care of all the tracking for you. If you ask for the return value of the original task it will go find it for you.

### Instantiation Options

* <code>record\_return\_values</code> - set to true if you want to capture return values. Otherwise, they'll be mixed with the hay and feed to the mules. All return values must respond to <code>rrepr</code>.
* <code>push\_progress\_updates</code> - If you are reading your progress more often than it changes set this to true. You can then use <code>current\_progress</code> to read it instead of <code>update\_progress</code> and the current\_progress will be updated for you whenever it changes.
* <code>time\_to\_run</code> - Defaults to <code>2.minutes</code>. If any method takes longer there's a pretty good chance it will get ran again. Set this to the twice the maximum amount of time you expect any method to take.