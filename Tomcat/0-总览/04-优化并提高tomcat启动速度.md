## 清理你的 Tomcat

1. 清理不必要的 Web 应用

首先我们要做的是删除掉 webapps 文件夹下不需要的工程，一般是 host-manager、example、doc 等这些默认的工程，可能还有以前添加的但现在用不着的工程，最好把这些全都删除掉。如果你看过 Tomcat 的启动日志，可以发现每次启动 Tomcat，都会重新布署这些工程。

2. 清理 XML 配置文件

我们知道 Tomcat 在启动的时候会解析所有的 XML 配置文件，但 XML 解析的代价可不小，因此我们要尽量保持配置文件的简洁，需要解析的东西越少，速度自然就会越快。

3. 清理 JAR 文件

我们还可以删除所有不需要的 JAR 文件。JVM 的类加载器在加载类时，需要查找每一个 JAR 文件，去找到所需要的类。如果删除了不需要的 JAR 文件，查找的速度就会快一些。这里请注意：Web 应用中的 lib 目录下不应该出现 Servlet API 或者 Tomcat 自身的 JAR，这些 JAR 由 Tomcat 负责提供。如果你是使用 Maven 来构建你的应用，对 Servlet API 的依赖应该指定为<scope>provided</scope>。

4. 清理其他文件

及时清理日志，删除 logs 文件夹下不需要的日志文件。同样还有 work 文件夹下的 catalina 文件夹，它其实是 Tomcat 把 JSP 转换为 Class 文件的工作目录。有时候我们也许会遇到修改了代码，重启了 Tomcat，但是仍没效果，这时候便可以删除掉这个文件夹，Tomcat 下次启动的时候会重新生成。

## 禁止 Tomcat TLD 扫描

Tomcat 为了支持 JSP，在应用启动的时候会扫描 JAR 包里面的 TLD 文件，加载里面定义的标签库，所以在 Tomcat 的启动日志里，你可能会碰到这种提示：

At least one JAR was scanned for TLDs yet contained no TLDs. Enable debug logging for this logger for a complete list of JARs that were scanned but no TLDs were found in them. Skipping unneeded JARs during scanning can improve startup time and JSP compilation time.

Tomcat 的意思是，我扫描了你 Web 应用下的 JAR 包，发现 JAR 包里没有 TLD 文件。我建议配置一下 Tomcat 不要去扫描这些 JAR 包，这样可以提高 Tomcat 的启动速度，并节省 JSP 编译时间。

那如何配置不去扫描这些 JAR 包呢，这里分两种情况：

如果你的项目没有使用 JSP 作为 Web 页面模板，而是使用 Velocity 之类的模板引擎，你完全可以把 TLD 扫描禁止掉。方法是，找到 Tomcat 的conf/目录下的context.xml文件，在这个文件里 Context 标签下，加上 JarScanner 和 JarScanFilter 子标签，像下面这样。

![[Pasted image 20230323093750.png]]

如果你的项目使用了 JSP 作为 Web 页面模块，意味着 TLD 扫描无法避免，但是我们可以通过配置来告诉 Tomcat，只扫描那些包含 TLD 文件的 JAR 包。方法是，找到 Tomcat 的conf/目录下的catalina.properties文件，在这个文件里的 jarsToSkip 配置项中，加上你的 JAR 包。

```properties
tomcat.util.scan.StandardJarScanFilter.jarsToSkip=xxx.jar
```

## 关闭 WebSocket 支持

Tomcat 会扫描 WebSocket 注解的 API 实现，比如@ServerEndpoint注解的类。我们知道，注解扫描一般是比较慢的，如果不需要使用 WebSocket 就可以关闭它。具体方法是，找到 Tomcat 的conf/目录下的context.xml文件，给 Context 标签加一个 containerSciFilter 的属性，像下面这样。

![[Pasted image 20230323093850.png]]

更进一步，如果你不需要 WebSocket 这个功能，你可以把 Tomcat lib 目录下的websocket-api.jar和tomcat-websocket.jar这两个 JAR 文件删除掉，进一步提高性能。

## 关闭 JSP 支持

跟关闭 WebSocket 一样，如果你不需要使用 JSP，可以通过类似方法关闭 JSP 功能，像下面这样。

![[Pasted image 20230323093902.png]]

我们发现关闭 JSP 用的也是 containerSciFilter 属性，如果你想把 WebSocket 和 JSP 都关闭，那就这样配置：

![[Pasted image 20230323093912.png]]

## 禁止 Servlet 注解扫描

Servlet 3.0 引入了注解 Servlet，Tomcat 为了支持这个特性，会在 Web 应用启动时扫描你的类文件，因此如果你没有使用 Servlet 注解这个功能，可以告诉 Tomcat 不要去扫描 Servlet 注解。具体配置方法是，在你的 Web 应用的web.xml文件中，设置 `<web-app>` 元素的属性`metadata-complete="true"`，像下面这样。
![[Pasted image 20230323094023.png]]
metadata-complete的意思是，web.xml里配置的 Servlet 是完整的，不需要再去库类中找 Servlet 的定义。

## 配置 Web-Fragment 扫描

Servlet 3.0 还引入了“Web 模块部署描述符片段”的web-fragment.xml，这是一个部署描述文件，可以完成web.xml的配置功能。而这个web-fragment.xml文件必须存放在 JAR 文件的META-INF目录下，而 JAR 包通常放在WEB-INF/lib目录下，因此 Tomcat 需要对 JAR 文件进行扫描才能支持这个功能。

你可以通过配置web.xml里面的`<absolute-ordering>`元素直接指定了哪些 JAR 包需要扫描web fragment，如果`<absolute-ordering/>`元素是空的， 则表示不需要扫描，像下面这样。

![[Pasted image 20230323094040.png]]

## 随机数熵源优化

这是一个比较有名的问题。Tomcat 7 以上的版本依赖 Java 的 SecureRandom 类来生成随机数，比如 Session ID。而 JVM 默认使用阻塞式熵源（/dev/random）， 在某些情况下就会导致 Tomcat 启动变慢。当阻塞时间较长时， 你会看到这样一条警告日志：

```
<DATE> org.apache.catalina.util.SessionIdGenerator createSecureRandom

INFO: Creation of SecureRandom instance for session ID generation using [SHA1PRNG] took [8152] milliseconds.
```


这其中的原理我就不展开了，你可以阅读资料获得更多信息。解决方案是通过设置，让 JVM 使用非阻塞式的熵源。

我们可以设置 JVM 的参数：

`-Djava.security.egd=file:/dev/./urandom
`
或者是设置java.security文件，位于$JAVA_HOME/jre/lib/security目录之下： `securerandom.source=file:/dev/./urandom`

这里请你注意，/dev/./urandom中间有个./的原因是 Oracle JRE 中的 Bug，Java 8 里面的 SecureRandom 类已经修正这个 Bug。 阻塞式的熵源（/dev/random）安全性较高， 非阻塞式的熵源（/dev/./urandom）安全性会低一些，因为如果你对随机数的要求比较高， 可以考虑使用硬件方式生成熵源。

## 并行启动多个 Web 应用

Tomcat 启动的时候，默认情况下 Web 应用都是一个一个启动的，等所有 Web 应用全部启动完成，Tomcat 才算启动完毕。如果在一个 Tomcat 下你有多个 Web 应用，为了优化启动速度，你可以配置多个应用程序并行启动，可以通过修改server.xml中 Host 元素的 startStopThreads 属性来完成。startStopThreads 的值表示你想用多少个线程来启动你的 Web 应用，如果设成 0 表示你要并行启动 Web 应用，像下面这样的配置。

![[Pasted image 20230323094132.png]]

这里需要注意的是，Engine 元素里也配置了这个参数，这意味着如果你的 Tomcat 配置了多个 Host（虚拟主机），Tomcat 会以并行的方式启动多个 Host。