关于 Jetty 的性能调优，官网上给出了一些很好的建议，分为操作系统层面和 Jetty 本身的调优，我们将分别来看一看它们具体是怎么做的，最后再通过一个实战案例来学习一下如何确定 Jetty 的最佳线程数。

## 操作系统层面调优

对于 Linux 操作系统调优来说，我们需要加大一些默认的限制值，这些参数主要可以在/etc/security/limits.conf中或通过sysctl命令进行配置，其实这些配置对于 Tomcat 来说也是适用的，下面我来详细介绍一下这些参数。

### TCP 缓冲区大小

TCP 的发送和接收缓冲区最好加大到 16MB，可以通过下面的命令配置：
```
sysctl -w net.core.rmem_max = 16777216

sysctl -w net.core.wmem_max = 16777216

sysctl -w net.ipv4.tcp_rmem =“4096 87380 16777216”

sysctl -w net.ipv4.tcp_wmem =“4096 16384 16777216”
```
### TCP 队列大小

net.core.somaxconn控制 TCP 连接队列的大小，默认值为 128，在高并发情况下明显不够用，会出现拒绝连接的错误。但是这个值也不能调得过高，因为过多积压的 TCP 连接会消耗服务端的资源，并且会造成请求处理的延迟，给用户带来不好的体验。因此我建议适当调大，推荐设置为 4096。
```
sysctl -w net.core.somaxconn = 4096

net.core.netdev_max_backlog用来控制 Java 程序传入数据包队列的大小，可以适当调大。

sysctl -w net.core.netdev_max_backlog = 16384

sysctl -w net.ipv4.tcp_max_syn_backlog = 8192

sysctl -w net.ipv4.tcp_syncookies = 1
```

### 端口

如果 Web 应用程序作为客户端向远程服务器建立了很多 TCP 连接，可能会出现 TCP 端口不足的情况。因此最好增加使用的端口范围，并允许在 TIME_WAIT 中重用套接字：
```
sysctl -w net.ipv4.ip_local_port_range =“1024 65535”

sysctl -w net.ipv4.tcp_tw_recycle = 1
```

### 文件句柄数

高负载服务器的文件句柄数很容易耗尽，这是因为系统默认值通常比较低，我们可以在/etc/security/limits.conf中为特定用户增加文件句柄数：
```
用户名 hard nofile 40000

用户名 soft nofile 40000
```

### 拥塞控制

Linux 内核支持可插拔的拥塞控制算法，如果要获取内核可用的拥塞控制算法列表，可以通过下面的命令：
```
sysctl net.ipv4.tcp_available_congestion_control
```
这里我推荐将拥塞控制算法设置为 cubic：
```
sysctl -w net.ipv4.tcp_congestion_control = cubic
```
## Jetty 本身的调优

Jetty 本身的调优，主要是设置不同类型的线程的数量，包括 Acceptor 和 Thread Pool。

### Acceptors

Acceptor 的个数 accepts 应该设置为大于等于 1，并且小于等于 CPU 核数。

### Thread Pool

限制 Jetty 的任务队列非常重要。默认情况下，队列是无限的！因此，如果在高负载下超过 Web 应用的处理能力，Jetty 将在队列上积压大量待处理的请求。并且即使负载高峰过去了，Jetty 也不能正常响应新的请求，这是因为仍然有很多请求在队列等着被处理。

因此对于一个高可靠性的系统，我们应该通过使用有界队列立即拒绝过多的请求（也叫快速失败）。那队列的长度设置成多大呢，应该根据 Web 应用的处理速度而定。比如，如果 Web 应用每秒可以处理 100 个请求，当负载高峰到来，我们允许一个请求可以在队列积压 60 秒，那么我们就可以把队列长度设置为 60 × 100 = 6000。如果设置得太低，Jetty 将很快拒绝请求，无法处理正常的高峰负载，以下是配置示例：
```xml
<Configure id="Server" class="org.eclipse.jetty.server.Server">
<Set name="ThreadPool">
<New class="org.eclipse.jetty.util.thread.QueuedThreadPool">
<New class="java.util.concurrent.ArrayBlockingQueue">
<Arg type="int">6000
<Set name="minThreads">10
<Set name="maxThreads">200
<Set name="detailedDump">false
```

那如何配置 Jetty 的线程池中的线程数呢？跟 Tomcat 一样，你可以根据实际压测，如果 I/O 越密集，线程阻塞越严重，那么线程数就可以配置多一些。通常情况，增加线程数需要更多的内存，因此内存的最大值也要跟着调整，所以一般来说，Jetty 的最大线程数应该在 50 到 500 之间。

## 本期精华

今天我们首先学习了 Jetty 调优的基本思路，主要分为操作系统级别的调优和 Jetty 本身的调优，其中操作系统级别也适用于 Tomcat。接着我们通过一个实例来寻找 Jetty 的最佳线程数，在测试中我们发现，对于 CPU 密集型应用，将最大线程数设置 CPU 核数的 1.5 倍是最佳的。因此，在我们的实际工作中，切勿将线程池直接设置得很大，因为程序所需要的线程数可能会比我们想象的要小。