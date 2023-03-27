# 总体架构-connector

Jetty 是 Eclipse 基金会的一个开源项目，和 Tomcat 一样，Jetty 也是一个“HTTP 服务器 + Servlet 容器”，并且 Jetty 和 Tomcat 在架构设计上有不少相似的地方。但同时 Jetty 也有自己的特点，主要是更加小巧，更易于定制化。Jetty 作为一名后起之秀，应用范围也越来越广，比如 Google App Engine 就采用了 Jetty 来作为 Web 容器。Jetty 和 Tomcat 各有特点，所以今天我会和你重点聊聊 Jetty 在哪些地方跟 Tomcat 不同。通过比较它们的差异，一方面希望可以继续加深你对 Web 容器架构设计的理解，另一方面也让你更清楚它们的设计区别，并根据它们的特点来选用这两款 Web 容器。

## 鸟瞰 Jetty 整体架构

简单来说，Jetty Server 就是由多个 Connector（连接器）、多个 Handler（处理器），以及一个线程池组成。整体结构请看下面这张图。

![[Pasted image 20230327155742.png]]

跟 Tomcat 一样，Jetty 也有 HTTP 服务器和 Servlet 容器的功能，因此 Jetty 中的 Connector 组件和 Handler 组件分别来实现这两个功能，而这两个组件工作时所需要的线程资源都直接从一个全局线程池 ThreadPool 中获取。

Jetty Server 可以有多个 Connector 在不同的端口上监听客户请求，而对于请求处理的 Handler 组件，也可以根据具体场景使用不同的 Handler。这样的设计提高了 Jetty 的灵活性，需要支持 Servlet，则可以使用 ServletHandler；需要支持 Session，则再增加一个 SessionHandler。也就是说我们可以不使用 Servlet 或者 Session，只要不配置这个 Handler 就行了。

为了启动和协调上面的核心组件工作，Jetty 提供了一个 Server 类来做这个事情，它负责创建并初始化 Connector、Handler、ThreadPool 组件，然后调用 start 方法启动它们。

我们对比一下 Tomcat 的整体架构图，你会发现 Tomcat 在整体上跟 Jetty 很相似，它们的第一个区别是 Jetty 中没有 Service 的概念，Tomcat 中的 Service 包装了多个连接器和一个容器组件，一个 Tomcat 实例可以配置多个 Service，不同的 Service 通过不同的连接器监听不同的端口；而 Jetty 中 Connector 是被所有 Handler 共享的。

![[Pasted image 20230327155751.png]]

它们的第二个区别是，在 Tomcat 中每个连接器都有自己的线程池，而在 Jetty 中所有的 Connector 共享一个全局的线程池。

讲完了 Jetty 的整体架构，接下来我来详细分析 Jetty 的 Connector 组件的设计，下一期我将分析 Handler 组件的设计。

## Connector 组件

跟 Tomcat 一样，Connector 的主要功能是对 I/O 模型和应用层协议的封装。I/O 模型方面，最新的 Jetty 9 版本只支持 NIO，因此 Jetty 的 Connector 设计有明显的 Java NIO 通信模型的痕迹。至于应用层协议方面，跟 Tomcat 的 Processor 一样，Jetty 抽象出了 Connection 组件来封装应用层协议的差异。

Java NIO 早已成为程序员的必备技能，并且也经常出现在面试题中。接下来我们一起来看看 Jetty 是如何实现 NIO 模型的，以及它是怎么用Java NIO 的。

Java NIO 回顾

关于 Java NIO 编程，如果你还不太熟悉，可以先学习这一系列文章。Java NIO 的核心组件是 Channel、Buffer 和 Selector。Channel 表示一个连接，可以理解为一个 Socket，通过它可以读取和写入数据，但是并不能直接操作数据，需要通过 Buffer 来中转。

Selector 可以用来检测 Channel 上的 I/O 事件，比如读就绪、写就绪、连接就绪，一个 Selector 可以同时处理多个 Channel，因此单个线程可以监听多个 Channel，这样会大量减少线程上下文切换的开销。下面我们通过一个典型的服务端 NIO 程序来回顾一下如何使用这些组件。

首先，创建服务端 Channel，绑定监听端口并把 Channel 设置为非阻塞方式。

![[Pasted image 20230327155811.png]]

然后，创建 Selector，并在 Selector 中注册 Channel 感兴趣的事件 OP_ACCEPT，告诉 Selector 如果客户端有新的连接请求到这个端口就通知我。

![[Pasted image 20230327155818.png]]

接下来，Selector 会在一个死循环里不断地调用 select 去查询 I/O 状态，select 会返回一个 SelectionKey 列表，Selector 会遍历这个列表，看看是否有“客户”感兴趣的事件，如果有，就采取相应的动作。

比如下面这个例子，如果有新的连接请求，就会建立一个新的连接。连接建立后，再注册 Channel 的可读事件到 Selector 中，告诉 Selector 我对这个 Channel 上是否有新的数据到达感兴趣。

![[Pasted image 20230327155826.png]]

简单回顾完服务端 NIO 编程之后，你会发现服务端在 I/O 通信上主要完成了三件事情：监听连接、I/O 事件查询以及数据读写。因此 Jetty 设计了 Acceptor、SelectorManager 和 Connection 来分别做这三件事情，下面我分别来说说这三个组件。

Acceptor

顾名思义，Acceptor 用于接受请求，跟 Tomcat 一样，Jetty 也有独立的 Acceptor 线程组用于处理连接请求。在 Connector 的实现类 ServerConnector 中，有一个_acceptors的数组，在 Connector 启动的时候, 会根据_acceptors数组的长度创建对应数量的 Acceptor，而 Acceptor 的个数可以配置。

![[Pasted image 20230327155835.png]]

Acceptor 是 ServerConnector 中的一个内部类，同时也是一个 Runnable，Acceptor 线程是通过 getExecutor 得到的线程池来执行的，前面提到这是一个全局的线程池。

Acceptor 通过阻塞的方式来接受连接，这一点跟 Tomcat 也是一样的。

![[Pasted image 20230327155843.png]]

接受连接成功后会调用 accepted 函数，accepted 函数中会将 SocketChannel 设置为非阻塞模式，然后交给 Selector 去处理，因此这也就到了 Selector 的地界了。

![[Pasted image 20230327155850.png]]

### SelectorManager

Jetty 的 Selector 由 SelectorManager 类管理，而被管理的 Selector 叫作 ManagedSelector。SelectorManager 内部有一个 ManagedSelector 数组，真正干活的是 ManagedSelector。咱们接着上面分析，看看在 SelectorManager 在 accept 方法里做了什么。

![[Pasted image 20230327155902.png]]

SelectorManager 从本身的 Selector 数组中选择一个 Selector 来处理这个 Channel，并创建一个任务 Accept 交给 ManagedSelector，ManagedSelector 在处理这个任务主要做了两步：

第一步，调用 Selector 的 register 方法把 Channel 注册到 Selector 上，拿到一个 SelectionKey。

_key = _channel.register(selector, SelectionKey.OP_ACCEPT, this);

第二步，创建一个 EndPoint 和 Connection，并跟这个 SelectionKey（Channel）绑在一起：

![[Pasted image 20230327155911.png]]

上面这两个过程是什么意思呢？打个比方，你到餐厅吃饭，先点菜（注册 I/O 事件），服务员（ManagedSelector）给你一个单子（SelectionKey），等菜做好了（I/O 事件到了），服务员根据单子就知道是哪桌点了这个菜，于是喊一嗓子某某桌的菜做好了（调用了绑定在 SelectionKey 上的 EndPoint 的方法）。

这里需要你特别注意的是，ManagedSelector 并没有调用直接 EndPoint 的方法去处理数据，而是通过调用 EndPoint 的方法返回一个 Runnable，然后把这个 Runnable 扔给线程池执行，所以你能猜到，这个 Runnable 才会去真正读数据和处理请求。

### Connection

这个 Runnable 是 EndPoint 的一个内部类，它会调用 Connection 的回调方法来处理请求。Jetty 的 Connection 组件类比就是 Tomcat 的 Processor，负责具体协议的解析，得到 Request 对象，并调用 Handler 容器进行处理。下面我简单介绍一下它的具体实现类 HttpConnection 对请求和响应的处理过程。

请求处理：HttpConnection 并不会主动向 EndPoint 读取数据，而是向在 EndPoint 中注册一堆回调方法：
```java
getEndPoint().fillInterested(_readCallback);
```
这段代码就是告诉 EndPoint，数据到了你就调我这些回调方法_readCallback吧，有点异步 I/O 的感觉，也就是说 Jetty 在应用层面模拟了异步 I/O 模型。

而在回调方法_readCallback里，会调用 EndPoint 的接口去读数据，读完后让 HTTP 解析器去解析字节流，HTTP 解析器会将解析后的数据，包括请求行、请求头相关信息存到 Request 对象里。

响应处理：Connection 调用 Handler 进行业务处理，Handler 会通过 Response 对象来操作响应流，向流里面写入数据，HttpConnection 再通过 EndPoint 把数据写到 Channel，这样一次响应就完成了。

到此你应该了解了 Connector 的工作原理，下面我画张图再来回顾一下 Connector 的工作流程。

![[Pasted image 20230327155932.png]]

1.Acceptor 监听连接请求，当有连接请求到达时就接受连接，一个连接对应一个 Channel，Acceptor 将 Channel 交给 ManagedSelector 来处理。

2.ManagedSelector 把 Channel 注册到 Selector 上，并创建一个 EndPoint 和 Connection 跟这个 Channel 绑定，接着就不断地检测 I/O 事件。

3.I/O 事件到了就调用 EndPoint 的方法拿到一个 Runnable，并扔给线程池执行。

4. 线程池中调度某个线程执行 Runnable。

5.Runnable 执行时，调用回调函数，这个回调函数是 Connection 注册到 EndPoint 中的。

6. 回调函数内部实现，其实就是调用 EndPoint 的接口方法来读数据。

7.Connection 解析读到的数据，生成请求对象并交给 Handler 组件去处理。

Jetty Server 就是由多个 Connector、多个 Handler，以及一个线程池组成，在设计上简洁明了。

Jetty 的 Connector 只支持 NIO 模型，跟 Tomcat 的 NioEndpoint 组件一样，它也是通过 Java 的 NIO API 实现的。我们知道，Java NIO 编程有三个关键组件：Channel、Buffer 和 Selector，而核心是 Selector。为了方便使用，Jetty 在原生 Selector 组件的基础上做了一些封装，实现了 ManagedSelector 组件。

在线程模型设计上 Tomcat 的 NioEndpoint 跟 Jetty 的 Connector 是相似的，都是用一个 Acceptor 数组监听连接，用一个 Selector 数组侦测 I/O 事件，用一个线程池执行请求。它们的不同点在于，Jetty 使用了一个全局的线程池，所有的线程资源都是从线程池来分配。

Jetty Connector 设计中的一大特点是，使用了回调函数来模拟异步 I/O，比如 Connection 向 EndPoint 注册了一堆回调函数。它的本质将函数当作一个参数来传递，告诉对方，你准备好了就调这个回调函数。

# 总体架构-handler

Jetty 就是由多个 Connector（连接器）、多个 Handler（处理器），以及一个线程池组成，整体结构图如下。

![[Pasted image 20230327160116.png]]

上一期我们分析了 Jetty Connector 组件的设计，Connector 会将 Servlet 请求交给 Handler 去处理，那 Handler 又是如何处理请求的呢？

Jetty 的 Handler 在设计上非常有意思，可以说是 Jetty 的灵魂，Jetty 通过 Handler 实现了高度可定制化，那具体是如何实现的呢？我们能从中学到怎样的设计方法呢？接下来，我就来聊聊这些问题。

## Handler 是什么

Handler 就是一个接口，它有一堆实现类，Jetty 的 Connector 组件调用这些接口来处理 Servlet 请求，我们先来看看这个接口定义成什么样子。

![[Pasted image 20230327160127.png]]

你会看到 Handler 接口的定义非常简洁，主要就是用 handle 方法用来处理请求，跟 Tomcat 容器组件的 service 方法一样，它有 ServletRequest 和 ServletResponse 两个参数。除此之外，这个接口中还有 setServer 和 getServer 方法，因为任何一个 Handler 都需要关联一个 Server 组件，也就是说 Handler 需要被 Server 组件来管理。一般来说 Handler 会加载一些资源到内存，因此通过设置 destroy 方法来销毁。

### Handler 继承关系

Handler 只是一个接口，完成具体功能的还是它的子类。那么 Handler 有哪些子类呢？它们的继承关系又是怎样的？这些子类是如何实现 Servlet 容器功能的呢？

Jetty 中定义了一些默认 Handler 类，并且这些 Handler 类之间的继承关系比较复杂，我们先通过一个全景图来了解一下。为了避免让你感到不适，我对类图进行了简化。

![[Pasted image 20230327160135.png]]

从图上你可以看到，Handler 的种类和层次关系还是比较复杂的：

Handler 接口之下有抽象类 AbstractHandler，这一点并不意外，因为有接口一般就有抽象实现类。

在 AbstractHandler 之下有 AbstractHandlerContainer，为什么需要这个类呢？这其实是个过渡，为了实现链式调用，一个 Handler 内部必然要有其他 Handler 的引用，所以这个类的名字里才有 Container，意思就是这样的 Handler 里包含了其他 Handler 的引用。

理解了上面的 AbstractHandlerContainer，我们就能理解它的两个子类了：HandlerWrapper 和 HandlerCollection。简单来说就是，HandlerWrapper 和 HandlerCollection 都是 Handler，但是这些 Handler 里还包括其他 Handler 的引用。不同的是，HandlerWrapper 只包含一个其他 Handler 的引用，而 HandlerCollection 中有一个 Handler 数组的引用。

![[Pasted image 20230327160144.png]]

接着来看左边的 HandlerWrapper，它有两个子类：Server 和 ScopedHandler。Server 比较好理解，它本身是 Handler 模块的入口，必然要将请求传递给其他 Handler 来处理，为了触发其他 Handler 的调用，所以它是一个 HandlerWrapper。

再看 ScopedHandler，它也是一个比较重要的 Handler，实现了“具有上下文信息”的责任链调用。为什么我要强调“具有上下文信息”呢？那是因为 Servlet 规范规定 Servlet 在执行过程中是有上下文的。那么这些 Handler 在执行过程中如何访问这个上下文呢？这个上下文又存在什么地方呢？答案就是通过 ScopedHandler 来实现的。

而 ScopedHandler 有一堆的子类，这些子类就是用来实现 Servlet 规范的，比如 ServletHandler、ContextHandler、SessionHandler、ServletContextHandler 和 WebAppContext。接下来我会详细介绍它们，但我们先把总体类图看完。

请看类图的右边，跟 HandlerWrapper 对等的还有 HandlerCollection，HandlerCollection 其实维护了一个 Handler 数组。你可能会问，为什么要发明一个这样的 Handler？这是因为 Jetty 可能需要同时支持多个 Web 应用，如果每个 Web 应用有一个 Handler 入口，那么多个 Web 应用的 Handler 就成了一个数组，比如 Server 中就有一个 HandlerCollection，Server 会根据用户请求的 URL 从数组中选取相应的 Handler 来处理，就是选择特定的 Web 应用来处理请求。

### Handler 的类型

虽然从类图上看 Handler 有很多，但是本质上这些 Handler 分成三种类型：

第一种是协调 Handler，这种 Handler 负责将请求路由到一组 Handler 中去，比如上图中的 HandlerCollection，它内部持有一个 Handler 数组，当请求到来时，它负责将请求转发到数组中的某一个 Handler。

第二种是过滤器 Handler，这种 Handler 自己会处理请求，处理完了后再把请求转发到下一个 Handler，比如图上的 HandlerWrapper，它内部持有下一个 Handler 的引用。需要注意的是，所有继承了 HandlerWrapper 的 Handler 都具有了过滤器 Handler 的特征，比如 ContextHandler、SessionHandler 和 WebAppContext 等。

第三种是内容 Handler，说白了就是这些 Handler 会真正调用 Servlet 来处理请求，生成响应的内容，比如 ServletHandler。如果浏览器请求的是一个静态资源，也有相应的 ResourceHandler 来处理这个请求，返回静态页面。

## 如何实现 Servlet 规范

上文提到，ServletHandler、ContextHandler 以及 WebAppContext 等，它们实现了 Servlet 规范，那具体是怎么实现的呢？为了帮助你理解，在这之前，我们还是来看看如何使用 Jetty 来启动一个 Web 应用。

![[Pasted image 20230327160154.png]]

上面的过程主要分为两步：

第一步创建一个 WebAppContext，接着设置一些参数到这个 Handler 中，就是告诉 WebAppContext 你的 WAR 包放在哪，Web 应用的访问路径是什么。

第二步就是把新创建的 WebAppContext 添加到 Server 中，然后启动 Server。

WebAppContext 对应一个 Web 应用。我们回忆一下 Servlet 规范中有 Context、Servlet、Filter、Listener 和 Session 等，Jetty 要支持 Servlet 规范，就需要有相应的 Handler 来分别实现这些功能。因此，Jetty 设计了 3 个组件：ContextHandler、ServletHandler 和 SessionHandler 来实现 Servlet 规范中规定的功能，而 WebAppContext 本身就是一个 ContextHandler，另外它还负责管理 ServletHandler 和 SessionHandler。

我们再来看一下什么是 ContextHandler。ContextHandler 会创建并初始化 Servlet 规范里的 ServletContext 对象，同时 ContextHandler 还包含了一组能够让你的 Web 应用运行起来的 Handler，可以这样理解，Context 本身也是一种 Handler，它里面包含了其他的 Handler，这些 Handler 能处理某个特定 URL 下的请求。比如，ContextHandler 包含了一个或者多个 ServletHandler。

再来看 ServletHandler，它实现了 Servlet 规范中的 Servlet、Filter 和 Listener 的功能。ServletHandler 依赖 FilterHolder、ServletHolder、ServletMapping、FilterMapping 这四大组件。FilterHolder 和 ServletHolder 分别是 Filter 和 Servlet 的包装类，每一个 Servlet 与路径的映射会被封装成 ServletMapping，而 Filter 与拦截 URL 的映射会被封装成 FilterMapping。

SessionHandler 从名字就知道它的功能，用来管理 Session。除此之外 WebAppContext 还有一些通用功能的 Handler，比如 SecurityHandler 和 GzipHandler，同样从名字可以知道这些 Handler 的功能分别是安全控制和压缩 / 解压缩。

WebAppContext 会将这些 Handler 构建成一个执行链，通过这个链会最终调用到我们的业务 Servlet。我们通过一张图来理解一下。

![[Pasted image 20230327160205.png]]

通过对比 Tomcat 的架构图，你可以看到，Jetty 的 Handler 组件和 Tomcat 中的容器组件是大致是对等的概念，Jetty 中的 WebAppContext 相当于 Tomcat 的 Context 组件，都是对应一个 Web 应用；而 Jetty 中的 ServletHandler 对应 Tomcat 中的 Wrapper 组件，它负责初始化和调用 Servlet，并实现了 Filter 的功能。

对于一些通用组件，比如安全和解压缩，在 Jetty 中都被做成了 Handler，这是 Jetty Handler 架构的特点。

因此对于 Jetty 来说，请求处理模块就被抽象成 Handler，不管是实现了 Servlet 规范的 Handler，还是实现通用功能的 Handler，比如安全、解压缩等，我们可以任意添加或者裁剪这些“功能模块”，从而实现高度的可定制化。

Jetty Server 就是由多个 Connector、多个 Handler，以及一个线程池组成。

Jetty 的 Handler 设计是它的一大特色，Jetty 本质就是一个 Handler 管理器，Jetty 本身就提供了一些默认 Handler 来实现 Servlet 容器的功能，你也可以定义自己的 Handler 来添加到 Jetty 中，这体现了“微内核 + 插件”的设计思想。