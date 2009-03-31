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
