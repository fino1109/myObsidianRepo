## 1.背景

随着公司业务的不断扩大，公司原本使用的虚拟机部署的skywalking集群虽然仍能满足使用，但是在面对业务高峰和高峰过后的业务量降低时回存在以下缺点，这也是很多虚拟机部署业务应用所共同面对的问题，扩容缩容问题:

-   业务高峰来临时动态扩容困难，出现紧急状况时导致系统不可用时间增加
-   业务高峰过后需要缩容，操作也相对复杂

随着公司云平台的日渐成熟，我们决定将APM监控也搬上云平台。

## 2.虚拟机部署配置

### 版本:

skywalking使用7.0.0

es使用7.6.2

### skywalking oap：

7台虚拟机 32C32G JVM16G

agent连接controller通过LVS再经过主备的nginx进行代理

### skywalking web：

3台虚拟机 16C16G JVM8G

通过F5直接映射域名IP进行访问

### es集群：

master*3(4C8G JVM4G)

client*3(16C32G JVM24G)

data*8(32C 64G JVM16G 500G)

## 3.上云过程

使用helm3进行部署，使用官方的helm进行部署。期间遇到了如下的坑。

### 问题1:生产es连接报错

由于生产es需要认证,但是配置了用户名和密码后出现`NoSuchFileException:../es_keystore.jks`错误：

解决办法参考如下链接：

[https://help.aliyun.com/document_detail/161783.html#title-5ct-j89-zqo](https://help.aliyun.com/document_detail/161783.html#title-5ct-j89-zqo)
```yaml
storage:
  selector: ${SW_STORAGE:elasticsearch7}
  elasticsearch7:
    nameSpace: ${SW_NAMESPACE:"skywalking-index"}
    clusterNodes: ${SW_STORAGE_ES_CLUSTER_NODES:es-cn-4591kzdzk000i****.public.elasticsearch.aliyuncs.com:9200}
    protocol: ${SW_STORAGE_ES_HTTP_PROTOCOL:"http"}
   # 注释掉下面两行即可
   # trustStorePath: ${SW_SW_STORAGE_ES_SSL_JKS_PATH:"../es_keystore.jks"}
   # trustStorePass: ${SW_SW_STORAGE_ES_SSL_JKS_PASS:""}
    enablePackedDownsampling: ${SW_STORAGE_ENABLE_PACKED_DOWNSAMPLING:true} # Hour and Day metrics will be merged into minute index.
    dayStep: ${SW_STORAGE_DAY_STEP:1} # Represent the number of days in the one minute/hour/day index.
    user: ${SW_ES_USER:"elastic"}
    password: ${SW_ES_PASSWORD:"es_password"}
```
### 问题2:对接原使用es后部分页面的数据查询无数据

出现了Integer无法转换String的java错误：

因为在使用虚拟机使用7.0.0版本打包好的程序包+同版本的ES的情况下为出现上述情况，考虑是官方镜像可能存在问题，使用

[http://gitlab.yundasys.com:8090/qianzhongjie2933/charts_all_2021/-/tree/master/skywalking_charts/images/oap-es7](http://gitlab.yundasys.com:8090/qianzhongjie2933/charts_all_2021/-/tree/master/skywalking_charts/images/oap-es7) 位置的文件打包后替换chart中的镜像，再部署就发现之前没有查询到数据的页面数据得到了。

### 云端部署配置：

oap的配置方面，延续了虚拟机部署时长期实践得出的，JVM16G进行配置，CPU限制为32核心。