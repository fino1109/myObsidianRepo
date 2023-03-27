# 部署

![[Pasted image 20230327172724.png]]
# 单一职责节点

好处：  
可以节省成本

## master node

### 配置

```
node.master=true
node.data=false
node.ingest=false
```

### 职责

```
负责集群状态管理

从高可用&避免脑裂的角度出发 一般每个生产集群配置3台master节点

每个集群只有一个活跃的master node
    负责分片管理 索引创建 集群管理等操作

不能和data或coordinate节点混合部署
    data节点内存占用大
    coordinate节点会在处理部分查询是占用大量内存
    这些都可能影响master节点从而影响整个集群

建议使用低配置的cpu ram disk
```

## data node

### 配置

```
node.master=false
node.data=true
node.ingest=false
```

### 职责

```
负责数据的存储和处理客户端的请求

数据量增加时可横向增加data节点数量实现扩容

建议使用高配置的cpu ram disk
```

## ingest node

### 配置

```
node.master=false
node.data-false
node.ingest=true
```

### 职责

```
负责数据处理

可以对写入的数据通过pipeline进行处理 增加集群的写入性能
写入性能不足时可横向扩展ingest节点增加提升写入性能

建议使用高配置的cpu 中等配置的ram 低配置的disk
```

## coordinate node

### 配置

```
node.master=false
node.data=false
node.ingest=false
```

### 职责

```
扮演负载均衡器的角色 降低master和data节点的负载 也可以负责搜索结果的聚合

复杂查询较多时可横向扩展节点数量从而提升性能

可以和kibana部署在相同的节点上


建议使用中高配置的cpu ram 低配置的disk
```

# 异地多活部署
![[Pasted image 20230327172818.png]]

## 使用ingets节点添加时间戳
```


##注意 ingets需要开启
PUT _ingest/pipeline/my_timestamp_pipeline
{
  "description": "Adds a field to a document with the time of ingestion",
  "processors": [
    {
      "set": {
        "field": "ingest_timestamp",
        "value": "{{_ingest.timestamp}}"
      }
    }
  ]
}


PUT pa_log_clean_with_time
{
  "settings": {
    "default_pipeline": "my_timestamp_pipeline"
  }
}
```

# filebeat配置示例
```yaml
max_procs: 4
queue.mem.events: 4096
queue.mem.f	lush.min_events: 2048
filebeat.inputs:
- type: log
  enabled: true
  max_bytes: 20480
  recursive_glob.enabled: true
  paths:
    - /home/xxx/netlog/*/*/*.txt
- type: filestream
  enabled: false
  paths:
    - /var/log/*.log
- type: udp
  enabled: true
  host: 'localhost:9000'
  max_message_size: 10KiB
  read_buffer: 0


filebeat.config.modules:
  path: ${path.config}/modules.d/*.yml
  reload.enabled: false
setup.template.settings:
  index.number_of_shards: 1
  
setup.kibana:
  #host: "localhost:5601"
  #space.id:

output.kafka:
  enabled: true
  hosts: ["kafka_host:port"]
  topic: uat_log_net
  partition.round_robin:
    reachable_only: true
  worker: 4
  required_acks: 1
  compression: gzip
  max_message_bytes: 1000000 

processors:
  - add_host_metadata:
      when.not.contains.tags: forwarded
  - add_cloud_metadata: ~
  - add_docker_metadata: ~
  - add_kubernetes_metadata: ~
```