# 打破双亲委托机制

相信我们平时在工作中都遇到过 ClassNotFound 异常，这个异常表示 JVM 在尝试加载某个类的时候失败了。想要解决这个问题，首先你需要知道什么是类加载，JVM 是如何加载类的，以及为什么会出现 ClassNotFound 异常？弄懂上面这些问题之后，我们接着要思考 Tomcat 作为 Web 容器，它是如何加载和管理 Web 应用下的 Servlet 呢？

Tomcat 正是通过 Context 组件来加载管理 Web 应用的，所以今天我会详细分析 Tomcat 的类加载机制。但在这之前，我们有必要预习一下 JVM 的类加载机制，我会先回答一下一开始抛出来的问题，接着再谈谈 Tomcat 的类加载器如何打破 Java 的双亲委托机制。

## JVM 的类加载器

Java 的类加载，就是把字节码格式“.class”文件加载到 JVM 的方法区，并在 JVM 的堆区建立一个java.lang.Class对象的实例，用来封装 Java 类相关的数据和方法。那 Class 对象又是什么呢？你可以把它理解成业务类的模板，JVM 根据这个模板来创建具体业务类对象实例。

JVM 并不是在启动时就把所有的“.class”文件都加载一遍，而是程序在运行过程中用到了这个类才去加载。JVM 类加载是由类加载器来完成的，JDK 提供一个抽象类 ClassLoader，这个抽象类中定义了三个关键方法，理解清楚它们的作用和关系非常重要。

```java

public abstract class ClassLoader {

    //每个类加载器都有个父加载器
    private final ClassLoader parent;
    
    public Class<?> loadClass(String name) {
  
        //查找一下这个类是不是已经加载过了
        Class<?> c = findLoadedClass(name);
        
        //如果没有加载过
        if( c == null ){
          //先委托给父加载器去加载，注意这是个递归调用
          if (parent != null) {
              c = parent.loadClass(name);
          }else {
              // 如果父加载器为空，查找Bootstrap加载器是不是加载过了
              c = findBootstrapClassOrNull(name);
          }
        }
        // 如果父加载器没加载成功，调用自己的findClass去加载
        if (c == null) {
            c = findClass(name);
        }
        
        return c；
    }
    
    protected Class<?> findClass(String name){
       //1. 根据传入的类名name，到在特定目录下去寻找类文件，把.class文件读入内存
          ...
          
       //2. 调用defineClass将字节数组转成Class对象
       return defineClass(buf, off, len)；
    }
    
    // 将字节码数组解析成一个Class对象，用native方法实现
    protected final Class<?> defineClass(byte[] b, int off, int len){
       ...
    }
}
```

从上面的代码我们可以得到几个关键信息：

- JVM 的类加载器是分层次的，它们有父子关系，每个类加载器都持有一个 parent 字段，指向父加载器。
- defineClass 是个工具方法，它的职责是调用 native 方法把 Java 类的字节码解析成一个 Class 对象，所谓的 native 方法就是由 C 语言实现的方法，Java 通过 JNI 机制调用。
- findClass 方法的主要职责就是找到“.class”文件，可能来自文件系统或者网络，找到后把“.class”文件读到内存得到字节码数组，然后调用 defineClass 方法得到 Class 对象。
- loadClass 是个 public 方法，说明它才是对外提供服务的接口，具体实现也比较清晰：首先检查这个类是不是已经被加载过了，如果加载过了直接返回，否则交给父加载器去加载。请你注意，这是一个递归调用，也就是说子加载器持有父加载器的引用，当一个类加载器需要加载一个 Java 类时，会先委托父加载器去加载，然后父加载器在自己的加载路径中搜索 Java 类，当父加载器在自己的加载范围内找不到时，才会交还给子加载器加载，这就是双亲委托机制。

JDK 中有哪些默认的类加载器？它们的本质区别是什么？为什么需要双亲委托机制？JDK 中有 3 个类加载器，另外你也可以自定义类加载器，它们的关系如下图所示。

![[Pasted image 20230323143911.png]]

- BootstrapClassLoader 是启动类加载器，由 C 语言实现，用来加载 JVM 启动时所需要的核心类，比如rt.jar、resources.jar等。

- ExtClassLoader 是扩展类加载器，用来加载\jre\lib\ext目录下 JAR 包。

- AppClassLoader 是系统类加载器，用来加载 classpath 下的类，应用程序默认用它来加载类。

- 自定义类加载器，用来加载自定义路径下的类。

这些类加载器的工作原理是一样的，区别是它们的加载路径不同，也就是说 findClass 这个方法查找的路径不同。双亲委托机制是为了保证一个 Java 类在 JVM 中是唯一的，假如你不小心写了一个与 JRE 核心类同名的类，比如 Object 类，双亲委托机制能保证加载的是 JRE 里的那个 Object 类，而不是你写的 Object 类。这是因为 AppClassLoader 在加载你的 Object 类时，会委托给 ExtClassLoader 去加载，而 ExtClassLoader 又会委托给 BootstrapClassLoader，BootstrapClassLoader 发现自己已经加载过了 Object 类，会直接返回，不会去加载你写的 Object 类。

这里请你注意，类加载器的父子关系不是通过继承来实现的，比如 AppClassLoader 并不是 ExtClassLoader 的子类，而是说 AppClassLoader 的 parent 成员变量指向 ExtClassLoader 对象。同样的道理，如果你要自定义类加载器，不去继承 AppClassLoader，而是继承 ClassLoader 抽象类，再重写 findClass 和 loadClass 方法即可，Tomcat 就是通过自定义类加载器来实现自己的类加载逻辑。不知道你发现没有，如果你要打破双亲委托机制，就需要重写 loadClass 方法，因为 loadClass 的默认实现就是双亲委托机制。

## Tomcat 的类加载器

Tomcat 的自定义类加载器 WebAppClassLoader 打破了双亲委托机制，它首先自己尝试去加载某个类，如果找不到再代理给父类加载器，其目的是优先加载 Web 应用自己定义的类。具体实现就是重写 ClassLoader 的两个方法：findClass 和 loadClass。

### findClass 方法

我们先来看看 findClass 方法的实现，为了方便理解和阅读，我去掉了一些细节：

```java

public Class<?> findClass(String name) throws ClassNotFoundException {
    ...
    
    Class<?> clazz = null;
    try {
            //1. 先在Web应用目录下查找类 
            clazz = findClassInternal(name);
    }  catch (RuntimeException e) {
           throw e;
       }
    
    if (clazz == null) {
    try {
            //2. 如果在本地目录没有找到，交给父加载器去查找
            clazz = super.findClass(name);
    }  catch (RuntimeException e) {
           throw e;
       }
    
    //3. 如果父类也没找到，抛出ClassNotFoundException
    if (clazz == null) {
        throw new ClassNotFoundException(name);
     }

    return clazz;
}
```

在 findClass 方法里，主要有三个步骤：

- 先在 Web 应用本地目录下查找要加载的类。

- 如果没有找到，交给父加载器去查找，它的父加载器就是上面提到的系统类加载器 AppClassLoader。

- 如何父加载器也没找到这个类，抛出 ClassNotFound 异常。

### loadClass 方法

接着我们再来看 Tomcat 类加载器的 loadClass 方法的实现，同样我也去掉了一些细节：

```java

public Class<?> loadClass(String name, boolean resolve) throws ClassNotFoundException {

    synchronized (getClassLoadingLock(name)) {
 
        Class<?> clazz = null;

        //1. 先在本地cache查找该类是否已经加载过
        clazz = findLoadedClass0(name);
        if (clazz != null) {
            if (resolve)
                resolveClass(clazz);
            return clazz;
        }

        //2. 从系统类加载器的cache中查找是否加载过
        clazz = findLoadedClass(name);
        if (clazz != null) {
            if (resolve)
                resolveClass(clazz);
            return clazz;
        }

        // 3. 尝试用ExtClassLoader类加载器类加载，为什么？
        ClassLoader javaseLoader = getJavaseClassLoader();
        try {
            clazz = javaseLoader.loadClass(name);
            if (clazz != null) {
                if (resolve)
                    resolveClass(clazz);
                return clazz;
            }
        } catch (ClassNotFoundException e) {
            // Ignore
        }

        // 4. 尝试在本地目录搜索class并加载
        try {
            clazz = findClass(name);
            if (clazz != null) {
                if (resolve)
                    resolveClass(clazz);
                return clazz;
            }
        } catch (ClassNotFoundException e) {
            // Ignore
        }

        // 5. 尝试用系统类加载器(也就是AppClassLoader)来加载
            try {
                clazz = Class.forName(name, false, parent);
                if (clazz != null) {
                    if (resolve)
                        resolveClass(clazz);
                    return clazz;
                }
            } catch (ClassNotFoundException e) {
                // Ignore
            }
       }
    
    //6. 上述过程都加载失败，抛出异常
    throw new ClassNotFoundException(name);
}
```

loadClass 方法稍微复杂一点，主要有六个步骤：

- 先在本地 Cache 查找该类是否已经加载过，也就是说 Tomcat 的类加载器是否已经加载过这个类。

- 如果 Tomcat 类加载器没有加载过这个类，再看看系统类加载器是否加载过。

- 如果都没有，就让 ExtClassLoader 去加载，这一步比较关键，目的防止 Web 应用自己的类覆盖 JRE 的核心类。因为 Tomcat 需要打破双亲委托机制，假如 Web 应用里自定义了一个叫 Object 的类，如果先加载这个 Object 类，就会覆盖 JRE 里面的那个 Object 类，这就是为什么 Tomcat 的类加载器会优先尝试用 ExtClassLoader 去加载，因为 ExtClassLoader 会委托给 BootstrapClassLoader 去加载，BootstrapClassLoader 发现自己已经加载了 Object 类，直接返回给 Tomcat 的类加载器，这样 Tomcat 的类加载器就不会去加载 Web 应用下的 Object 类了，也就避免了覆盖 JRE 核心类的问题。

- 如果 ExtClassLoader 加载器加载失败，也就是说 JRE 核心类中没有这类，那么就在本地 Web 应用目录下查找并加载。

- 如果本地目录下没有这个类，说明不是 Web 应用自己定义的类，那么由系统类加载器去加载。这里请你注意，Web 应用是通过Class.forName调用交给系统类加载器的，因为Class.forName的默认加载器就是系统类加载器。

- 如果上述加载过程全部失败，抛出 ClassNotFound 异常。

从上面的过程我们可以看到，Tomcat 的类加载器打破了双亲委托机制，没有一上来就直接委托给父加载器，而是先在本地目录下加载，为了避免本地目录下的类覆盖 JRE 的核心类，先尝试用 JVM 扩展类加载器 ExtClassLoader 去加载。那为什么不先用系统类加载器 AppClassLoader 去加载？很显然，如果是这样的话，那就变成双亲委托机制了，这就是 Tomcat 类加载器的巧妙之处。

今天我介绍了 JVM 的类加载器原理和源码剖析，以及 Tomcat 的类加载器是如何打破双亲委托机制的，目的是为了优先加载 Web 应用目录下的类，然后再加载其他目录下的类，这也是 Servlet 规范的推荐做法。

要打破双亲委托机制，需要继承 ClassLoader 抽象类，并且需要重写它的 loadClass 方法，因为 ClassLoader 的默认实现就是双亲委托。

# 隔离web应用

我在专栏上一期提到，Tomcat 通过自定义类加载器 WebAppClassLoader 打破了双亲委托机制，具体来说就是重写了 JVM 的类加载器 ClassLoader 的 findClass 方法和 loadClass 方法，这样做的目的是优先加载 Web 应用目录下的类。除此之外，你觉得 Tomcat 的类加载器还需要完成哪些需求呢？或者说在设计上还需要考虑哪些方面？

我们知道，Tomcat 作为 Servlet 容器，它负责加载我们的 Servlet 类，此外它还负责加载 Servlet 所依赖的 JAR 包。并且 Tomcat 本身也是一个 Java 程序，因此它需要加载自己的类和依赖的 JAR 包。首先让我们思考这一下这几个问题：

- 假如我们在 Tomcat 中运行了两个 Web 应用程序，两个 Web 应用中有同名的 Servlet，但是功能不同，Tomcat 需要同时加载和管理这两个同名的 Servlet 类，保证它们不会冲突，因此 Web 应用之间的类需要隔离。

- 假如两个 Web 应用都依赖同一个第三方的 JAR 包，比如 Spring，那 Spring 的 JAR 包被加载到内存后，Tomcat 要保证这两个 Web 应用能够共享，也就是说 Spring 的 JAR 包只被加载一次，否则随着依赖的第三方 JAR 包增多，JVM 的内存会膨胀。

- 跟 JVM 一样，我们需要隔离 Tomcat 本身的类和 Web 应用的类。

在了解了 Tomcat 的类加载器在设计时要考虑的这些问题以后，今天我们主要来学习一下 Tomcat 是如何通过设计多层次的类加载器来解决这些问题的。

## Tomcat 类加载器的层次结构

为了解决这些问题，Tomcat 设计了类加载器的层次结构，它们的关系如下图所示。下面我来详细解释为什么要设计这些类加载器，告诉你它们是怎么解决上面这些问题的。

![[Pasted image 20230323144527.png]]

我们先来看第 1 个问题，假如我们使用 JVM 默认 AppClassLoader 来加载 Web 应用，AppClassLoader 只能加载一个 Servlet 类，在加载第二个同名 Servlet 类时，AppClassLoader 会返回第一个 Servlet 类的 Class 实例，这是因为在 AppClassLoader 看来，同名的 Servlet 类只被加载一次。

因此 Tomcat 的解决方案是自定义一个类加载器 WebAppClassLoader， 并且给每个 Web 应用创建一个类加载器实例。我们知道，Context 容器组件对应一个 Web 应用，因此，每个 Context 容器负责创建和维护一个 WebAppClassLoader 加载器实例。这背后的原理是，不同的加载器实例加载的类被认为是不同的类，即使它们的类名相同。这就相当于在 Java 虚拟机内部创建了一个个相互隔离的 Java 类空间，每一个 Web 应用都有自己的类空间，Web 应用之间通过各自的类加载器互相隔离。

SharedClassLoader

我们再来看第 2 个问题，本质需求是两个 Web 应用之间怎么共享库类，并且不能重复加载相同的类。我们知道，在双亲委托机制里，各个子加载器都可以通过父加载器去加载类，那么把需要共享的类放到父加载器的加载路径下不就行了吗，应用程序也正是通过这种方式共享 JRE 的核心类。因此 Tomcat 的设计者又加了一个类加载器 SharedClassLoader，作为 WebAppClassLoader 的父加载器，专门来加载 Web 应用之间共享的类。如果 WebAppClassLoader 自己没有加载到某个类，就会委托父加载器 SharedClassLoader 去加载这个类，SharedClassLoader 会在指定目录下加载共享类，之后返回给 WebAppClassLoader，这样共享的问题就解决了。

CatalinaClassLoader

我们来看第 3 个问题，如何隔离 Tomcat 本身的类和 Web 应用的类？我们知道，要共享可以通过父子关系，要隔离那就需要兄弟关系了。兄弟关系就是指两个类加载器是平行的，它们可能拥有同一个父加载器，但是两个兄弟类加载器加载的类是隔离的。基于此 Tomcat 又设计一个类加载器 CatalinaClassLoader，专门来加载 Tomcat 自身的类。这样设计有个问题，那 Tomcat 和各 Web 应用之间需要共享一些类时该怎么办呢？

CommonClassLoader

老办法，还是再增加一个 CommonClassLoader，作为 CatalinaClassLoader 和 SharedClassLoader 的父加载器。CommonClassLoader 能加载的类都可以被 CatalinaClassLoader 和 SharedClassLoader 使用，而 CatalinaClassLoader 和 SharedClassLoader 能加载的类则与对方相互隔离。WebAppClassLoader 可以使用 SharedClassLoader 加载到的类，但各个 WebAppClassLoader 实例之间相互隔离。

## Spring 的加载问题

在 JVM 的实现中有一条隐含的规则，默认情况下，如果一个类由类加载器 A 加载，那么这个类的依赖类也是由相同的类加载器加载。比如 Spring 作为一个 Bean 工厂，它需要创建业务类的实例，并且在创建业务类实例之前需要加载这些类。Spring 是通过调用Class.forName来加载业务类的，我们来看一下 forName 的源码：

```java

public static Class<?> forName(String className) {
    Class<?> caller = Reflection.getCallerClass();
    return forName0(className, true, ClassLoader.getClassLoader(caller), caller);
}
```

可以看到在 forName 的函数里，会用调用者也就是 Spring 的加载器去加载业务类。

我在前面提到，Web 应用之间共享的 JAR 包可以交给 SharedClassLoader 来加载，从而避免重复加载。Spring 作为共享的第三方 JAR 包，它本身是由 SharedClassLoader 来加载的，Spring 又要去加载业务类，按照前面那条规则，加载 Spring 的类加载器也会用来加载业务类，但是业务类在 Web 应用目录下，不在 SharedClassLoader 的加载路径下，这该怎么办呢？

于是线程上下文加载器登场了，它其实是一种类加载器传递机制。为什么叫作“线程上下文加载器”呢，因为这个类加载器保存在线程私有数据里，只要是同一个线程，一旦设置了线程上下文加载器，在线程后续执行过程中就能把这个类加载器取出来用。因此 Tomcat 为每个 Web 应用创建一个 WebAppClassLoader 类加载器，并在启动 Web 应用的线程里设置线程上下文加载器，这样 Spring 在启动时就将线程上下文加载器取出来，用来加载 Bean。Spring 取线程上下文加载的代码如下：
```java
cl = Thread.currentThread().getContextClassLoader();
```
今天我介绍了 JVM 的类加载器原理并剖析了源码，以及 Tomcat 的类加载器的设计。重点需要你理解的是，Tomcat 的 Context 组件为每个 Web 应用创建一个 WebAppClassLoader 类加载器，由于不同类加载器实例加载的类是互相隔离的，因此达到了隔离 Web 应用的目的，同时通过 CommonClassLoader 等父加载器来共享第三方 JAR 包。而共享的第三方 JAR 包怎么加载特定 Web 应用的类呢？可以通过设置线程上下文加载器来解决。而作为 Java 程序员，我们应该牢记的是：

每个 Web 应用自己的 Java 类文件和依赖的 JAR 包，分别放在WEB-INF/classes和WEB-INF/lib目录下面。

多个应用共享的 Java 类文件和 JAR 包，分别放在 Web 容器指定的共享目录下。

当出现 ClassNotFound 错误时，应该检查你的类加载器是否正确。

线程上下文加载器不仅仅可以用在 Tomcat 和 Spring 类加载的场景里，核心框架类需要加载具体实现类时都可以用到它，比如我们熟悉的 JDBC 就是通过上下文类加载器来加载不同的数据库驱动的，感兴趣的话可以深入了解一下。

# 实现servlet规范

一个 Web 应用里往往有多个 Servlet，而在 Tomcat 中一个 Web 应用对应一个 Context 容器，也就是说一个 Context 容器需要管理多个 Servlet 实例。但 Context 容器并不直接持有 Servlet 实例，而是通过子容器 Wrapper 来管理 Servlet，你可以把 Wrapper 容器看作是 Servlet 的包装。

那为什么需要 Wrapper 呢？Context 容器直接维护一个 Servlet 数组不就行了吗？这是因为 Servlet 不仅仅是一个类实例，它还有相关的配置信息，比如它的 URL 映射、它的初始化参数，因此设计出了一个包装器，把 Servlet 本身和它相关的数据包起来，没错，这就是面向对象的思想。

那管理好 Servlet 就完事大吉了吗？别忘了 Servlet 还有两个兄弟：Listener 和 Filter，它们也是 Servlet 规范中的重要成员，因此 Tomcat 也需要创建它们的实例，也需要在合适的时机去调用它们的方法。

说了那么多，下面我们就来聊一聊 Tomcat 是如何做到上面这些事的。

## Servlet 管理

前面提到，Tomcat 是用 Wrapper 容器来管理 Servlet 的，那 Wrapper 容器具体长什么样子呢？我们先来看看它里面有哪些关键的成员变量：

```java
protected volatile Servlet instance = null;
```

毫无悬念，它拥有一个 Servlet 实例，并且 Wrapper 通过 loadServlet 方法来实例化 Servlet。为了方便你阅读，我简化了代码：

```java

public synchronized Servlet loadServlet() throws ServletException {
    Servlet servlet;
  
    //1. 创建一个Servlet实例
    servlet = (Servlet) instanceManager.newInstance(servletClass);    
    
    //2.调用了Servlet的init方法，这是Servlet规范要求的
    initServlet(servlet);
    
    return servlet;
}
```

其实 loadServlet 主要做了两件事：创建 Servlet 的实例，并且调用 Servlet 的 init 方法，因为这是 Servlet 规范要求的。

那接下来的问题是，什么时候会调到这个 loadServlet 方法呢？为了加快系统的启动速度，我们往往会采取资源延迟加载的策略，Tomcat 也不例外，默认情况下 Tomcat 在启动时不会加载你的 Servlet，除非你把 Servlet 的loadOnStartup参数设置为true。

这里还需要你注意的是，虽然 Tomcat 在启动时不会创建 Servlet 实例，但是会创建 Wrapper 容器，就好比尽管枪里面还没有子弹，先把枪造出来。那子弹什么时候造呢？是真正需要开枪的时候，也就是说有请求来访问某个 Servlet 时，这个 Servlet 的实例才会被创建。

那 Servlet 是被谁调用的呢？我们回忆一下专栏前面提到过 Tomcat 的 Pipeline-Valve 机制，每个容器组件都有自己的 Pipeline，每个 Pipeline 中有一个 Valve 链，并且每个容器组件有一个 BasicValve（基础阀）。Wrapper 作为一个容器组件，它也有自己的 Pipeline 和 BasicValve，Wrapper 的 BasicValve 叫 StandardWrapperValve。

你可以想到，当请求到来时，Context 容器的 BasicValve 会调用 Wrapper 容器中 Pipeline 中的第一个 Valve，然后会调用到 StandardWrapperValve。我们先来看看它的 invoke 方法是如何实现的，同样为了方便你阅读，我简化了代码：

```java

public final void invoke(Request request, Response response) {

    //1.实例化Servlet
    servlet = wrapper.allocate();
   
    //2.给当前请求创建一个Filter链
    ApplicationFilterChain filterChain =
        ApplicationFilterFactory.createFilterChain(request, wrapper, servlet);

   //3. 调用这个Filter链，Filter链中的最后一个Filter会调用Servlet
   filterChain.doFilter(request.getRequest(), response.getResponse());

}
```

StandardWrapperValve 的 invoke 方法比较复杂，去掉其他异常处理的一些细节，本质上就是三步：

- 第一步，创建 Servlet 实例；

- 第二步，给当前请求创建一个 Filter 链；

- 第三步，调用这个 Filter 链。

你可能会问，为什么需要给每个请求创建一个 Filter 链？这是因为每个请求的请求路径都不一样，而 Filter 都有相应的路径映射，因此不是所有的 Filter 都需要来处理当前的请求，我们需要根据请求的路径来选择特定的一些 Filter 来处理。

第二个问题是，为什么没有看到调到 Servlet 的 service 方法？这是因为 Filter 链的 doFilter 方法会负责调用 Servlet，具体来说就是 Filter 链中的最后一个 Filter 会负责调用 Servlet。

接下来我们来看 Filter 的实现原理。

## Filter 管理

我们知道，跟 Servlet 一样，Filter 也可以在web.xml文件里进行配置，不同的是，Filter 的作用域是整个 Web 应用，因此 Filter 的实例是在 Context 容器中进行管理的，Context 容器用 Map 集合来保存 Filter。

```java

private Map<String, FilterDef> filterDefs = new HashMap<>();
```

那上面提到的 Filter 链又是什么呢？Filter 链的存活期很短，它是跟每个请求对应的。一个新的请求来了，就动态创建一个 Filter 链，请求处理完了，Filter 链也就被回收了。理解它的原理也非常关键，我们还是来看看源码：

```java

public final class ApplicationFilterChain implements FilterChain {
  
  //Filter链中有Filter数组，这个好理解
  private ApplicationFilterConfig[] filters = new ApplicationFilterConfig[0];
    
  //Filter链中的当前的调用位置
  private int pos = 0;
    
  //总共有多少了Filter
  private int n = 0;

  //每个Filter链对应一个Servlet，也就是它要调用的Servlet
  private Servlet servlet = null;
  
  public void doFilter(ServletRequest req, ServletResponse res) {
        internalDoFilter(request,response);
  }
   
  private void internalDoFilter(ServletRequest req,
                                ServletResponse res){

    // 每个Filter链在内部维护了一个Filter数组
    if (pos < n) {
        ApplicationFilterConfig filterConfig = filters[pos++];
        Filter filter = filterConfig.getFilter();

        filter.doFilter(request, response, this);
        return;
    }

    servlet.service(request, response);
   
}
```

从 ApplicationFilterChain 的源码我们可以看到几个关键信息：

- Filter 链中除了有 Filter 对象的数组，还有一个整数变量 pos，这个变量用来记录当前被调用的 Filter 在数组中的位置。

- Filter 链中有个 Servlet 实例，这个好理解，因为上面提到了，每个 Filter 链最后都会调到一个 Servlet。

- Filter 链本身也实现了 doFilter 方法，直接调用了一个内部方法 internalDoFilter。

- internalDoFilter 方法的实现比较有意思，它做了一个判断，如果当前 Filter 的位置小于 Filter 数组的长度，也就是说 Filter 还没调完，就从 Filter 数组拿下一个 Filter，调用它的 doFilter 方法。否则，意味着所有 Filter 都调到了，就调用 Servlet 的 service 方法。

但问题是，方法体里没看到循环，谁在不停地调用 Filter 链的 doFilter 方法呢？Filter 是怎么依次调到的呢？

答案是 Filter 本身的 doFilter 方法会调用 Filter 链的 doFilter 方法，我们还是来看看代码就明白了：

```java

public void doFilter(ServletRequest request, ServletResponse response,
        FilterChain chain){
        
          ...
          
          //调用Filter的方法
          chain.doFilter(request, response);
      
      }
```

注意 Filter 的 doFilter 方法有个关键参数 FilterChain，就是 Filter 链。并且每个 Filter 在实现 doFilter 时，必须要调用 Filter 链的 doFilter 方法，而 Filter 链中保存当前 Filter 的位置，会调用下一个 Filter 的 doFilter 方法，这样链式调用就完成了。

Filter 链跟 Tomcat 的 Pipeline-Valve 本质都是责任链模式，但是在具体实现上稍有不同，你可以细细体会一下。

## Listener 管理

我们接着聊 Servlet 规范里 Listener。跟 Filter 一样，Listener 也是一种扩展机制，你可以监听容器内部发生的事件，主要有两类事件：

- 第一类是生命状态的变化，比如 Context 容器启动和停止、Session 的创建和销毁。

- 第二类是属性的变化，比如 Context 容器某个属性值变了、Session 的某个属性值变了以及新的请求来了等。

我们可以在web.xml配置或者通过注解的方式来添加监听器，在监听器里实现我们的业务逻辑。对于 Tomcat 来说，它需要读取配置文件，拿到监听器类的名字，实例化这些类，并且在合适的时机调用这些监听器的方法。

Tomcat 是通过 Context 容器来管理这些监听器的。Context 容器将两类事件分开来管理，分别用不同的集合来存放不同类型事件的监听器：

```java

//监听属性值变化的监听器
private List<Object> applicationEventListenersList = new CopyOnWriteArrayList<>();

//监听生命事件的监听器
private Object applicationLifecycleListenersObjects[] = new Object[0];
```

剩下的事情就是触发监听器了，比如在 Context 容器的启动方法里，就触发了所有的 ServletContextListener：

```java

//1.拿到所有的生命周期监听器
Object instances[] = getApplicationLifecycleListeners();

for (int i = 0; i < instances.length; i++) {
   //2. 判断Listener的类型是不是ServletContextListener
   if (!(instances[i] instanceof ServletContextListener))
      continue;

   //3.触发Listener的方法
   ServletContextListener lr = (ServletContextListener) instances[i];
   lr.contextInitialized(event);
}
```

需要注意的是，这里的 ServletContextListener 接口是一种留给用户的扩展机制，用户可以实现这个接口来定义自己的监听器，监听 Context 容器的启停事件。Spring 就是这么做的。ServletContextListener 跟 Tomcat 自己的生命周期事件 LifecycleListener 是不同的。LifecycleListener 定义在生命周期管理组件中，由基类 LifecycleBase 统一管理。

Servlet 规范中最重要的就是 Servlet、Filter 和 Listener“三兄弟”。Web 容器最重要的职能就是把它们创建出来，并在适当的时候调用它们的方法。

Tomcat 通过 Wrapper 容器来管理 Servlet，Wrapper 包装了 Servlet 本身以及相应的参数，这体现了面向对象中“封装”的设计原则。

Tomcat 会给每个请求生成一个 Filter 链，Filter 链中的最后一个 Filter 会负责调用 Servlet 的 service 方法。

对于 Listener 来说，我们可以定制自己的监听器来监听 Tomcat 内部发生的各种事件：包括 Web 应用级别的、Session 级别的和请求级别的。Tomcat 中的 Context 容器统一维护了这些监听器，并负责触发。

Context 组件通过自定义类加载器来加载 Web 应用，并实现了 Servlet 规范，直接跟 Web 应用打交道，是一个核心的容器组件。