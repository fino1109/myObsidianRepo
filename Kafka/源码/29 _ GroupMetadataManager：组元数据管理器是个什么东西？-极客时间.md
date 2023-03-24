你好，我是胡夕。今天，我们学习 GroupMetadataManager 类的源码。从名字上来看，它是组元数据管理器，但是，从它提供的功能来看，我更愿意将它称作消费者组管理器，因为它定义的方法，提供的都是添加消费者组、移除组、查询组这样组级别的基础功能。

不过，这个类的知名度不像 KafkaController、GroupCoordinator 那么高，你之前可能都没有听说过它。但是，它其实是非常重要的消费者组管理类。

GroupMetadataManager 类是在消费者组 Coordinator 组件被创建时被实例化的。这就是说，每个 Broker 在启动过程中，都会创建并维持一个 GroupMetadataManager 实例，以实现对该 Broker 负责的消费者组进行管理。更重要的是，生产环境输出日志中的与消费者组相关的大多数信息，都和它息息相关。

我举一个简单的例子。你应该见过这样的日志输出：

Removed ××× expired offsets in ××× milliseconds.

这条日志每 10 分钟打印一次。你有没有想过，它为什么要这么操作呢？其实，这是由 GroupMetadataManager 类创建的定时任务引发的。如果你不清楚 GroupMetadataManager 的原理，虽然暂时不会影响你使用，但是，一旦你在实际环境中看到了有关消费者组的错误日志，仅凭日志输出，你是无法定位错误原因的。要解决这个问题，就只有一个办法：通过阅读源码，彻底搞懂底层实现原理，做到以不变应万变。

关于这个类，最重要的就是要掌握它是如何管理消费者组的，以及它对内部位移主题的操作方法。这两个都是重磅功能，我们必须要吃透它们的原理，这也是我们这三节课的学习重点。今天，我们先学习它的类定义和管理消费者组的方法。

## 类定义与字段

GroupMetadataManager 类定义在 coordinator.group 包下的同名 scala 文件中。这个类的代码将近 1000 行，逐行分析的话，显然效率不高，也没有必要。所以，我从类定义和字段、重要方法两个维度给出主要逻辑的代码分析。下面的代码是该类的定义，以及我选取的重要字段信息。

class 

 GroupMetadataManager(

brokerId: Int,

interBrokerProtocolVersion: ApiVersion,

config: OffsetConfig,

replicaManager: ReplicaManager,

zkClient: KafkaZkClient,

time: Time,

metrics: Metrics) extends Logging with KafkaMetricsGroup {

private val compressionType: CompressionType = CompressionType.forId(config.offsetsTopicCompressionCodec.codec)

private val groupMetadataCache = new Pool\[String, GroupMetadata\]

private val loadingPartitions: mutable.Set\[Int\] = mutable.Set()

private val ownedPartitions: mutable.Set\[Int\] = mutable.Set()

private val groupMetadataTopicPartitionCount = getGroupMetadataTopicPartitionCount

......

}

这个类的构造函数需要 7 个参数，后面的 time 和 metrics 只是起辅助作用，因此，我重点解释一下前 5 个参数的含义。

brokerId：这个参数我们已经无比熟悉了。它是所在 Broker 的 ID 值，也就是 broker.id 参数值。

interBrokerProtocolVersion：保存 Broker 间通讯使用的请求版本。它是 Broker 端参数 inter.broker.protocol.version 值。这个参数的主要用途是确定位移主题消息格式的版本。

config：这是一个 OffsetConfig 类型。该类型定义了与位移管理相关的重要参数，比如位移主题日志段大小设置、位移主题备份因子、位移主题分区数配置等。

replicaManager：副本管理器类。GroupMetadataManager 类使用该字段实现获取分区对象、日志对象以及写入分区消息的目的。

zkClient：ZooKeeper 客户端。该类中的此字段只有一个目的：从 ZooKeeper 中获取位移主题的分区数。

除了构造函数所需的字段，该类还定义了其他关键字段，我给你介绍几个非常重要的。

1.compressionType

压缩器类型。Kafka 向位移主题写入消息前，可以选择对消息执行压缩操作。是否压缩，取决于 Broker 端参数 offsets.topic.compression.codec 值，默认是不进行压缩。如果你的位移主题占用的磁盘空间比较多的话，可以考虑启用压缩，以节省资源。

2.groupMetadataCache

该字段是 GroupMetadataManager 类上最重要的属性，它保存这个 Broker 上 GroupCoordinator 组件管理的所有消费者组元数据。它的 Key 是消费者组名称，Value 是消费者组元数据，也就是 GroupMetadata。源码通过该字段实现对消费者组的添加、删除和遍历操作。

3.loadingPartitions

位移主题下正在执行加载操作的分区号集合。这里需要注意两点：首先，这些分区都是位移主题分区，也就是 \_\_consumer\_offsets 主题下的分区；其次，所谓的加载，是指读取位移主题消息数据，填充 GroupMetadataCache 字段的操作。

4.ownedPartitions

位移主题下完成加载操作的分区号集合。与 loadingPartitions 类似的是，该字段保存的分区也是位移主题下的分区。和 loadingPartitions 不同的是，它保存的分区都是已经完成加载操作的分区。

5.groupMetadataTopicPartitionCount

位移主题的分区数。它是 Broker 端参数 offsets.topic.num.partitions 的值，默认是 50 个分区。若要修改分区数，除了变更该参数值之外，你也可以手动创建位移主题，并指定不同的分区数。

在这些字段中，groupMetadataCache 是最重要的，GroupMetadataManager 类大量使用该字段实现对消费者组的管理。接下来，我们就重点学习一下该类是如何管理消费者组的。

## 重要方法

管理消费者组包含两个方面，对消费者组元数据的管理以及对消费者组位移的管理。组元数据和组位移都是 Coordinator 端重要的消费者组管理对象。

## 消费者组元数据管理

消费者组元数据管理分为查询获取组信息、添加组、移除组和加载组信息。从代码复杂度来讲，查询获取、移除和添加的逻辑相对简单，加载的过程稍微费事些。我们先说说查询获取。

### 查询获取消费者组元数据

GroupMetadataManager 类中查询及获取组数据的方法有很多。大多逻辑简单，你一看就能明白，比如下面的 getGroup 方法和 getOrMaybeCreateGroup 方法：

def getGroup(groupId: String): Option\[GroupMetadata\] = {

Option(groupMetadataCache.get(groupId))

}

def getOrMaybeCreateGroup(groupId: String, createIfNotExist: Boolean): Option\[GroupMetadata\] = {

if (createIfNotExist)

Option(groupMetadataCache.getAndMaybePut(groupId, new 

 GroupMetadata(groupId, Empty, time)))

else

Option(groupMetadataCache.get(groupId))

}

GroupMetadataManager 类的上层组件 GroupCoordinator 会大量使用这两个方法来获取给定消费者组的数据。这两个方法都会返回给定消费者组的元数据信息，但是它们之间是有区别的。

对于 getGroup 方法而言，如果该组信息不存在，就返回 None，而这通常表明，消费者组确实不存在，或者是，该组对应的 Coordinator 组件变更到其他 Broker 上了。

而对于 getOrMaybeCreateGroup 方法而言，若组信息不存在，就根据 createIfNotExist 参数值决定是否需要添加该消费者组。而且，getOrMaybeCreateGroup 方法是在消费者组第一个成员加入组时被调用的，用于把组创建出来。

在 GroupMetadataManager 类中，还有一些地方也散落着组查询获取的逻辑。不过它们与这两个方法中的代码大同小异，很容易理解，课下你可以自己阅读下。

### 移除消费者组元数据

接下来，我们看下如何移除消费者组信息。当 Broker 卸任某些消费者组的 Coordinator 角色时，它需要将这些消费者组从 groupMetadataCache 中全部移除掉，这就是 removeGroupsForPartition 方法要做的事情。我们看下它的源码：

def removeGroupsForPartition(offsetsPartition: Int,

onGroupUnloaded: GroupMetadata => Unit): Unit = {

val topicPartition = new TopicPartition(Topic.GROUP\_METADATA\_TOPIC_NAME, offsetsPartition)

info(s"Scheduling unloading of offsets and group metadata from $topicPartition")

scheduler.schedule(topicPartition.toString, () => removeGroupsAndOffsets)

def removeGroupsAndOffsets(): Unit = {

var numOffsetsRemoved = 0

var numGroupsRemoved = 0

inLock(partitionLock) {

ownedPartitions.remove(offsetsPartition)

for (group <- groupMetadataCache.values) {

if (partitionFor(group.groupId) == offsetsPartition) {

onGroupUnloaded(group)

groupMetadataCache.remove(group.groupId, group)

removeGroupFromAllProducers(group.groupId)

numGroupsRemoved += 1

numOffsetsRemoved += group.numOffsets

}

}

}

info(s"Finished unloading $topicPartition. Removed $numOffsetsRemoved cached offsets " +

s"and $numGroupsRemoved cached groups.")

}

}

该方法的主要逻辑是，先定义一个内部方法 removeGroupsAndOffsets，然后创建一个异步任务，调用该方法来执行移除消费者组信息和位移信息。

那么，怎么判断要移除哪些消费者组呢？这里的依据就是传入的位移主题分区。每个消费者组及其位移的数据，都只会保存在位移主题的一个分区下。一旦给定了位移主题分区，那么，元数据保存在这个位移主题分区下的消费者组就要被移除掉。removeGroupsForPartition 方法传入的 offsetsPartition 参数，表示 Leader 发生变更的位移主题分区，因此，这些分区保存的消费者组都要从该 Broker 上移除掉。

具体的执行逻辑是什么呢？我来解释一下。

首先，异步任务从 ownedPartitions 中移除给定位移主题分区。

其次，遍历消费者组元数据缓存中的所有消费者组对象，如果消费者组正是在给定位移主题分区下保存的，就依次执行下面的步骤。

第 1 步，调用 onGroupUnloaded 方法执行组卸载逻辑。这个方法的逻辑是上层组件 GroupCoordinator 传过来的。它主要做两件事情：将消费者组状态变更到 Dead 状态；封装异常表示 Coordinator 已发生变更，然后调用回调函数返回。

第 2 步，把消费者组信息从 groupMetadataCache 中移除。这一步非常关键，目的是彻底清除掉该组的“痕迹”。

第 3 步，把消费者组从 producer 对应的组集合中移除。这里的 producer，是给 Kafka 事务用的。

第 4 步，增加已移除组计数器。

第 5 步，更新已移除位移值计数器。

到这里，方法结束。

### 添加消费者组元数据

下面，我们学习添加消费者组的管理方法，即 addGroup。它特别简单，仅仅是调用 putIfNotExists 将给定组添加进 groupMetadataCache 中而已。代码如下：

def addGroup(group: GroupMetadata): GroupMetadata = {

val 

 currentGroup 

 = groupMetadataCache.putIfNotExists(group.groupId, group)

if (currentGroup != null) {

currentGroup

} else {

group

}

}

### 加载消费者组元数据

现在轮到相对复杂的加载消费者组了。GroupMetadataManager 类中定义了一个 loadGroup 方法执行对应的加载过程。

private def loadGroup(

group: GroupMetadata, offsets: Map\[TopicPartition, CommitRecordMetadataAndOffset\],

pendingTransactionalOffsets: Map\[Long, mutable.Map\[TopicPartition, CommitRecordMetadataAndOffset\]\]): Unit = {

trace(s"Initialized offsets $offsets for group ${group.groupId}")

group.initializeOffsets(offsets, pendingTransactionalOffsets.toMap)

val currentGroup = addGroup(group)

if (group != currentGroup)

debug(s"Attempt to load group ${group.groupId} from log with generation ${group.generationId} failed " +

s"because there is already a cached group with generation ${currentGroup.generationId}")

}

该方法的逻辑有两步。

第 1 步，通过 initializeOffsets 方法，将位移值添加到 offsets 字段标识的消费者组提交位移元数据中，实现加载消费者组订阅分区提交位移的目的。

第 2 步，调用 addGroup 方法，将该消费者组元数据对象添加进消费者组元数据缓存，实现加载消费者组元数据的目的。

## 消费者组位移管理

除了消费者组的管理，GroupMetadataManager 类的另一大类功能，是提供消费者组位移的管理，主要包括位移数据的保存和查询。我们总说，位移主题是保存消费者组位移信息的地方。实际上，当消费者组程序在查询位移时，Kafka 总是从内存中的位移缓存数据查询，而不会直接读取底层的位移主题数据。

### 保存消费者组位移

storeOffsets 方法负责保存消费者组位移。该方法的代码很长，我先画一张图来展示下它的完整流程，帮助你建立起对这个方法的整体认知。接下来，我们再从它的方法签名和具体代码两个维度，来具体了解一下它的执行逻辑。

![[76116b323c0c7b024ebe95c3c08e6ae6_efb70503e8254a48b.jpg]]

我先给你解释一下保存消费者组位移的全部流程。

首先，storeOffsets 方法要过滤出满足特定条件的待保存位移信息。是否满足特定条件，要看 validateOffsetMetadataLength 方法的返回值。这里的特定条件，是指位移提交记录中的自定义数据大小，要小于 Broker 端参数 offset.metadata.max.bytes 的值，默认值是 4KB。

如果没有一个分区满足条件，就构造 OFFSET\_METADATA\_TOO_LARGE 异常，并调用回调函数。这里的回调函数执行发送位移提交 Response 的动作。

倘若有分区满足了条件，接下来，方法会判断当前 Broker 是不是该消费者组的 Coordinator，如果不是的话，就构造 NOT_COORDINATOR 异常，并提交给回调函数；如果是的话，就构造位移主题消息，并将消息写入进位移主题下。

然后，调用一个名为 putCacheCallback 的内置方法，填充 groupMetadataCache 中各个消费者组元数据中的位移值，最后，调用回调函数返回。

接下来，我们结合代码来查看下 storeOffsets 方法的实现逻辑。

首先我们看下它的方法签名。既然是保存消费者组提交位移的，那么，我们就要知道上层调用方都给这个方法传入了哪些参数。

def storeOffsets(

group: GroupMetadata,

consumerId: String,

offsetMetadata: immutable.Map\[TopicPartition, OffsetAndMetadata\],

responseCallback: immutable.Map\[TopicPartition, Errors\] => Unit,

producerId: Long = RecordBatch.NO\_PRODUCER\_ID,

producerEpoch: Short = RecordBatch.NO\_PRODUCER\_EPOCH): Unit = {

......

}

这个方法接收 6 个参数，它们的含义我都用注释的方式标注出来了。producerId 和 producerEpoch 这两个参数是与 Kafka 事务相关的，你简单了解下就行。我们要重点掌握前面 4 个参数的含义。

group：消费者组元数据信息。该字段的类型就是我们之前学到的 GroupMetadata 类。

consumerId：消费者组成员 ID，仅用于 DEBUG 调试。

offsetMetadata：待保存的位移值，按照分区分组。

responseCallback：位移保存完成后需要执行的回调函数。

接下来，我们看下 storeOffsets 的代码。为了便于你理解，我删除了与 Kafka 事务操作相关的部分。

val 

 filteredOffsetMetadata 

 = offsetMetadata.filter { case (_, offsetAndMetadata) =>

validateOffsetMetadataLength(offsetAndMetadata.metadata)

}

......

val 

 isTxnOffsetCommit 

 = producerId != RecordBatch.NO\_PRODUCER\_ID

if (filteredOffsetMetadata.isEmpty) {

val 

 commitStatus 

 = offsetMetadata.map { case (k, _) => k -> Errors.OFFSET\_METADATA\_TOO_LARGE }

responseCallback(commitStatus)

None

} else {

getMagic(partitionFor(group.groupId)) match {

case 

 Some(magicValue) =>

val 

 timestampType 

 = TimestampType.CREATE_TIME

val 

 timestamp 

 = time.milliseconds()

val 

 records 

 = filteredOffsetMetadata.map { case (topicPartition, offsetAndMetadata) =>

val 

 key 

 = GroupMetadataManager.offsetCommitKey(group.groupId, topicPartition)

val 

 value 

 = GroupMetadataManager.offsetCommitValue(offsetAndMetadata, interBrokerProtocolVersion)

new 

 SimpleRecord(timestamp, key, value)

}

val 

 offsetTopicPartition 

 = 

 new 

 TopicPartition(Topic.GROUP\_METADATA\_TOPIC_NAME, partitionFor(group.groupId))

val 

 buffer 

 = ByteBuffer.allocate(AbstractRecords.estimateSizeInBytes(magicValue, compressionType, records.asJava))

if (isTxnOffsetCommit && magicValue < RecordBatch.MAGIC\_VALUE\_V2)

throw Errors.UNSUPPORTED\_FOR\_MESSAGE_FORMAT.exception("Attempting to make a transaction offset commit with an invalid magic: " \+ magicValue)

val 

 builder 

 = MemoryRecords.builder(buffer, magicValue, compressionType, timestampType, 0L, time.milliseconds(),

producerId, producerEpoch, 0, isTxnOffsetCommit, RecordBatch.NO\_PARTITION\_LEADER_EPOCH)

records.foreach(builder.append)

val 

 entries 

 = Map(offsetTopicPartition -> builder.build())

if (isTxnOffsetCommit) {

......

} else {

group.inLock {

group.prepareOffsetCommit(offsetMetadata)

}

}

appendForGroup(group, entries, putCacheCallback)

case 

 None 

 =>

val 

 commitStatus 

 = offsetMetadata.map {

case (topicPartition, _) =>

(topicPartition, Errors.NOT_COORDINATOR)

}

responseCallback(commitStatus)

None

}

}

我为方法的关键步骤都标注了注释，具体流程前面我也介绍过了，应该很容易理解。不过，这里还需要注意两点，也就是 appendForGroup 和 putCacheCallback 方法。前者是向位移主题写入消息；后者是填充元数据缓存的。我们结合代码来学习下。

appendForGroup 方法负责写入消息到位移主题，同时传入 putCacheCallback 方法，更新消费者元数据。以下是它的代码：

private def appendForGroup(

group: GroupMetadata,

records: Map\[TopicPartition, MemoryRecords\],

callback: Map\[TopicPartition, PartitionResponse\] => Unit): Unit = {

replicaManager.appendRecords(

timeout = config.offsetCommitTimeoutMs.toLong,

requiredAcks = config.offsetCommitRequiredAcks,

internalTopicsAllowed = true,

origin = AppendOrigin.Coordinator,

entriesPerPartition = records,

delayedProduceLock = Some(group.lock),

responseCallback = callback)

}

可以看到，该方法就是调用 ReplicaManager 的 appendRecords 方法，将消息写入到位移主题中。

下面，我们再关注一下 putCacheCallback 方法的实现，也就是将写入的位移值填充到缓存中。我先画一张图来展示下 putCacheCallback 的逻辑。

![[bc2fcf199a685a5cc6d32846c53c3042_006f77078562443eb.jpg]]

现在，我们结合代码，学习下它的逻辑实现。

def putCacheCallback(responseStatus: Map\[TopicPartition, PartitionResponse\]): Unit = {

if (responseStatus.size != 1 || !responseStatus.contains(offsetTopicPartition))

throw 

 new IllegalStateException("Append status %s should only have one partition %s"

.format(responseStatus, offsetTopicPartition))

offsetCommitsSensor.record(records.size)

val status = responseStatus(offsetTopicPartition)

val responseError = group.inLock {

if (status.error == Errors.NONE) {

if (!group.is(Dead)) {

filteredOffsetMetadata.foreach { case (topicPartition, offsetAndMetadata) =>

if (isTxnOffsetCommit)

......

else

group.onOffsetCommitAppend(topicPartition, CommitRecordMetadataAndOffset(Some(status.baseOffset), offsetAndMetadata))

}

}

Errors.NONE

} else {

if (!group.is(Dead)) {

......

filteredOffsetMetadata.foreach { case (topicPartition, offsetAndMetadata) =>

if (isTxnOffsetCommit)

group.failPendingTxnOffsetCommit(producerId, topicPartition)

else

group.failPendingOffsetWrite(topicPartition, offsetAndMetadata)

}

}

......

status.error match {

case Errors.UNKNOWN\_TOPIC\_OR_PARTITION

| Errors.NOT\_ENOUGH\_REPLICAS

| Errors.NOT\_ENOUGH\_REPLICAS\_AFTER\_APPEND =>

Errors.COORDINATOR\_NOT\_AVAILABLE

case Errors.NOT\_LEADER\_FOR_PARTITION

| Errors.KAFKA\_STORAGE\_ERROR =>

Errors.NOT_COORDINATOR

case Errors.MESSAGE\_TOO\_LARGE

| Errors.RECORD\_LIST\_TOO_LARGE

| Errors.INVALID\_FETCH\_SIZE =>

Errors.INVALID\_COMMIT\_OFFSET_SIZE

case other => other

}

}

}

val commitStatus = offsetMetadata.map { case (topicPartition, offsetAndMetadata) =>

if (validateOffsetMetadataLength(offsetAndMetadata.metadata))

(topicPartition, responseError)

else

(topicPartition, Errors.OFFSET\_METADATA\_TOO_LARGE)

}

responseCallback(commitStatus)

}

putCacheCallback 方法的主要目的，是将多个消费者组位移值填充到 GroupMetadata 的 offsets 元数据缓存中。

首先，该方法要确保位移消息写入到指定位移主题分区，否则就抛出异常。

之后，更新已提交位移数指标，然后判断写入结果是否有错误。

如果没有错误，只要组状态不是 Dead 状态，就调用 GroupMetadata 的 onOffsetCommitAppend 方法填充元数据。onOffsetCommitAppend 方法的主体逻辑，是将消费者组订阅分区的位移值写入到 offsets 字段保存的集合中。当然，如果状态是 Dead，则什么都不做。

如果刚才的写入结果有错误，那么，就通过 failPendingOffsetWrite 方法取消未完成的位移消息写入。

接下来，代码要将日志写入的异常类型转换成表征提交状态错误的异常类型。具体来说，就是将 UNKNOWN\_TOPIC\_OR\_PARTITION、NOT\_LEADER\_FOR\_PARTITION 和 MESSAGE\_TOO\_LARGE 这样的异常，转换到 COORDINATOR\_NOT\_AVAILABLE 和 NOT_COORDINATOR 这样的异常。之后，再将这些转换后的异常封装进 commitStatus 字段中传给回调函数。

最后，调用回调函数返回。至此，方法结束。

好了，保存消费者组位移信息的 storeOffsets 方法，我们就学完了，它的关键逻辑，是构造位移主题消息并写入到位移主题，然后将位移值填充到消费者组元数据中。

### 查询消费者组位移

现在，我再说说查询消费者组位移，也就是 getOffsets 方法的代码实现。比起 storeOffsets，这个方法要更容易理解。我们看下它的源码：

def getOffsets(

groupId: String,

requireStable: Boolean,

topicPartitionsOpt: Option\[Seq\[TopicPartition\]\]): Map\[TopicPartition, PartitionData\] = {

......

val group = groupMetadataCache.get(groupId)

if (group == null) {

topicPartitionsOpt.getOrElse(Seq.empty\[TopicPartition\]).map { topicPartition =>

val partitionData = new PartitionData(OffsetFetchResponse.INVALID_OFFSET,

Optional.empty(), "", Errors.NONE)

topicPartition -> partitionData

}.toMap

} else {

group.inLock {

if (group.is(Dead)) {

topicPartitionsOpt.getOrElse(Seq.empty\[TopicPartition\]).map { topicPartition =>

val partitionData = new PartitionData(OffsetFetchResponse.INVALID_OFFSET,

Optional.empty(), "", Errors.NONE)

topicPartition -> partitionData

}.toMap

} else {

val topicPartitions = topicPartitionsOpt.getOrElse(group.allOffsets.keySet)

topicPartitions.map { topicPartition =>

if (requireStable && group.hasPendingOffsetCommitsForTopicPartition(topicPartition)) {

topicPartition -> new PartitionData(OffsetFetchResponse.INVALID_OFFSET,

Optional.empty(), "", Errors.UNSTABLE\_OFFSET\_COMMIT)

} else {

val partitionData = group.offset(topicPartition) match {

case None =>

new PartitionData(OffsetFetchResponse.INVALID_OFFSET,

Optional.empty(), "", Errors.NONE)

case Some(offsetAndMetadata) =>

new PartitionData(offsetAndMetadata.offset,

offsetAndMetadata.leaderEpoch, offsetAndMetadata.metadata, Errors.NONE)

}

topicPartition -> partitionData

}

}.toMap

}

}

}

}

getOffsets 方法首先会读取 groupMetadataCache 中的组元数据，如果不存在对应的记录，则返回空数据集，如果存在，就接着判断组是否处于 Dead 状态。

如果是 Dead 状态，就说明消费者组已经被销毁了，位移数据也被视为不可用了，依然返回空数据集；若状态不是 Dead，就提取出消费者组订阅的分区信息，再依次为它们获取对应的位移数据并返回。至此，方法结束。

## 总结

今天，我们学习了 GroupMetadataManager 类的源码。作为消费者组管理器，它负责管理消费者组的方方面面。其中，非常重要的两个管理功能是消费者组元数据管理和消费者组位移管理，分别包括查询获取、移除、添加和加载消费者组元数据，以及保存和查询消费者组位移，这些方法是上层组件 GroupCoordinator 倚重的重量级功能载体，你一定要彻底掌握它们。

我画了一张思维导图，帮助你复习一下今天的重点内容。

![[eb8fe45e1d152e2ac9cb52c81390265a_2bfc272e2c6b45c6b.jpg]]

实际上，GroupMetadataManager 类的地位举足轻重。虽然它在 Coordinator 组件中不显山不露水，但却是一些线上问题的根源所在。

我再跟你分享一个小案例。

之前，我碰到过一个问题：在消费者组成员超多的情况下，无法完成位移加载，这导致 Consumer 端总是接收到 Marking the coordinator dead 的错误。

当时，我查遍各种资料，都无法定位问题，最终，还是通过阅读源码，发现是这个类的 doLoadGroupsAndOffsets 方法中创建的 buffer 过小导致的。后来，通过调大 offsets.load.buffer.size 参数值，我们顺利地解决了问题。

试想一下，如果当时没有阅读这部分的源码，仅凭日志，我们肯定无法解决这个问题。因此，我们花三节课的时间，专门阅读 GroupMetadataManager 类源码，是非常值得的。下节课，我将带你继续研读 GroupMetadataManager 源码，去探寻有关位移主题的那些代码片段。

## 课后讨论

请思考这样一个问题：在什么场景下，需要移除 GroupMetadataManager 中保存的消费者组记录？

欢迎在留言区写下你的思考和答案，跟我交流讨论，也欢迎你把今天的内容分享给你的朋友。