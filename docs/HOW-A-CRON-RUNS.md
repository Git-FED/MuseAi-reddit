# How a Cron Runs

A cron is the timing layer. It does not do the work itself; it fires at the configured time and starts a job.

1. The clock reaches the schedule.
2. The cron fires one job.
3. A worker is assigned to that run.
4. The worker operates its lane or task.
5. The worker hands its result back to the main agent.
6. Verification happens before the result is reported as done.

The useful distinction is: **cron is when, job is what, worker is who, run is one occurrence**.
