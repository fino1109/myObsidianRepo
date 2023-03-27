# 组件设计规范

在当今的互联网时代，我们每个人获取信息的机会基本上都是平等的，但是为什么有些人对信息理解得更深，并且有自己独到的见解呢？我认为是因为他们养成了思考和总结的好习惯。当我们学习一门技术的时候，如果可以勤于思考、善于总结，可以帮助我们看到现象背后更本质的东西，让我们在成长之路上更快“脱颖而出”。

我们经常谈敏捷、快速迭代和重构，这些都是为了应对需求的快速变化，也因此我们在开始设计一个系统时就要考虑可扩展性。那究竟该怎样设计才能适应变化呢？或者要设计成什么样后面才能以最小的成本进行重构呢？今天我来总结一些 Tomcat 和 Jetty 组件化的设计思想，或许从中我们可以得到一些启发。

## 组件化及可配置

Tomcat 和 Jetty 的整体架构都是基于组件的，你可以通过 XML 文件或者代码的方式来配置这些组件，比如我们可以在 server.xml 配置 Tomcat 的连接器以及容器组件。相应的，你也可以在 jetty.xml 文件里组装 Jetty 的 Connector 组件，以及各种 Handler 组件。也就是说，Tomcat 和 Jetty 提供了一堆积木，怎么搭建这些积木由你来决定，你可以根据自己的需要灵活选择组件来搭建你的 Web 容器，并且也可以自定义组件，这样的设计为 Web 容器提供了深度可定制化。

那 Web 容器如何实现这种组件化设计呢？我认为有两个要点：

第一个是面向接口编程。我们需要对系统的功能按照“高内聚、低耦合”的原则进行拆分，每个组件都有相应的接口，组件之间通过接口通信，这样就可以方便地替换组件了。比如我们可以选择不同连接器类型，只要这些连接器组件实现同一个接口就行。

第二个是 Web 容器提供一个载体把组件组装在一起工作。组件的工作无非就是处理请求，因此容器通过责任链模式把请求依次交给组件去处理。对于用户来说，我只需要告诉 Web 容器由哪些组件来处理请求。把组件组织起来需要一个“管理者”，这就是为什么 Tomcat 和 Jetty 都有一个 Server 的概念，Server 就是组件的载体，Server 里包含了连接器组件和容器组件；容器还需要把请求交给各个子容器组件去处理，Tomcat 和 Jetty 都是责任链模式来实现的。

用户通过配置来组装组件，跟 Spring 中 Bean 的依赖注入相似。Spring 的用户可以通过配置文件或者注解的方式来组装 Bean，Bean 与 Bean 的依赖关系完全由用户自己来定义。这一点与 Web 容器不同，Web 容器中组件与组件之间的关系是固定的，比如 Tomcat 中 Engine 组件下有 Host 组件、Host 组件下有 Context 组件等，但你不能在 Host 组件里“注入”一个 Wrapper 组件，这是由于 Web 容器本身的功能来决定的。

## 组件的创建

由于组件是可以配置的，Web 容器在启动之前并不知道要创建哪些组件，也就是说，不能通过硬编码的方式来实例化这些组件，而是需要通过反射机制来动态地创建。具体来说，Web 容器不是通过 new 方法来实例化组件对象的，而是通过 Class.forName 来创建组件。无论哪种方式，在实例化一个类之前，Web 容器需要把组件类加载到 JVM，这就涉及一个类加载的问题，Web 容器设计了自己类加载器，我会在专栏后面的文章详细介绍 Tomcat 的类加载器。

Spring 也是通过反射机制来动态地实例化 Bean，那么它用到的类加载器是从哪里来的呢？Web 容器给每个 Web 应用创建了一个类加载器，Spring 用到的类加载器是 Web 容器传给它的。

## 组件的生命周期管理

不同类型的组件具有父子层次关系，父组件处理请求后再把请求传递给某个子组件。你可能会感到疑惑，Jetty 的中 Handler 不是一条链吗，看上去像是平行关系？其实不然，Jetty 中的 Handler 也是分层次的，比如 WebAppContext 中包含 ServletHandler 和 SessionHandler。因此你也可以把 ContextHandler 和它所包含的 Handler 看作是父子关系。

而 Tomcat 通过容器的概念，把小容器放到大容器来实现父子关系，其实它们的本质都是一样的。这其实涉及如何统一管理这些组件，如何做到一键式启停。

Tomcat 和 Jetty 都采用了类似的办法来管理组件的生命周期，主要有两个要点，一是父组件负责子组件的创建、启停和销毁。这样只要启动最上层组件，整个 Web 容器就被启动起来了，也就实现了一键式启停；二是 Tomcat 和 Jetty 都定义了组件的生命周期状态，并且把组件状态的转变定义成一个事件，一个组件的状态变化会触发子组件的变化，比如 Host 容器的启动事件里会触发 Web 应用的扫描和加载，最终会在 Host 容器下创建相应的 Context 容器，而 Context 组件的启动事件又会触发 Servlet 的扫描，进而创建 Wrapper 组件。那么如何实现这种联动呢？答案是观察者模式。具体来说就是创建监听器去监听容器的状态变化，在监听器的方法里去实现相应的动作，这些监听器其实是组件生命周期过程中的“扩展点”。

Spring 也采用了类似的设计，Spring 给 Bean 生命周期状态提供了很多的“扩展点”。这些扩展点被定义成一个个接口，只要你的 Bean 实现了这些接口，Spring 就会负责调用这些接口，这样做的目的就是，当 Bean 的创建、初始化和销毁这些控制权交给 Spring 后，Spring 让你有机会在 Bean 的整个生命周期中执行你的逻辑。下面我通过一张图帮你理解 Spring Bean 的生命周期过程：

![[Pasted image 20230327170610.png]]

## 组件的骨架抽象类和模板模式

具体到组件的设计的与实现，Tomcat 和 Jetty 都大量采用了骨架抽象类和模板模式。比如说 Tomcat 中 ProtocolHandler 接口，ProtocolHandler 有抽象基类 AbstractProtocol，它实现了协议处理层的骨架和通用逻辑，而具体协议也有抽象基类，比如 HttpProtocol 和 AjpProtocol。对于 Jetty 来说，Handler 接口之下有 AbstractHandler，Connector 接口之下有 AbstractConnector，这些抽象骨架类实现了一些通用逻辑，并且会定义一些抽象方法，这些抽象方法由子类实现，抽象骨架类调用抽象方法来实现骨架逻辑。

这是一个通用的设计规范，不管是 Web 容器还是 Spring，甚至 JDK 本身都到处使用这种设计，比如 Java 集合中的 AbstractSet、AbstractMap 等。 值得一提的是，从 Java 8 开始允许接口有 default 方法，这样我们可以把抽象骨架类的通用逻辑放到接口中去。

今天我总结了 Tomcat 和 Jetty 的组件化设计，我们可以通过搭积木的方式来定制化自己的 Web 容器。Web 容器为了支持这种组件化设计，遵循了一些规范，比如面向接口编程，用“管理者”去组装这些组件，用反射的方式动态的创建组件、统一管理组件的生命周期，并且给组件生命状态的变化提供了扩展点，组件的具体实现一般遵循骨架抽象类和模板模式。

通过今天的学习，你会发现 Tomcat 和 Jetty 有很多共同点，并且 Spring 框架的设计也有不少相似的的地方，这正好说明了 Web 开发中有一些本质的东西是相通的，只要你深入理解了一个技术，也就是在一个点上突破了深度，再扩展广度就不是难事。并且我建议在学习一门技术的时候，可以回想一下之前学过的东西，是不是有相似的地方，有什么不同的地方，通过对比理解它们的本质，这样我们才能真正掌握这些技术背后的精髓。

# 对象池技术

Java 对象，特别是一个比较大、比较复杂的 Java 对象，它们的创建、初始化和 GC 都需要耗费 CPU 和内存资源，为了减少这些开销，Tomcat 和 Jetty 都使用了对象池技术。所谓的对象池技术，就是说一个 Java 对象用完之后把它保存起来，之后再拿出来重复使用，省去了对象创建、初始化和 GC 的过程。对象池技术是典型的以空间换时间的思路。

由于维护对象池本身也需要资源的开销，不是所有场景都适合用对象池。如果你的 Java 对象数量很多并且存在的时间比较短，对象本身又比较大比较复杂，对象初始化的成本比较高，这样的场景就适合用对象池技术。比如 Tomcat 和 Jetty 处理 HTTP 请求的场景就符合这个特征，请求的数量很多，为了处理单个请求需要创建不少的复杂对象（比如 Tomcat 连接器中 SocketWrapper 和 SocketProcessor），而且一般来说请求处理的时间比较短，一旦请求处理完毕，这些对象就需要被销毁，因此这个场景适合对象池技术。

## Tomcat 的 SynchronizedStack

Tomcat 用 SynchronizedStack 类来实现对象池，下面我贴出它的关键代码来帮助你理解。

```java
public class SynchronizedStack<T> {
  private Object[] stack;
  public synchronized boolean push(T obj) {
    index++;
    if (index == size) {
      if (limit == -1 || size < limit) {
        expand();
      } else {
        index--;
        return false;
      }
    }
    stack[index] = obj;
    return true;
  }
  public synchronized T pop() {
    if (index == -1) {
      return null;
    }
    T result = (T) stack[index];
    stack[index--] = null;
    return result;
  }
  private void expand() {
    int newSize = size * 2;
    if (limit != -1 && newSize > limit) {
      newSize = limit;
    }
    Object[] newStack = new Object[newSize];
    System.arraycopy(stack, 0, newStack, 0, size);
    stack = newStack;
    size = newSize;
  }
}
```
这个代码逻辑比较清晰，主要是 SynchronizedStack 内部维护了一个对象数组，并且用数组来实现栈的接口：push 和 pop 方法，这两个方法分别用来归还对象和获取对象。你可能好奇为什么 Tomcat 使用一个看起来比较简单的 SynchronizedStack 来做对象容器，为什么不使用高级一点的并发容器比如 ConcurrentLinkedQueue 呢？

这是因为 SynchronizedStack 用数组而不是链表来维护对象，可以减少结点维护的内存开销，并且它本身只支持扩容不支持缩容，也就是说数组对象在使用过程中不会被重新赋值，也就不会被 GC。这样设计的目的是用最低的内存和 GC 的代价来实现无界容器，同时 Tomcat 的最大同时请求数是有限制的，因此不需要担心对象的数量会无限膨胀。

## Jetty 的 ByteBufferPool

我们再来看 Jetty 中的对象池 ByteBufferPool，它本质是一个 ByteBuffer 对象池。当 Jetty 在进行网络数据读写时，不需要每次都在 JVM 堆上分配一块新的 Buffer，只需在 ByteBuffer 对象池里拿到一块预先分配好的 Buffer，这样就避免了频繁的分配内存和释放内存。这种设计你同样可以在高性能通信中间件比如 Mina 和 Netty 中看到。ByteBufferPool 是一个接口：

```java
public interface ByteBufferPool {
  public ByteBuffer acquire(int size, boolean direct);
  public void release(ByteBuffer buffer);
}
```

接口中的两个方法：acquire 和 release 分别用来分配和释放内存，并且你可以通过 acquire 方法的 direct 参数来指定 buffer 是从 JVM 堆上分配还是从本地内存分配。ArrayByteBufferPool 是 ByteBufferPool 的实现类，我们先来看看它的成员变量和构造函数：

```java
public class ArrayByteBufferPool implements ByteBufferPool {
  private final int _min;
  private final int _maxQueue;
  private final ByteBufferPool.Bucket[] _direct;
  private final ByteBufferPool.Bucket[] _indirect;
  private final int _inc;
  public ArrayByteBufferPool(
      int minSize, int increment, int maxSize, int maxQueue) {
    if (minSize <= 0)
      minSize = 0;
    if (increment <= 0)
      increment = 1024;
    if (maxSize <= 0)
      maxSize = 64 * 1024;
    if (minSize >= increment)
      throw new IllegalArgumentException("minSize >= increment");
    if ((maxSize % increment) != 0 || increment >= maxSize)
      throw new IllegalArgumentException(
          "increment must be a divisor of maxSize");
    _min = minSize;
    _inc = increment;
    _direct = new ByteBufferPool.Bucket[maxSize / increment];
    _indirect = new ByteBufferPool.Bucket[maxSize / increment];
    _maxQueue = maxQueue;
    int size = 0;
    for (int i = 0; i < _direct.length; i++) {
      size += _inc;
      _direct[i] = new ByteBufferPool.Bucket(this, size, _maxQueue);
      _indirect[i] = new ByteBufferPool.Bucket(this, size, _maxQueue);
    }
  }
}
```

从上面的代码我们看到，ByteBufferPool 是用不同的桶（Bucket）来管理不同长度的 ByteBuffer，因为我们可能需要分配一块 1024 字节的 Buffer，也可能需要一块 64K 字节的 Buffer。而桶的内部用一个 ConcurrentLinkedDeque 来放置 ByteBuffer 对象的引用。

```java
private final Deque<ByteBuffer> _queue = new ConcurrentLinkedDeque<>();
```

你可以通过下面的图再来理解一下：

![[Pasted image 20230327172154.png]]

而 Buffer 的分配和释放过程，就是找到相应的桶，并对桶中的 Deque 做出队和入队的操作，而不是直接向 JVM 堆申请和释放内存。

```java
public ByteBuffer acquire(int size, boolean direct) {
  ByteBufferPool.Bucket bucket = bucketFor(size, direct);
  if (bucket == null)
    return newByteBuffer(size, direct);
  return bucket.acquire(direct);
}
public void release(ByteBuffer buffer) {
  if (buffer != null) {
    ByteBufferPool.Bucket bucket =
        bucketFor(buffer.capacity(), buffer.isDirect());
    if (bucket != null)
      bucket.release(buffer);
  }
}
```

## 对象池的思考

对象池作为全局资源，高并发环境中多个线程可能同时需要获取对象池中的对象，因此多个线程在争抢对象时会因为锁竞争而阻塞， 因此使用对象池有线程同步的开销，而不使用对象池则有创建和销毁对象的开销。对于对象池本身的设计来说，需要尽量做到无锁化，比如 Jetty 就使用了 ConcurrentLinkedDeque。如果你的内存足够大，可以考虑用线程本地（ThreadLocal）对象池，这样每个线程都有自己的对象池，线程之间互不干扰。

为了防止对象池的无限膨胀，必须要对池的大小做限制。对象池太小发挥不了作用，对象池太大的话可能有空闲对象，这些空闲对象会一直占用内存，造成内存浪费。这里你需要根据实际情况做一个平衡，因此对象池本身除了应该有自动扩容的功能，还需要考虑自动缩容。

所有的池化技术，包括缓存，都会面临内存泄露的问题，原因是对象池或者缓存的本质是一个 Java 集合类，比如 List 和 Stack，这个集合类持有缓存对象的引用，只要集合类不被 GC，缓存对象也不会被 GC。维持大量的对象也比较占用内存空间，所以必要时我们需要主动清理这些对象。以 Java 的线程池 ThreadPoolExecutor 为例，它提供了 allowCoreThreadTimeOut 和 setKeepAliveTime 两种方法，可以在超时后销毁线程，我们在实际项目中也可以参考这个策略。

另外在使用对象池时，我这里还有一些小贴士供你参考：

对象在用完后，需要调用对象池的方法将对象归还给对象池。

对象池中的对象在再次使用时需要重置，否则会产生脏对象，脏对象可能持有上次使用的引用，导致内存泄漏等问题，并且如果脏对象下一次使用时没有被清理，程序在运行过程中会发生意想不到的问题。

对象一旦归还给对象池，使用者就不能对它做任何操作了。

向对象池请求对象时有可能出现的阻塞、异常或者返回 null 值，这些都需要我们做一些额外的处理，来确保程序的正常运行。

Tomcat 和 Jetty 都用到了对象池技术，这是因为处理一次 HTTP 请求的时间比较短，但是这个过程中又需要创建大量复杂对象。

对象池技术可以减少频繁创建和销毁对象带来的成本，实现对象的缓存和复用。如果你的系统需要频繁的创建和销毁对象，并且对象的创建代价比较大，这种情况下，一般来说你会观察到 GC 的压力比较大，占用 CPU 率比较高，这个时候你就可以考虑使用对象池了。

还有一种情况是你需要对资源的使用做限制，比如数据库连接，不能无限制地创建数据库连接，因此就有了数据库连接池，你也可以考虑把一些关键的资源池化，对它们进行统一管理，防止滥用。

# 高性能、高并发之道

高性能程序就是高效的利用 CPU、内存、网络和磁盘等资源，在短时间内处理大量的请求。那如何衡量“短时间和大量”呢？其实就是两个关键指标：响应时间和每秒事务处理量（TPS）。

那什么是资源的高效利用呢？ 我觉得有两个原则：

减少资源浪费。比如尽量避免线程阻塞，因为一阻塞就会发生线程上下文切换，就需要耗费 CPU 资源；再比如网络通信时数据从内核空间拷贝到 Java 堆内存，需要通过本地内存中转。

当某种资源成为瓶颈时，用另一种资源来换取。比如缓存和对象池技术就是用内存换 CPU；数据压缩后再传输就是用 CPU 换网络。

Tomcat 和 Jetty 中用到了大量的高性能、高并发的设计，我总结了几点：I/O 和线程模型、减少系统调用、池化、零拷贝、高效的并发编程。下面我会详细介绍这些设计，希望你也可以将这些技术用到实际的工作中去。

## I/O 和线程模型

I/O 模型的本质就是为了缓解 CPU 和外设之间的速度差。当线程发起 I/O 请求时，比如读写网络数据，网卡数据还没准备好，这个线程就会被阻塞，让出 CPU，也就是说发生了线程切换。而线程切换是无用功，并且线程被阻塞后，它持有内存资源并没有释放，阻塞的线程越多，消耗的内存就越大，因此 I/O 模型的目标就是尽量减少线程阻塞。Tomcat 和 Jetty 都已经抛弃了传统的同步阻塞 I/O，采用了非阻塞 I/O 或者异步 I/O，目的是业务线程不需要阻塞在 I/O 等待上。

除了 I/O 模型，线程模型也是影响性能和并发的关键点。Tomcat 和 Jetty 的总体处理原则是：

连接请求由专门的 Acceptor 线程组处理。

I/O 事件侦测也由专门的 Selector 线程组来处理。

具体的协议解析和业务处理可能交给线程池（Tomcat），或者交给 Selector 线程来处理（Jetty）。

将这些事情分开的好处是解耦，并且可以根据实际情况合理设置各部分的线程数。这里请你注意，线程数并不是越多越好，因为 CPU 核的个数有限，线程太多也处理不过来，会导致大量的线程上下文切换。

## 减少系统调用

其实系统调用是非常耗资源的一个过程，涉及 CPU 从用户态切换到内核态的过程，因此我们在编写程序的时候要有意识尽量避免系统调用。比如在 Tomcat 和 Jetty 中，系统调用最多的就是网络通信操作了，一个 Channel 上的 write 就是系统调用，为了降低系统调用的次数，最直接的方法就是使用缓冲，当输出数据达到一定的大小才 flush 缓冲区。Tomcat 和 Jetty 的 Channel 都带有输入输出缓冲区。

还有值得一提的是，Tomcat 和 Jetty 在解析 HTTP 协议数据时， 都采取了延迟解析的策略，HTTP 的请求体（HTTP Body）直到用的时候才解析。也就是说，当 Tomcat 调用 Servlet 的 service 方法时，只是读取了和解析了 HTTP 请求头，并没有读取 HTTP 请求体。

直到你的 Web 应用程序调用了 ServletRequest 对象的 getInputStream 方法或者 getParameter 方法时，Tomcat 才会去读取和解析 HTTP 请求体中的数据；这意味着如果你的应用程序没有调用上面那两个方法，HTTP 请求体的数据就不会被读取和解析，这样就省掉了一次 I/O 系统调用。

## 池化、零拷贝

关于池化和零拷贝，我在专栏前面已经详细讲了它们的原理，你可以回过头看看专栏第 20 期和第 16 期。其实池化的本质就是用内存换 CPU；而零拷贝就是不做无用功，减少资源浪费。

## 高效的并发编程

我们知道并发的过程中为了同步多个线程对共享变量的访问，需要加锁来实现。而锁的开销是比较大的，拿锁的过程本身就是个系统调用，如果锁没拿到线程会阻塞，又会发生线程上下文切换，尤其是大量线程同时竞争一把锁时，会浪费大量的系统资源。因此作为程序员，要有意识的尽量避免锁的使用，比如可以使用原子类 CAS 或者并发集合来代替。如果万不得已需要用到锁，也要尽量缩小锁的范围和锁的强度。接下来我们来看看 Tomcat 和 Jetty 如何做到高效的并发编程的。

### 缩小锁的范围

缩小锁的范围，其实就是不直接在方法上加 synchronized，而是使用细粒度的对象锁。


```java
protected void startInternal() throws LifecycleException {
  setState(LifecycleState.STARTING);
  if (engine != null) {
    synchronized (engine) {
      engine.start();
    }
  }
  synchronized (executors) {
    for (Executor executor : executors) {
      executor.start();
    }
  }
  mapperListener.start();
  synchronized (connectorsLock) {
    for (Connector connector : connectors) {
      if (connector.getState() != LifecycleState.FAILED) {
        connector.start();
      }
    }
  }
}
```

比如上面的代码是 Tomcat 的 StandardService 组件的启动方法，这个启动方法要启动三种子组件：Engine、Executors 和 Connectors。它没有直接在方法上加锁，而是用了三把细粒度的锁，来分别用来锁三个成员变量。如果直接在方法上加 synchronized，多个线程执行到这个方法时需要排队；而在对象级别上加 synchronized，多个线程可以并行执行这个方法，只是在访问某个成员变量时才需要排队。

### 用原子变量和 CAS 取代锁

下面的代码是 Jetty 线程池的启动方法，它的主要功能就是根据传入的参数启动相应个数的线程。

```java
private boolean startThreads(int threadsToStart) {
  while (threadsToStart > 0 && isRunning()) {
    int threads = _threadsStarted.get();
    if (threads >= _maxThreads)
      return false;
    if (!_threadsStarted.compareAndSet(threads, threads + 1))
      continue;
    boolean started = false;
    try {
      Thread thread = newThread(_runnable);
      thread.setDaemon(isDaemon());
      thread.setPriority(getThreadsPriority());
      thread.setName(_name + "-" + thread.getId());
      _threads.add(thread);
      _lastShrink.set(System.nanoTime());
      thread.start();
      started = true;
      --threadsToStart;
    } finally {
      if (!started)
        _threadsStarted.decrementAndGet();
    }
  }
  return true;
}
```

你可以看到整个函数的实现是一个 while 循环，并且是无锁的。_threadsStarted表示当前线程池已经启动了多少个线程，它是一个原子变量 AtomicInteger，首先通过它的 get 方法拿到值，如果线程数已经达到最大值，直接返回。否则尝试用 CAS 操作将_threadsStarted的值加一，如果成功了意味着没有其他线程在改这个值，当前线程可以继续往下执行；否则走 continue 分支，也就是继续重试，直到成功为止。在这里当然你也可以使用锁来实现，但是我们的目的是无锁化。

### 并发容器的使用

CopyOnWriteArrayList 适用于读多写少的场景，比如 Tomcat 用它来“存放”事件监听器，这是因为监听器一般在初始化过程中确定后就基本不会改变，当事件触发时需要遍历这个监听器列表，所以这个场景符合读多写少的特征。

```java
public abstract class LifecycleBase implements Lifecycle {
  private final List<LifecycleListener> lifecycleListeners =
      new CopyOnWriteArrayList<>();
  ...
}
```

### volatile 关键字的使用

再拿 Tomcat 中的 LifecycleBase 作为例子，它里面的生命状态就是用 volatile 关键字修饰的。volatile 的目的是为了保证一个线程修改了变量，另一个线程能够读到这种变化。对于生命状态来说，需要在各个线程中保持是最新的值，因此采用了 volatile 修饰。

```java
public abstract class LifecycleBase implements Lifecycle {
  private volatile LifecycleState state = LifecycleState.NEW;
}
```

高性能程序能够高效的利用系统资源，首先就是减少资源浪费，比如要减少线程的阻塞，因为阻塞会导致资源闲置和线程上下文切换，Tomcat 和 Jetty 通过合理的 I/O 模型和线程模型减少了线程的阻塞。

另外系统调用会导致用户态和内核态切换的过程，Tomcat 和 Jetty 通过缓存和延迟解析尽量减少系统调用，另外还通过零拷贝技术避免多余的数据拷贝。

高效的利用资源还包括另一层含义，那就是我们在系统设计的过程中，经常会用一种资源换取另一种资源，比如 Tomcat 和 Jetty 中使用的对象池技术，就是用内存换取 CPU，将数据压缩后再传输就是用 CPU 换网络。

除此之外，高效的并发编程也很重要，多线程虽然可以提高并发度，也带来了锁的开销，因此我们在实际编程过程中要尽量避免使用锁，比如可以用原子变量和 CAS 操作来代替锁。如果实在避免不了用锁，也要尽量少锁的范围和强度，比如可以用细粒度的对象锁或者低强度的读写锁。Tomcat 和 Jetty 的代码也很好的实践了这一理念。

# 异同

概括一下 Tomcat 和 Jetty 两者最大的区别。大体来说，Tomcat 的核心竞争力是成熟稳定，因为它经过了多年的市场考验，应用也相当广泛，对于比较复杂的企业级应用支持得更加全面。也因为如此，Tomcat 在整体结构上比 Jetty 更加复杂，功能扩展方面可能不如 Jetty 那么方便。

而 Jetty 比较年轻，设计上更加简洁小巧，配置也比较简单，功能也支持方便地扩展和裁剪，比如我们可以把 Jetty 的 SessionHandler 去掉，以节省内存资源，因此 Jetty 还可以运行在小型的嵌入式设备中，比如手机和机顶盒。当然，我们也可以自己开发一个 Handler，加入 Handler 链中用来扩展 Jetty 的功能。值得一提的是，Hadoop 和 Solr 都嵌入了 Jetty 作为 Web 服务器。

从设计的角度来看，Tomcat 的架构基于一种多级容器的模式，这些容器组件具有父子关系，所有组件依附于这个骨架，而且这个骨架是不变的，我们在扩展 Tomcat 的功能时也需要基于这个骨架，因此 Tomcat 在设计上相对来说比较复杂。当然 Tomcat 也提供了较好的扩展机制，比如我们可以自定义一个 Valve，但相对来说学习成本还是比较大的。而 Jetty 采用 Handler 责任链模式。由于 Handler 之间的关系比较松散，Jetty 提供 HandlerCollection 可以帮助开发者方便地构建一个 Handler 链，同时也提供了 ScopeHandler 帮助开发者控制 Handler 链的访问顺序。关于这部分内容，你可以回忆一下专栏里讲的回溯方式的责任链模式。

Jetty 在吞吐量和响应速度方面稍有优势，并且 Jetty 消耗的线程和内存资源明显比 Tomcat 要少，这也恰好说明了 Jetty 在设计上更加小巧和轻量级的特点。

但是 Jetty 有 2.45% 的错误率，而 Tomcat 没有任何错误，并且我经过多次测试都是这个结果。因此我们可以认为 Tomcat 比 Jetty 更加成熟和稳定。

当然由于测试场景的限制，以上数据并不能完全反映 Tomcat 和 Jetty 的真实能力。但是它可以在我们做选型的时候提供一些参考：如果系统的目标是资源消耗尽量少，并且对稳定性要求没有那么高，可以选择轻量级的 Jetty；如果你的系统是比较关键的企业级应用，建议还是选择 Tomcat 比较稳妥。

最后用一句话总结 Tomcat 和 Jetty 的区别：Tomcat 好比是一位工作多年比较成熟的工程师，轻易不会出错、不会掉链子，但是他有自己的想法，不会轻易做出改变。而 Jetty 更像是一位年轻的后起之秀，脑子转得很快，可塑性也很强，但有时候也会犯一点小错误。