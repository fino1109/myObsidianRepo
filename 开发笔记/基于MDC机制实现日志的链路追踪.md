[参考文章](https://www.jianshu.com/p/3dca4aeb6edd)

## 1.需求背景
由于程序内调用关系复杂 链路很长 排查线上问题时很难在日志中查询一次请求的全部日志

## 2.分析+思路
1.在核心逻辑的每个入口记录一个`traceId`用于区分请求的唯一身份标识
2.使用logback的MDC机制,在日志模板中记录`traceId`,输出到日志文件

3.扩展,修改接入elk的sdk,多记录一个`traceId`字段
4.扩展,在调用下游应用接口是将`traceId`放入http请求头进行传递

## 3.实现
### log组件
```xml
<pattern>%d{yyyy-MM-dd/HH:mm:ss.SSS} [%X{TRACE_ID}] %contextName [%thread] %-5level %logger{36} - %msg%n</pattern>
```

### 数据来源为接口
#### 拦截器实现
```java
//拦截器
public class LogInterceptor extends HandlerInterceptorAdapter {
    
	private final static String KEY = "TRACE_ID";

    @Override
    public void afterCompletion(HttpServletRequest arg0, HttpServletResponse arg1, Object arg2, Exception arg3)
            throws Exception {
        MDC.remove(KEY);
    }

    @Override
    public void postHandle(HttpServletRequest arg0, HttpServletResponse arg1,
                           Object arg2, ModelAndView arg3) throws Exception {
    }

    @Override
    public boolean preHandle(HttpServletRequest request,
                             HttpServletResponse response, Object handler) throws Exception {
        String token = UUID.randomUUID().toString().replace("-", "");
        MDC.put(KEY, token);
        return true;
    }
}

//注册拦截器

@Configuration
public class WebMvcConfigurer extends WebMvcConfigurerAdapter {

    @Bean
    public HandlerInterceptor logInterceptor() {
        return new LogInterceptor();
    }

    @Override
    public void addInterceptors(InterceptorRegistry registry) {
	    //这里添加我们需要记录traceId的接口
        registry.addInterceptor(logInterceptor()).addPathPatterns("/**");
        super.addInterceptors(registry);
    }
}

```

#### AOP注解实现
使用AOP注解可以将注解标记在mq的消费者端方法和接口方法上 比拦截器稍加灵活
```java
//注解
@Target(ElementType.METHOD)  
@Retention(RetentionPolicy.RUNTIME)  
@Documented  
public @interface TraceId {  
      
}

//切面
@Component  
@Aspect  
public class TraceAspect {  
  
    private final static String SESSION_KEY = "TRACE_ID";  
  
    @Pointcut("@annotation(com.xx.mc.aop.TraceId)" )  
    public void setTraceId() {  
  
    }  
  
  
    @Before("setTraceId()" )  
    public void doBefore(JoinPoint joinPoint) {  
        String token = UUID.randomUUID().toString().replace("-", "");  
        MDC.put(KEY, token);  
    }  
  
  
    @AfterReturning(returning = "ret" , pointcut = "setTraceId()" )  
    public void doAfterReturning(Object ret) {  
        MDC.remove(KEY);  
    }  
}
```

### 异步支持
```java

@Configuration  
@EnableAspectJAutoProxy(proxyTargetClass = true)  
@Slf4j  
public class ThreadPoolConfiguration implements AsyncConfigurer {  
  
    @Bean("commonThreadPoolTaskExecutor")  
    public ThreadPoolTaskExecutor threadPoolTaskExecutor() {  
        ThreadPoolTaskExecutor threadPoolTaskExecutor = new ThreadPoolTaskExecutor();  
        threadPoolTaskExecutor.setMaxPoolSize(16);  
        threadPoolTaskExecutor.setCorePoolSize(8);  
        threadPoolTaskExecutor.setQueueCapacity(16384);  
        threadPoolTaskExecutor.setKeepAliveSeconds(20);  
        threadPoolTaskExecutor.setThreadNamePrefix("async-worker-");  
        threadPoolTaskExecutor.setTaskDecorator(new MdcTaskDecorator());  
        threadPoolTaskExecutor.afterPropertiesSet();  
        return threadPoolTaskExecutor;  
    }  
  
    class MdcTaskDecorator implements TaskDecorator {  
        private static final String KEY = "TRACE_ID";  
  
        @Override  
        public Runnable decorate(Runnable runnable) {  
	        //生产有概率在此处get到null 无法传递traceId 不阻塞业务
            Map<String, String> map = MDC.getCopyOfContextMap();  
            return () -> {  
                try {  
                    if (map != null) {  
                        MDC.setContextMap(map);  
                    }  
                    String traceId = MDC.get(KEY);  
                    if (StringUtils.isBlank(traceId)) {  
                        traceId = UUID.randomUUID().toString();  
                        MDC.put(KEY, traceId);  
                    }  
                    runnable.run();  
                } catch (Exception e) {  
                    log.error("MDC传递traceId异常:{}", e);  
                } finally {  
                    MDC.clear();  
                }  
            };  
        }  
    }  
  
    @Override  
    public AsyncUncaughtExceptionHandler getAsyncUncaughtExceptionHandler() {  
        return (throwable, method, params) -> {  
            log.error("异步任务异常：方法：{} 参数：{}", method.getName(), JSON.toJSONString(params));  
            log.error(throwable.getMessage(), throwable);  
        };  
    }  
}
```

#### 公司elk sdk部分组件重写
重写sdk部分的重点在于重写appender和appender传递的数据对象class
```xml
<appender name="wpAppender"  
          class="com.xx.mc.logging.MyLogBackAppender">  
    <env>prod</env>  
    <index>i11</index>  
    <logPackage>com.xx.mc</logPackage>  
    <application>xx</application>  
</appender>
```

```java
public class LogUtils {  
        private static String ip;  
  
        public LogUtils() {  
        }  
  
        public static WpData buildData(String level, String index, String className, String msg, String exception, String application, String applicationGroup,String traceId) {  
            WpData wpData = new WpData();  
            wpData.setLevel(level);  
            wpData.setLoggerName(index);  
            wpData.setClassName(className);  
            wpData.setApplication(application);  
            wpData.setApplicationGroup(applicationGroup);  
            wpData.setData(msg);  
            wpData.setException(exception);  
            wpData.setServerIp(ip); 
            //添加了这一行 
            wpData.setTraceId(traceId);  
            wpData.setTimestamp(System.currentTimeMillis());  
            return wpData;  
        }  
  
}

public class MyLogBackAppender extends AppenderBase<ILoggingEvent> {  
    private final static String KEY = "TRACE_ID";  
    private UDPEnum en;  
    private String index;  
    private String logPackage;  
    private String application;  
    private String applicationGroup;  
  
    public MyLogBackAppender() {  
    }  
  
    public void setApplication(String application) {  
        this.application = application;  
    }  
  
    public void setEnv(String env) {  
        this.en = UDPEnum.getUdpEnum(env);  
    }  
  
    public void setLogPackage(String logPackage) {  
        this.logPackage = logPackage == null ? null : logPackage.trim();  
    }  
  
    public void setApplicationGroup(String applicationGroup) {  
        this.applicationGroup = applicationGroup == null ? null : applicationGroup.trim();  
    }  
  
    public void setIndex(String index) {  
        this.index = StringUtil.getIndex(index);  
    }  
  
    protected void append(ILoggingEvent event) {  
        String traceId = MDC.get(KEY);  
        String className = event.getLoggerName();  
        if (!WpUtil.checkClassName(className, this.logPackage)) {  
            String msg = event.getFormattedMessage();  
            Map<String, String> msgMap = StringUtil.splitMsg(msg);  
            String level = event.getLevel().toString();  
            IThrowableProxy throwableProxy = event.getThrowableProxy();  
            String exception = null;  
            try {  
                StackTraceElementProxy[] stackTrace = throwableProxy.getStackTraceElementProxyArray();  
                String stack = (String) Arrays.stream(stackTrace).limit(50L).map(StackTraceElementProxy::getSTEAsString).collect(Collectors.joining(WpConstants.LINESEPARATOR));  
                String message = Objects.isNull(throwableProxy.getMessage()) ? "" : throwableProxy.getMessage();  
                exception = throwableProxy.getClassName().concat(": ").concat(message).concat(WpConstants.LINESEPARATOR).concat(stack);  
            } catch (Exception var11) {  
  
            }  
            WpData wpData = LogUtils.buildData(level, this.index, className, msg, exception, this.application, this.applicationGroup,traceId);  
            Map<String, Object> map = wpData.toMap();  
            map.putAll(msgMap);  
            UDPUtil.send(map, this.en);  
        }  
    }  
}


public class WpData implements Serializable {  
    public String application;  
    public String applicationGroup;  
    public String serverIp;  
    public String exception;  
    public String data;  
    public String className;  
    public String loggerName;  
    public String level;  
    public String traceId;  
    public long timestamp;  
  
    public WpData() {  
    }  
  
    public WpData(String application, String applicationGroup, String serverIp, String exception, String traceId, String data, String className, String loggerName, String level, long timestamp) {  
        this.application = application;  
        this.applicationGroup = applicationGroup;  
        this.serverIp = serverIp;  
        this.exception = exception;  
        this.data = data;  
        this.className = className;  
        this.loggerName = loggerName;  
        this.level = level;  
        this.traceId = traceId;  
        this.timestamp = timestamp;  
    }  
  
    public Map<String, Object> toMap() {  
        Map<String, Object> map = new HashMap(16);  
        map.put("application", this.application);  
        map.put("applicationGroup", this.applicationGroup);  
        map.put("serverIp", this.serverIp);  
        map.put("exception", this.exception);  
        map.put("data", this.data);  
        map.put("className", this.className);  
        map.put("loggerName", this.loggerName);  
        map.put("level", this.level);  
        map.put("timestamp", this.timestamp);  
        map.put("traceId", this.traceId);  
        return map;  
    }  
	//getter
	//setter
	//tostring
	//builder
}


```