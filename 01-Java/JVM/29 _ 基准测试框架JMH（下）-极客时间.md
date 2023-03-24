$ java -jar target/benchmarks.jar

...

\# JMH version: 1.21

\# VM version: JDK 10.0.2, Java HotSpot(TM) 64-Bit Server VM, 10.0.2+13

\# VM invoker: /Library/Java/JavaVirtualMachines/jdk-10.0.2.jdk/Contents/Home/bin/java

\# VM options: &lt;none&gt;

\# Warmup: 5 iterations, 10 s each

\# Measurement: 5 iterations, 10 s each

\# Timeout: 10 min per iteration

\# Threads: 1 thread, will synchronize iterations

\# Benchmark mode: Throughput, ops/time

\# Benchmark: org.sample.MyBenchmark.testMethod

\# Run progress: 0,00% complete, ETA 00:08:20

\# Fork: 1 of 5

\# Warmup Iteration 1: 1023500,647 ops/s

\# Warmup Iteration 2: 1030767,909 ops/s

\# Warmup Iteration 3: 1018212,559 ops/s

\# Warmup Iteration 4: 1002045,519 ops/s

\# Warmup Iteration 5: 1004210,056 ops/s

Iteration 1: 1010251,342 ops/s

Iteration 2: 1005717,344 ops/s

Iteration 3: 1004751,523 ops/s

Iteration 4: 1003034,640 ops/s

Iteration 5: 997003,830 ops/s

\# Run progress: 20,00% complete, ETA 00:06:41

\# Fork: 2 of 5

...

\# Run progress: 80,00% complete, ETA 00:01:40

\# Fork: 5 of 5

\# Warmup Iteration 1: 988321,959 ops/s

\# Warmup Iteration 2: 999486,531 ops/s

\# Warmup Iteration 3: 1004856,886 ops/s

\# Warmup Iteration 4: 1004810,860 ops/s

\# Warmup Iteration 5: 1002332,077 ops/s

Iteration 1: 1011871,670 ops/s

Iteration 2: 1002653,844 ops/s

Iteration 3: 1003568,030 ops/s

Iteration 4: 1002724,752 ops/s

Iteration 5: 1001507,408 ops/s

Result "org.sample.MyBenchmark.testMethod":

1004801,393 ±(99.9%) 4055,462 ops/s \[Average\]

(min, avg, max) = (992193,459, 1004801,393, 1014504,226), stdev = 5413,926

CI (99.9%): \[1000745,931, 1008856,856\] (assumes normal distribution)

\# Run complete. Total time: 00:08:22

...

Benchmark Mode Cnt Score Error Units

MyBenchmark.testMethod thrpt 25 1004801,393 ± 4055,462 ops/s