笔者在一个 Websocket 中间件产品（Apush，[https://market.aliyun.com/products/56928004/cmapi020699.html#sku=yuncode1469900000](https://market.aliyun.com/products/56928004/cmapi020699.html#sku=yuncode1469900000)）的集群管理中使用了 zk 的 EPHEMERAL 节点机制。  
在编码过程中发现很多可能存在的陷阱，毛估估，第一次使用 zk 来实现集群管理的人应该有 80% 以上会掉坑，有些坑比较隐蔽，在网络问题或者异常的场景时才会出现，可能很长一段时间才会暴露出来。

  

## 1、不处理 zk 的连接状态变化事件导致 zk 客户端断开后与 zk 服务器集群没有重连。后果：连接丢失后 EPHEMERAL 节点会删除并且客户端 watch 丢失。

  

此坑不深，稍微注意一下还是容易发现的，并且采用 Curator 会减少此类问题的发生，不是完全避免，具体见第 6 个坑。

  

zk 客户端如果和某台 zk 服务器断开，会主动尝试与 zk 集群中其他服务器重新连接，直到 sessiontimeout，需要考虑极端的情况下出现 sessiontimeout 的处理。  
zk 客户端和 zk 服务器断开时会收到 state 为 Disconnected 的连接事件，此事件一般可以不处理，此事件后续会跟 Expired 状态的连接事件或者 synconnected 状态的连接事件。  
zk 客户端连接重试失败并且达到 sessiontimeout 时间则会收到 Expired 状态的连接事件，在此事件中应该由应用程序重试建立 zk 客户端。

  

## 2、在 synconnected 事件中创建 EPHEMERAL 节点没有判断此节点是否已经存在，在已经存在的情况下没有判断是否应该删除重建，后果：EPHEMERAL 节点丢失导致可用的服务器不在可用服务器列表中。

  

此坑是个深坑，很隐蔽，而且没看到文章来提醒此坑。一般也不会出现问题，除非服务异常终止后立即重启。

  

一般我们会 synconnected 状态的连接事件中创建 EPHEMERAL 节点，注册 watch。  
synconnected 状态的连接事件中处理 EPHEMERAL 节点可以分三种场景：  
1、在第一次连接建立时  
2、在断开连接后，sessiontimeout 以前客户端自动重连成功  
3、老的客户端没有正常调用 close 进行关闭，并且在此客户端 sessiontimeout 以前，创建了一个新的客户端  
先说明一下第 3 种场景，session 是否过期是由 server 判断的，如果客户不是调用 close 来和服务器主动断开，服务端会等客户端重连，直到 session timeout。因此可能出现老 session 未过期，新客户端来建新 session 的情况。

  

在第 2 和第 3 种场景下，EPHEMERAL 节点都会在服务端存在。  
第 3 种场景下，随着残留在 zk 服务端 session 的 timeout，老的 EPHEMERAL 节点会被自动删除。  
由于 zk 的每个 session 都产生一个新的 sessionId，为了区分第 2、3 种场景，必须在每次 synconnected 状态的连接事件中比较当前 sessionId 和上次 sessionId。  
在 synconnected 状态的连接事件中要同时判断 sessionId 是否变化以及 EPHEMERAL 节点是否已经存在。  
对 sessionId 发生了变化且 EPHEMERAL 节点已经存在的情况要先删除后重建，这个是使用 Curator 也避免不了的。

  

## 3、应用程序关闭时不主动关闭 zk 客户端，后果：导致可用服务器列表包含已经失效的服务器。

  

原因同第 2 条，会导致 EPHEMERAL 节点在 sessiontimeout 之前都存在。  
如果 sessiontimeout 时间很长的话，会导致整个集群的可用服务列表长时间包含已关闭的服务器。

  

## 4、创建一个 zk 客户端时，zk 客户端连接 zk 服务器是异步的，如果在连接还没有建立时就调用 zk 客户端会抛异常。

  

正确的做法是在 synconnected 状态的连接事件中进行连接后的处理或者阻塞线程在连接事件中通知取消阻塞。  
Curator 提供了连接时同步阻塞的功能，可以避免此问题。

  

## 5、在 zk 的事件中执行长时间的业务

  

所有的 zk 事件都在 EventThread 中按顺序执行，如果一个事件长时间执行会导致其他事件无法及时响应。

  

## 6、使用 2.X 版本的 Curator 时，ExponentialBackoffRetry 的 maxRetries 参数设置的再大都会被限制到 29：MAX_RETRIES_LIMIT。

  

这个坑真不知道 Curator 是怎么想的，文档里一般也没提到这个坑。重试次数不够导致机房断网测试时 zk 的客户端可能永久丢失连接，据说新版本里已经增加了 ForeverRetry。最后我放弃了 Curator 回到原生 zk 客户端。

  

1.  zk 内部两个后台线程：IO 和心跳线程（SendThread），事件处理线程（EventThread），均为单线程，且互相独立。所以 eventthread 堵塞，不会导致心跳超时；另外由于 event thread 单线程，如果在 process 过程中堵塞，其他事件即使发生了，也只会放到本地队列中，暂时不会执行。

2.  如果 client 与 zkserver 连接中断，client 的 sendthread 会使用原来的 sessionid 一直尝试重连，连上后 server 判断该 sessionid 是否已经过期，如果未过期，则 SyncConnected 会通知给 client，同时期间的 watcher 事件也会通知给 client，不会丢失；如果已过期，则 client 会收到到 Expired 状态的连接事件，sendthread, eventthread 都退出，当前 client 失效。

3.  session 是否过期是由 server 判断的；如果过期了则 client 使用原来的 sessionid 连接进来时，会收到 expired 状态的连接事件。由 server 来判断 session 是否过期主要是因为 server 需要清理该 session 相关的 emphemeral 节点并且通知其他客户端；如果由 client 判断再通知 server，在 client 被直接 kill 掉的情况下，client 创建的临时节点就清理不掉了；如果 client 和 server 各自判断，会有同步问题。

4.  一个 zk 客户端连接断开后只要在 session 超时期限内重连成功，session 会保持。

5.  注册的 watch 事件和 EPHEMERAL 临时节点和 session 关联和连接没有关系。

6.  客户端连接没有 close 就断开，服务端 session 仍然存活直到 session 超时。

  

## 原生 zk 客户端的连接事件里面几个关键状态

  

-   SyncConnected 连接成功和重连成功时触发

-   Disconnected 连接断开时触发

-   Expired session 过期时触发

  

## Curator 的连接事件里面几个关键状态

  

-   CONNECTED 第一次连接

-   SUSPENDED 对应原生的 Disconnected

-   LOST 对应原生的 Expired

-   RECONNECTED 包括 sessionid 不变的重连和 sessionid 变化的重连，如果客户端建立了 EPHEMERAL 节点, 必须在此事件中判断 sessionId。  
    对应 sessionId 不变的情况，连接断开期间 watch 的事件不会丢失，如果 sessionId 变化，则期间 watch 的事件会丢失。  
    [https://developer.aliyun.com/article/227260](https://developer.aliyun.com/article/227260)