## 业务背景
为了实现不同分级的业务消息延迟不同的时间(如:1级 5MIN 2级 10MIN 3级 20MIN)
项目原使用了`ThreadPoolTaskScheduler` 实现 但是经常出现延迟任务不执行的情况

## 思路+分析
考虑项目中原有很多定时任务 会抢占资源 考虑使用中间件来实现这个类似延迟队列的功能
延迟队列基于项目已接入的中间件可用rabbitmq和redis都可以实现
但是考虑实现的简单程度决定使用:订阅redis的key过期事件通知+redisson分布式锁

## 知识点
### redis-key过期事件通知及设置
```conf
# It is possible to select the events that Redis will notify among a set
# of classes. Every class is identified by a single character:
#
#  K     Keyspace events, published with __keyspace@<db>__ prefix.
#  E     Keyevent events, published with __keyevent@<db>__ prefix.
#  g     Generic commands (non-type specific) like DEL, EXPIRE, RENAME, ...
#  $     String commands
#  l     List commands
#  s     Set commands
#  h     Hash commands
#  z     Sorted set commands
#  x     Expired events (events generated every time a key expires)
#  e     Evicted events (events generated when a key is evicted for maxmemory)
#  A     Alias for g$lshzxe, so that the "AKE" string means all the events.
#
#  The "notify-keyspace-events" takes as argument a string that is composed
#  of zero or multiple characters. The empty string means that notifications
#  are disabled.
#
#  Example: to enable list and generic events, from the point of view of the
#           event name, use:
#
#  notify-keyspace-events Elg
#
#  Example 2: to get the stream of the expired keys subscribing to channel
#             name __keyevent@0__:expired use:
#
#  notify-keyspace-events Ex
```

### 通知机制
基于redis的pubsub机制 也就是所有的实例都会收到这条消息 为了避免重复处理 所以引入了分布式锁

### 分布式锁的引入
使用了redis分布式锁最成熟的方案redisson来实现

## 实现

```shell
config set notify-keyspace-events xE
config rewrite
```

```java

//在业务入口添加key并设置对应分级的过期时间
long checkOffset = 20l;  
if ("P0".equals(alarmInfo.getPriority())) {  
	checkOffset = 5l;  
} else if ("P1".equals(alarmInfo.getPriority())) {  
	checkOffset = 10l;  
}  
redisTemplate.opsForValue().set(Constants.DING_READ_CHECK_PREFIX + msgId + "," + eventId, msgId, checkOffset, TimeUnit.MINUTES);


//监听+分布式锁
@Slf4j  
@Configuration  
public class RedisKeyExpiredListener extends KeyExpirationEventMessageListener {  
  
    private final AlarmInfoService alarmInfoService;  
    private final DingInternalApiClient dingInternalApiClient;  
    private final StringRedisTemplate redisTemplate;  
    private final RedissonClient redissonClient;  
  
  
    public RedisKeyExpiredListener(RedisMessageListenerContainer listenerContainer, AlarmInfoService alarmInfoService, DingInternalApiClient dingInternalApiClient, StringRedisTemplate redisTemplate, RedissonClient redissonClient) {  
        super(listenerContainer);  
        this.alarmInfoService = alarmInfoService;  
        this.dingInternalApiClient = dingInternalApiClient;  
        this.redisTemplate = redisTemplate;  
        this.redissonClient = redissonClient;  
    }  
  
    @Override  
    @TraceId    public void onMessage(Message message, byte[] pattern) {  
        String key = new String(message.getBody(), StandardCharsets.UTF_8);  
        //监听key过期  
        log.error("系统redis-key过期事件:key={}", key);  
        if (StringUtils.isEmpty(key)) {  
            log.error("系统redis-key过期事件:key监听错误!");  
            return;        }  
        //判断开头是否符合约定 && 包含全部数据  
        if (key.startsWith(Constants.DING_READ_CHECK_PREFIX) && key.contains(",")) {  
            log.error("开始执行key分析:{}", key);  
            try {  
                //分离 钉钉msgId 和 告警eventId  
                String[] ss = key.replaceAll(Constants.DING_READ_CHECK_PREFIX, "").split(",");  
                String msgId = ss[0];  
                String eventId = ss[1];  
                if (eventId == null) {  
                    log.error("根据msgId获取事件id错误!{}", key);  
                    return;                }  
                //查询原有告警  
                AlarmInfo alarmInfo = null;  
                List<AlarmInfo> list = alarmInfoService.selectByEventId(eventId);  
                if (list != null && list.size() == 1) {  
                    alarmInfo = list.get(0);  
                } else {  
                    log.error("根据事件id:{}查询告警出错!为空或不唯一!", eventId);  
                    return;                }  
                //查询锁  
                RLock lock = redissonClient.getLock(Constants.DING_LOCK_CHECK_PREFIX + msgId);  
                try {  
                    //上锁  
                    if (lock.tryLock(3, TimeUnit.MINUTES)) {  
                        log.error("更新钉钉已读状态调度任务开始,{}", eventId);  
                        boolean hasMobile = StringUtils.isNotBlank((alarmInfo.getActualHandleContact()));  
                        AlarmInfo.AlarmInfoBuilder updateRes = AlarmInfo.builder().id(alarmInfo.getId());  
                        //查询钉钉已读状态  
                        DingNotifyQueryResult res = dingInternalApiClient.querySendResultInternal(msgId);  
                        if (res.getData().getReadUserIdList().size() > 0) {  
                            log.error("告警已读,{}", eventId);  
                            updateRes.dingNotifyStatus(AlarmDingAutoNotifyStatus.read.getCode());  
                            log.error("更新钉钉已读时间:{}", eventId);  
                            Date date = new Date();  
                            updateRes.alarmResponseTime(date);  
                            long resCost = DateUtils.secondDiff(date, alarmInfo.getAlarmTime());  
                            updateRes.dingDuration(resCost);  
                            //p0只更新钉钉时间不更新响应时间  
                            if (!alarmInfo.getPriority().equals("P0")) {  
                                log.error("非P0告警在此处更新响应时间:{}",eventId);  
                                updateRes.alarmResponseCost(String.valueOf(resCost));  
                            }  
                        } else {  
                            updateRes.dingNotifyStatus(AlarmDingAutoNotifyStatus.unread.getCode());  
                            //未读打电话通知  
                            if (hasMobile && alarmInfo.isLackKeyInfo() && AlarmPriority.P1.name().equals(alarmInfo.getPriority())) {  
                                //220530暂时取消p1电话通知 只钉钉已读状态 并记录日志  
                                log.error("P1告警暂停电话通知,记录日志:{}", eventId);  
                            }  
                        }  
                        //更新已读状态  
                        alarmInfoService.updateById(updateRes.build());  
                    }  
                } finally {  
                    //解锁  
                    lock.unlock();  
                }  
            } catch (Exception e) {  
                log.error("更新钉钉已读状态调度任务异常,{}", e);  
            }  
        }  
    }  
}


```