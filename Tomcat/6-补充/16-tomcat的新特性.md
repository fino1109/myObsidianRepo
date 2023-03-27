# 支持WebSocket

我们知道 HTTP 协议是“请求 - 响应”模式，浏览器必须先发请求给服务器，服务器才会响应这个请求。也就是说，服务器不会主动发送数据给浏览器。

对于实时性要求比较的高的应用，比如在线游戏、股票基金实时报价和在线协同编辑等，浏览器需要实时显示服务器上最新的数据，因此出现了 Ajax 和 Comet 技术。Ajax 本质上还是轮询，而 Comet 是在 HTTP 长连接的基础上做了一些 hack，但是它们的实时性不高，另外频繁的请求会给服务器带来压力，也会浪费网络流量和带宽。于是 HTML5 推出了 WebSocket 标准，使得浏览器和服务器之间任何一方都可以主动发消息给对方，这样服务器有新数据时可以主动推送给浏览器。

今天我会介绍 WebSocket 的工作原理，以及作为服务器端的 Tomcat 是如何支持 WebSocket 的。更重要的是，希望你在学完之后可以灵活地选用 WebSocket 技术来解决实际工作中的问题。

## WebSocket 工作原理

WebSocket 的名字里带有 Socket，那 Socket 是什么呢？网络上的两个程序通过一个双向链路进行通信，这个双向链路的一端称为一个 Socket。一个 Socket 对应一个 IP 地址和端口号，应用程序通常通过 Socket 向网络发出请求或者应答网络请求。Socket 不是协议，它其实是对 TCP/IP 协议层抽象出来的 API。

但 WebSocket 不是一套 API，跟 HTTP 协议一样，WebSocket 也是一个应用层协议。为了跟现有的 HTTP 协议保持兼容，它通过 HTTP 协议进行一次握手，握手之后数据就直接从 TCP 层的 Socket 传输，就与 HTTP 协议无关了。浏览器发给服务端的请求会带上跟 WebSocket 有关的请求头，比如Connection: Upgrade和Upgrade: websocket。

![[Pasted image 20230327163611.png]]

如果服务器支持 WebSocket，同样会在 HTTP 响应里加上 WebSocket 相关的 HTTP 头部。

![[Pasted image 20230327163617.png]]

这样 WebSocket 连接就建立好了，接下来 WebSocket 的数据传输会以 frame 形式传输，会将一条消息分为几个 frame，按照先后顺序传输出去。这样做的好处有：

大数据的传输可以分片传输，不用考虑数据大小的问题。

和 HTTP 的 chunk 一样，可以边生成数据边传输，提高传输效率。

## Tomcat 如何支持 WebSocket

在讲 Tomcat 如何支持 WebSocket 之前，我们先来开发一个简单的聊天室程序，需求是：用户可以通过浏览器加入聊天室、发送消息，聊天室的其他人都可以收到消息。

WebSocket 聊天室程序

浏览器端 JavaScript 核心代码如下：

```javascript
var Chat = {};
Chat.socket = null;
Chat.connect = (function(host) {
    if ('WebSocket' in window) {
        Chat.socket = new WebSocket(host)
    } else if ('MozWebSocket' in window) {
        Chat.socket = new MozWebSocket(host)
    } else {
        Console.log('WebSocket is not supported by this browser.');
        return
    }
    Chat.socket.onopen = function() {
        Console.log('Info: WebSocket connection opened.');
        document.getElementById('chat').onkeydown = function(event) {
            if (event.keyCode == 13) {
                Chat.sendMessage()
            }
        }
    };
    Chat.socket.onclose = function() {
        document.getElementById('chat').onkeydown = null;
        Console.log('Info: WebSocket closed.')
    };
    Chat.socket.onmessage = function(message) {
        Console.log(message.data)
    }
});
```

上面的代码实现逻辑比较清晰，就是创建一个 WebSocket JavaScript 对象，然后实现了几个回调方法：onopen、onclose 和 onmessage。当连接建立、关闭和有新消息时，浏览器会负责调用这些回调方法。我们再来看服务器端 Tomcat 的实现代码：

```java
@ServerEndpoint(value = "/websocket/chat")
public class ChatEndpoint {
    private static final String GUEST_PREFIX = "Guest";
    private static final AtomicInteger connectionIds = new AtomicInteger(0);
    private static final Set<ChatEndpoint> connections =
        new CopyOnWriteArraySet<>();
    private final String nickname;
    private Session session;
    public ChatEndpoint() {
        nickname = GUEST_PREFIX + connectionIds.getAndIncrement();
    }
    @OnOpen
    public void start(Session session) {
        this.session = session;
        connections.add(this);
        String message = String.format("* %s %s", nickname, "has joined.");
        broadcast(message);
    }
    @OnClose
    public void end() {
        connections.remove(this);
        String message =
            String.format("* %s %s", nickname, "has disconnected.");
        broadcast(message);
    }
    @OnMessage
    public void incoming(String message) {
        String filteredMessage = String.format(
            "%s: %s", nickname, HTMLFilter.filter(message.toString()));
        broadcast(filteredMessage);
    }
    @OnError
    public void onError(Throwable t) throws Throwable {
        log.error("Chat Error: " + t.toString(), t);
    }
    private static void broadcast(String msg) {
        for (ChatAnnotation client : connections) {
            try {
                synchronized (client) {
                    client.session.getBasicRemote().sendText(msg);
                }
            } catch (IOException e) {
                ...
            }
        }
    }
}
```

根据 Java WebSocket 规范的规定，Java WebSocket 应用程序由一系列的 WebSocket Endpoint 组成。Endpoint 是一个 Java 对象，代表 WebSocket 连接的一端，就好像处理 HTTP 请求的 Servlet 一样，你可以把它看作是处理 WebSocket 消息的接口。跟 Servlet 不同的地方在于，Tomcat 会给每一个 WebSocket 连接创建一个 Endpoint 实例。你可以通过两种方式定义和实现 Endpoint。

第一种方法是编程式的，就是编写一个 Java 类继承javax.websocket.Endpoint，并实现它的 onOpen、onClose 和 onError 方法。这些方法跟 Endpoint 的生命周期有关，Tomcat 负责管理 Endpoint 的生命周期并调用这些方法。并且当浏览器连接到一个 Endpoint 时，Tomcat 会给这个连接创建一个唯一的 Session（javax.websocket.Session）。Session 在 WebSocket 连接握手成功之后创建，并在连接关闭时销毁。当触发 Endpoint 各个生命周期事件时，Tomcat 会将当前 Session 作为参数传给 Endpoint 的回调方法，因此一个 Endpoint 实例对应一个 Session，我们通过在 Session 中添加 MessageHandler 消息处理器来接收消息，MessageHandler 中定义了 onMessage 方法。在这里 Session 的本质是对 Socket 的封装，Endpoint 通过它与浏览器通信。

第二种定义 Endpoint 的方法是注解式的，也就是上面的聊天室程序例子中用到的方式，即实现一个业务类并给它添加 WebSocket 相关的注解。首先我们注意到@ServerEndpoint(value = "/websocket/chat")注解，它表明当前业务类 ChatEndpoint 是一个实现了 WebSocket 规范的 Endpoint，并且注解的 value 值表明 ChatEndpoint 映射的 URL 是/websocket/chat。我们还看到 ChatEndpoint 类中有@OnOpen、@OnClose、@OnError和在@OnMessage注解的方法，从名字你就知道它们的功能是什么。

对于程序员来说，其实我们只需要专注具体的 Endpoint 的实现，比如在上面聊天室的例子中，为了方便向所有人群发消息，ChatEndpoint 在内部使用了一个全局静态的集合 CopyOnWriteArraySet 来维护所有的 ChatEndpoint 实例，因为每一个 ChatEndpoint 实例对应一个 WebSocket 连接，也就是代表了一个加入聊天室的用户。当某个 ChatEndpoint 实例收到来自浏览器的消息时，这个 ChatEndpoint 会向集合中其他 ChatEndpoint 实例背后的 WebSocket 连接推送消息。

那么这个过程中，Tomcat 主要做了哪些事情呢？简单来说就是两件事情：Endpoint 加载和 WebSocket 请求处理。下面我分别来详细说说 Tomcat 是如何做这两件事情的。

WebSocket 加载

Tomcat 的 WebSocket 加载是通过 SCI 机制完成的。SCI 全称 ServletContainerInitializer，是 Servlet 3.0 规范中定义的用来接收 Web 应用启动事件的接口。那为什么要监听 Servlet 容器的启动事件呢？因为这样我们有机会在 Web 应用启动时做一些初始化工作，比如 WebSocket 需要扫描和加载 Endpoint 类。SCI 的使用也比较简单，将实现 ServletContainerInitializer 接口的类增加 HandlesTypes 注解，并且在注解内指定的一系列类和接口集合。比如 Tomcat 为了扫描和加载 Endpoint 而定义的 SCI 类如下：

```java
@HandlesTypes({ServerEndpoint.class, ServerApplicationConfig.class, Endpoint.class})
public class WsSci implements ServletContainerInitializer {
  public void onStartup(Set<Class<?>> clazzes, ServletContext ctx)  throws ServletException {
    ...
  }
}
```

一旦定义好了 SCI，Tomcat 在启动阶段扫描类时，会将 HandlesTypes 注解中指定的类都扫描出来，作为 SCI 的 onStartup 方法的参数，并调用 SCI 的 onStartup 方法。注意到 WsSci 的 HandlesTypes 注解中定义了ServerEndpoint.class、ServerApplicationConfig.class和Endpoint.class，因此在 Tomcat 的启动阶段会将这些类的类实例（注意不是对象实例）传递给 WsSci 的 onStartup 方法。那么 WsSci 的 onStartup 方法又做了什么事呢？

它会构造一个 WebSocketContainer 实例，你可以把 WebSocketContainer 理解成一个专门处理 WebSocket 请求的 Endpoint 容器。也就是说 Tomcat 会把扫描到的 Endpoint 子类和添加了注解@ServerEndpoint的类注册到这个容器中，并且这个容器还维护了 URL 到 Endpoint 的映射关系，这样通过请求 URL 就能找到具体的 Endpoint 来处理 WebSocket 请求。

WebSocket 请求处理

在讲 WebSocket 请求处理之前，我们先来回顾一下 Tomcat 连接器的组件图。

![[Pasted image 20230327164135.png]]

你可以看到 Tomcat 用 ProtocolHandler 组件屏蔽应用层协议的差异，其中 ProtocolHandler 中有两个关键组件：Endpoint 和 Processor。需要注意，这里的 Endpoint 跟上文提到的 WebSocket 中的 Endpoint 完全是两回事，连接器中的 Endpoint 组件用来处理 I/O 通信。WebSocket 本质就是一个应用层协议，因此不能用 HttpProcessor 来处理 WebSocket 请求，而要用专门 Processor 来处理，而在 Tomcat 中这样的 Processor 叫作 UpgradeProcessor。

为什么叫 UpgradeProcessor 呢？这是因为 Tomcat 是将 HTTP 协议升级成 WebSocket 协议的，我们知道 WebSocket 是通过 HTTP 协议来进行握手的，因此当 WebSocket 的握手请求到来时，HttpProtocolHandler 首先接收到这个请求，在处理这个 HTTP 请求时，Tomcat 通过一个特殊的 Filter 判断该当前 HTTP 请求是否是一个 WebSocket Upgrade 请求（即包含Upgrade: websocket的 HTTP 头信息），如果是，则在 HTTP 响应里添加 WebSocket 相关的响应头信息，并进行协议升级。具体来说就是用 UpgradeProtocolHandler 替换当前的 HttpProtocolHandler，相应的，把当前 Socket 的 Processor 替换成 UpgradeProcessor，同时 Tomcat 会创建 WebSocket Session 实例和 Endpoint 实例，并跟当前的 WebSocket 连接一一对应起来。这个 WebSocket 连接不会立即关闭，并且在请求处理中，不再使用原有的 HttpProcessor，而是用专门的 UpgradeProcessor，UpgradeProcessor 最终会调用相应的 Endpoint 实例来处理请求。下面我们通过一张图来理解一下。

![[Pasted image 20230327164143.png]]

你可以看到，Tomcat 对 WebSocket 请求的处理没有经过 Servlet 容器，而是通过 UpgradeProcessor 组件直接把请求发到 ServerEndpoint 实例，并且 Tomcat 的 WebSocket 实现不需要关注具体 I/O 模型的细节，从而实现了与具体 I/O 方式的解耦。

WebSocket 技术实现了 Tomcat 与浏览器的双向通信，Tomcat 可以主动向浏览器推送数据，可以用来实现对数据实时性要求比较高的应用。这需要浏览器和 Web 服务器同时支持 WebSocket 标准，Tomcat 启动时通过 SCI 技术来扫描和加载 WebSocket 的处理类 ServerEndpoint，并且建立起了 URL 到 ServerEndpoint 的映射关系。

当第一个 WebSocket 请求到达时，Tomcat 将 HTTP 协议升级成 WebSocket 协议，并将该 Socket 连接的 Processor 替换成 UpgradeProcessor。这个 Socket 不会立即关闭，对接下来的请求，Tomcat 通过 UpgradeProcessor 直接调用相应的 ServerEndpoint 来处理。

今天我讲了可以通过两种方式来开发 WebSocket 应用，一种是继承javax.websocket.Endpoint，另一种通过 WebSocket 相关的注解。其实你还可以通过 Spring 来实现 WebSocket 应用，有兴趣的话你可以去研究一下 Spring WebSocket 的原理。

# 支持异步Servlet

当一个新的请求到达时，Tomcat 和 Jetty 会从线程池里拿出一个线程来处理请求，这个线程会调用你的 Web 应用，Web 应用在处理请求的过程中，Tomcat 线程会一直阻塞，直到 Web 应用处理完毕才能再输出响应，最后 Tomcat 才回收这个线程。

我们来思考这样一个问题，假如你的 Web 应用需要较长的时间来处理请求（比如数据库查询或者等待下游的服务调用返回），那么 Tomcat 线程一直不回收，会占用系统资源，在极端情况下会导致“线程饥饿”，也就是说 Tomcat 和 Jetty 没有更多的线程来处理新的请求。

那该如何解决这个问题呢？方案是 Servlet 3.0 中引入的异步 Servlet。主要是在 Web 应用里启动一个单独的线程来执行这些比较耗时的请求，而 Tomcat 线程立即返回，不再等待 Web 应用将请求处理完，这样 Tomcat 线程可以立即被回收到线程池，用来响应其他请求，降低了系统的资源消耗，同时还能提高系统的吞吐量。

今天我们就来学习一下如何开发一个异步 Servlet，以及异步 Servlet 的工作原理，也就是 Tomcat 是如何支持异步 Servlet 的，让你彻底理解它的来龙去脉。

## 异步 Servlet 示例

我们先通过一个简单的示例来了解一下异步 Servlet 的实现。

```java
@WebServlet(urlPatterns = {"/async"}, asyncSupported = true)
public class AsyncServlet extends HttpServlet {
  ExecutorService executor = Executors.newSingleThreadExecutor();
  public void service(HttpServletRequest req, HttpServletResponse resp) {
    final AsyncContext ctx = req.startAsync();
    executor.execute(new Runnable() {
      @Override
      public void run() {
        try {
          ctx.getResponse().getWriter().println("Handling Async Servlet");
        } catch (IOException e) {
        }
        ctx.complete();
      }
    });
  }
}
```

上面的代码有三个要点：

- 通过注解的方式来注册 Servlet，除了 @WebServlet 注解，还需要加上asyncSupported=true的属性，表明当前的 Servlet 是一个异步 Servlet。

- Web 应用程序需要调用 Request 对象的 startAsync 方法来拿到一个异步上下文 AsyncContext。这个上下文保存了请求和响应对象。

- Web 应用需要开启一个新线程来处理耗时的操作，处理完成后需要调用 AsyncContext 的 complete 方法。目的是告诉 Tomcat，请求已经处理完成。

这里请你注意，虽然异步 Servlet 允许用更长的时间来处理请求，但是也有超时限制的，默认是 30 秒，如果 30 秒内请求还没处理完，Tomcat 会触发超时机制，向浏览器返回超时错误，如果这个时候你的 Web 应用再调用ctx.complete方法，会得到一个 IllegalStateException 异常。

## 异步 Servlet 原理

通过上面的例子，相信你对 Servlet 的异步实现有了基本的理解。要理解 Tomcat 在这个过程都做了什么事情，关键就是要弄清楚req.startAsync方法和ctx.complete方法都做了什么。

### startAsync 方法

startAsync 方法其实就是创建了一个异步上下文 AsyncContext 对象，AsyncContext 对象的作用是保存请求的中间信息，比如 Request 和 Response 对象等上下文信息。你来思考一下为什么需要保存这些信息呢？

这是因为 Tomcat 的工作线程在request.startAsync调用之后，就直接结束回到线程池中了，线程本身不会保存任何信息。也就是说一个请求到服务端，执行到一半，你的 Web 应用正在处理，这个时候 Tomcat 的工作线程没了，这就需要有个缓存能够保存原始的 Request 和 Response 对象，而这个缓存就是 AsyncContext。

有了 AsyncContext，你的 Web 应用通过它拿到 Request 和 Response 对象，拿到 Request 对象后就可以读取请求信息，请求处理完了还需要通过 Response 对象将 HTTP 响应发送给浏览器。

除了创建 AsyncContext 对象，startAsync 还需要完成一个关键任务，那就是告诉 Tomcat 当前的 Servlet 处理方法返回时，不要把响应发到浏览器，因为这个时候，响应还没生成呢；并且不能把 Request 对象和 Response 对象销毁，因为后面 Web 应用还要用呢。

在 Tomcat 中，负责 flush 响应数据的是 CoyoteAdapter，它还会销毁 Request 对象和 Response 对象，因此需要通过某种机制通知 CoyoteAdapter，具体来说是通过下面这行代码：
```java
this.request.getCoyoteRequest().action(ActionCode.ASYNC_START, this);
```
你可以把它理解为一个 Callback，在这个 action 方法里设置了 Request 对象的状态，设置它为一个异步 Servlet 请求。

我们知道连接器是调用 CoyoteAdapter 的 service 方法来处理请求的，而 CoyoteAdapter 会调用容器的 service 方法，当容器的 service 方法返回时，CoyoteAdapter 判断当前的请求是不是异步 Servlet 请求，如果是，就不会销毁 Request 和 Response 对象，也不会把响应信息发到浏览器。你可以通过下面的代码理解一下，这是 CoyoteAdapter 的 service 方法，我对它进行了简化：

```java
public void service(
    org.apache.coyote.Request req, org.apache.coyote.Response res) {
  connector.getService().getContainer().getPipeline().getFirst().invoke(
      request, response);
  if (request.isAsync()) {
    async = true;
  } else {
    request.finishRequest();
    response.finishResponse();
  }
  if (!async) {
    request.recycle();
    response.recycle();
  }
}
```

接下来，当 CoyoteAdapter 的 service 方法返回到 ProtocolHandler 组件时，ProtocolHandler 判断返回值，如果当前请求是一个异步 Servlet 请求，它会把当前 Socket 的协议处理者 Processor 缓存起来，将 SocketWrapper 对象和相应的 Processor 存到一个 Map 数据结构里。

```java
private final Map<S,Processor> connections = new ConcurrentHashMap<>();
```

之所以要缓存是因为这个请求接下来还要接着处理，还是由原来的 Processor 来处理，通过 SocketWrapper 就能从 Map 里找到相应的 Processor。

### complete 方法

接着我们再来看关键的ctx.complete方法，当请求处理完成时，Web 应用调用这个方法。那么这个方法做了些什么事情呢？最重要的就是把响应数据发送到浏览器。

这件事情不能由 Web 应用线程来做，也就是说ctx.complete方法不能直接把响应数据发送到浏览器，因为这件事情应该由 Tomcat 线程来做，但具体怎么做呢？

我们知道，连接器中的 Endpoint 组件检测到有请求数据达到时，会创建一个 SocketProcessor 对象交给线程池去处理，因此 Endpoint 的通信处理和具体请求处理在两个线程里运行。

在异步 Servlet 的场景里，Web 应用通过调用ctx.complete方法时，也可以生成一个新的 SocketProcessor 任务类，交给线程池处理。对于异步 Servlet 请求来说，相应的 Socket 和协议处理组件 Processor 都被缓存起来了，并且这些对象都可以通过 Request 对象拿到。

讲到这里，你可能已经猜到ctx.complete是如何实现的了：

```java
public void complete() {
  check();
  request.getCoyoteRequest().action(ActionCode.ASYNC_COMPLETE, null);
}
```

我们可以看到 complete 方法调用了 Request 对象的 action 方法。而在 action 方法里，则是调用了 Processor 的 processSocketEvent 方法，并且传入了操作码 OPEN_READ。

```java
case ASYNC_COMPLETE: {
  clearDispatches();
  if (asyncStateMachine.asyncComplete()) {
    processSocketEvent(SocketEvent.OPEN_READ, true);
  }
  break;
}
```

我们接着看 processSocketEvent 方法，它调用 SocketWrapper 的 processSocket 方法：

```java
protected void processSocketEvent(SocketEvent event, boolean dispatch) {
  SocketWrapperBase < ? &gt;
  socketWrapper = getSocketWrapper();
  if (socketWrapper != null) {
    socketWrapper.processSocket(event, dispatch);
  }
}
```

而 SocketWrapper 的 processSocket 方法会创建 SocketProcessor 任务类，并通过 Tomcat 线程池来处理：

```java
public boolean processSocket(
    SocketWrapperBase<S> socketWrapper, SocketEvent event, boolean dispatch) {
  if (socketWrapper == null) {
    return false;
  }
  SocketProcessorBase<S> sc = processorCache.pop();
  if (sc == null) {
    sc = createSocketProcessor(socketWrapper, event);
  } else {
    sc.reset(socketWrapper, event);
  }
  Executor executor = getExecutor();
  if (dispatch && executor != null) {
    executor.execute(sc);
  } else {
    sc.run();
  }
}
```

请你注意 createSocketProcessor 函数的第二个参数是 SocketEvent，这里我们传入的是 OPEN_READ。通过这个参数，我们就能控制 SocketProcessor 的行为，因为我们不需要再把请求发送到容器进行处理，只需要向浏览器端发送数据，并且重新在这个 Socket 上监听新的请求就行了。

最后我通过一张在帮你理解一下整个过程：

![[Pasted image 20230327164745.png]]

非阻塞 I/O 模型可以利用很少的线程处理大量的连接，提高了并发度，本质就是通过一个 Selector 线程查询多个 Socket 的 I/O 事件，减少了线程的阻塞等待。

同样，异步 Servlet 机制也是减少了线程的阻塞等待，将 Tomcat 线程和业务线程分开，Tomcat 线程不再等待业务代码的执行。

那什么样的场景适合异步 Servlet 呢？适合的场景有很多，最主要的还是根据你的实际情况，如果你拿不准是否适合异步 Servlet，就看一条：如果你发现 Tomcat 的线程不够了，大量线程阻塞在等待 Web 应用的处理上，而 Web 应用又没有优化的空间了，确实需要长时间处理，这个时候你不妨尝试一下异步

# Spring Boot使用内嵌式的Tomcat和Jetty

为了方便开发和部署，Spring Boot 在内部启动了一个嵌入式的 Web 容器。我们知道 Tomcat 和 Jetty 是组件化的设计，要启动 Tomcat 或者 Jetty 其实就是启动这些组件。在 Tomcat 独立部署的模式下，我们通过 startup 脚本来启动 Tomcat，Tomcat 中的 Bootstrap 和 Catalina 会负责初始化类加载器，并解析server.xml和启动这些组件。

在内嵌式的模式下，Bootstrap 和 Catalina 的工作就由 Spring Boot 来做了，Spring Boot 调用了 Tomcat 和 Jetty 的 API 来启动这些组件。那 Spring Boot 具体是怎么做的呢？而作为程序员，我们如何向 Spring Boot 中的 Tomcat 注册 Servlet 或者 Filter 呢？我们又如何定制内嵌式的 Tomcat？今天我们就来聊聊这些话题。

## Spring Boot 中 Web 容器相关的接口

既然要支持多种 Web 容器，Spring Boot 对内嵌式 Web 容器进行了抽象，定义了 WebServer 接口：

```java
public interface WebServer {
  void start() throws WebServerException;
  void stop() throws WebServerException;
  int getPort();
}
```

各种 Web 容器比如 Tomcat 和 Jetty 需要去实现这个接口。

Spring Boot 还定义了一个工厂 ServletWebServerFactory 来创建 Web 容器，返回的对象就是上面提到的 WebServer。

```java
public interface ServletWebServerFactory {
  WebServer getWebServer(ServletContextInitializer... initializers);
}
```

可以看到 getWebServer 有个参数，类型是 ServletContextInitializer。它表示 ServletContext 的初始化器，用于 ServletContext 中的一些配置：

```java
public interface ServletContextInitializer {
  void onStartup(ServletContext servletContext) throws ServletException;
}
```

这里请注意，上面提到的 getWebServer 方法会调用 ServletContextInitializer 的 onStartup 方法，也就是说如果你想在 Servlet 容器启动时做一些事情，比如注册你自己的 Servlet，可以实现一个 ServletContextInitializer，在 Web 容器启动时，Spring Boot 会把所有实现了 ServletContextInitializer 接口的类收集起来，统一调它们的 onStartup 方法。

为了支持对内嵌式 Web 容器的定制化，Spring Boot 还定义了 WebServerFactoryCustomizerBeanPostProcessor 接口，它是一个 BeanPostProcessor，它在 postProcessBeforeInitialization 过程中去寻找 Spring 容器中 WebServerFactoryCustomizer 类型的 Bean，并依次调用 WebServerFactoryCustomizer 接口的 customize 方法做一些定制化。

```java
public interface WebServerFactoryCustomizer<T extends WebServerFactory> {
  void customize(T factory);
}
```

## 内嵌式 Web 容器的创建和启动

铺垫了这些接口，我们再来看看 Spring Boot 是如何实例化和启动一个 Web 容器的。我们知道，Spring 的核心是一个 ApplicationContext，它的抽象实现类 AbstractApplicationContext 实现了著名的 refresh 方法，它用来新建或者刷新一个 ApplicationContext，在 refresh 方法中会调用 onRefresh 方法，AbstractApplicationContext 的子类可以重写这个 onRefresh 方法，来实现特定 Context 的刷新逻辑，因此 ServletWebServerApplicationContext 就是通过重写 onRefresh 方法来创建内嵌式的 Web 容器，具体创建过程是这样的：

```java
@Override
protected void onRefresh() {
  super.onRefresh();
  try {
    createWebServer();
  } catch (Throwable ex) {
  }
}
private void createWebServer() {
  WebServer webServer = this.webServer;
  ServletContext servletContext = this.getServletContext();
  if (webServer == null && servletContext == null) {
    ServletWebServerFactory factory = this.getWebServerFactory();
    this.webServer = factory.getWebServer(
        new ServletContextInitializer[] {this.getSelfInitializer()});
  } else if (servletContext != null) {
    try {
      this.getSelfInitializer().onStartup(servletContext);
    } catch (ServletException var4) {
      ...
    }
  }
  this.initPropertySources();
}
```

再来看看 getWebServer 具体做了什么，以 Tomcat 为例，主要调用 Tomcat 的 API 去创建各种组件：

```java
public WebServer getWebServer(ServletContextInitializer... initializers) {
  Tomcat tomcat = new Tomcat();
  File baseDir = this.baseDirectory != null ? this.baseDirectory
                                            : this.createTempDir("tomcat");
  tomcat.setBaseDir(baseDir.getAbsolutePath());
  Connector connector = new Connector(this.protocol);
  tomcat.getService().addConnector(connector);
  this.customizeConnector(connector);
  tomcat.setConnector(connector);
  tomcat.getHost().setAutoDeploy(false);
  this.configureEngine(tomcat.getEngine());
  this.prepareContext(tomcat.getHost(), initializers);
  return this.getTomcatWebServer(tomcat);
}
```

你可能好奇 prepareContext 方法是做什么的呢？这里的 Context 是指 Tomcat 中的 Context 组件，为了方便控制 Context 组件的行为，Spring Boot 定义了自己的 TomcatEmbeddedContext，它扩展了 Tomcat 的 StandardContext：

```java
class TomcatEmbeddedContext extends StandardContext{}
```

## 注册 Servlet 的三种方式

### 1. Servlet 注解

在 Spring Boot 启动类上加上 @ServletComponentScan 注解后，使用 @WebServlet、@WebFilter、@WebListener 标记的 Servlet、Filter、Listener 就可以自动注册到 Servlet 容器中，无需其他代码，我们通过下面的代码示例来理解一下。

```java
@SpringBootApplication
@ServletComponentScan
public class xxxApplication {}
@WebServlet("/hello")
public class HelloServlet extends HttpServlet {}
```

在 Web 应用的入口类上加上 @ServletComponentScan，并且在 Servlet 类上加上 @WebServlet，这样 Spring Boot 会负责将 Servlet 注册到内嵌的 Tomcat 中。

### 2. ServletRegistrationBean

同时 Spring Boot 也提供了 ServletRegistrationBean、FilterRegistrationBean 和 ServletListenerRegistrationBean 这三个类分别用来注册 Servlet、Filter、Listener。假如要注册一个 Servlet，可以这样做：

```java
@Bean
public ServletRegistrationBean servletRegistrationBean() {
  return new ServletRegistrationBean(new HelloServlet(), "/hello");
}
```

这段代码实现的方法返回一个 ServletRegistrationBean，并将它当作 Bean 注册到 Spring 中，因此你需要把这段代码放到 Spring Boot 自动扫描的目录中，或者放到 @Configuration 标识的类中。

### 3. 动态注册

你还可以创建一个类去实现前面提到的 ServletContextInitializer 接口，并把它注册为一个 Bean，Spring Boot 会负责调用这个接口的 onStartup 方法。

```java
@Component
public class MyServletRegister implements ServletContextInitializer {
  @Override
  public void onStartup(ServletContext servletContext) {
    ServletRegistration myServlet =
        servletContext.addServlet("HelloServlet", HelloServlet.class);
    myServlet.addMapping("/hello");
    myServlet.setInitParameter("name", "Hello Servlet");
  }
}
```

这里请注意两点：

ServletRegistrationBean 其实也是通过 ServletContextInitializer 来实现的，它实现了 ServletContextInitializer 接口。

注意到 onStartup 方法的参数是我们熟悉的 ServletContext，可以通过调用它的 addServlet 方法来动态注册新的 Servlet，这是 Servlet 3.0 以后才有的功能。

## Web 容器的定制

我们再来考虑一个问题，那就是如何在 Spring Boot 中定制 Web 容器。在 Spring Boot 2.0 中，我们可以通过两种方式来定制 Web 容器。

第一种方式是通过通用的 Web 容器工厂 ConfigurableServletWebServerFactory，来定制一些 Web 容器通用的参数：

```java
@Component
public class MyGeneralCustomizer
    implements WebServerFactoryCustomizer<ConfigurableServletWebServerFactory> {
  public void customize(ConfigurableServletWebServerFactory factory) {
    factory.setPort(8081);
    factory.setContextPath("/hello");
  }
}
```

第二种方式是通过特定 Web 容器的工厂比如 TomcatServletWebServerFactory 来进一步定制。下面的例子里，我们给 Tomcat 增加一个 Valve，这个 Valve 的功能是向请求头里添加 traceid，用于分布式追踪。TraceValve 的定义如下：

```java
class TraceValve extends ValveBase {
  @Override
  public void invoke(Request request, Response response)
      throws IOException, ServletException {
    request.getCoyoteRequest().getMimeHeaders().addValue("traceid").setString(
        "1234xxxxabcd");
    Valve next = getNext();
    if (null == next) {
      return;
    }
    next.invoke(request, response);
  }
}
```

跟第一种方式类似，再添加一个定制器，代码如下：

```java
@Component
public class MyTomcatCustomizer
    implements WebServerFactoryCustomizer<TomcatServletWebServerFactory> {
  @Override
  public void customize(TomcatServletWebServerFactory factory) {
    factory.setPort(8081);
    factory.setContextPath("/hello");
    factory.addEngineValves(new TraceValve());
  }
}
```