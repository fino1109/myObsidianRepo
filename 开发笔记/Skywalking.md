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