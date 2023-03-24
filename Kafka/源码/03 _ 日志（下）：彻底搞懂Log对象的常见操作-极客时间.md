private def append(records: MemoryRecords,

origin: AppendOrigin,

interBrokerProtocolVersion: ApiVersion,

assignOffsets: Boolean,

leaderEpoch: Int): LogAppendInfo = {

maybeHandleIOException(s"Error while appending records to $topicPartition in dir ${dir.getParent}") {

val appendInfo = analyzeAndValidateRecords(records, origin)

if (appendInfo.shallowCount == 0)

return appendInfo

var validRecords = trimInvalidBytes(records, appendInfo)

lock synchronized {

checkIfMemoryMappedBufferClosed()

if (assignOffsets) {

val offset = new LongRef(nextOffsetMetadata.messageOffset)

appendInfo.firstOffset = Some(offset.value)

val now = time.milliseconds

val validateAndOffsetAssignResult = try {

LogValidator.validateMessagesAndAssignOffsets(validRecords,

topicPartition,

offset,

time,

now,

appendInfo.sourceCodec,

appendInfo.targetCodec,

config.compact,

config.messageFormatVersion.recordVersion.value,

config.messageTimestampType,

config.messageTimestampDifferenceMaxMs,

leaderEpoch,

origin,

interBrokerProtocolVersion,

brokerTopicStats)

} catch {

case e: IOException =>

throw 

 new KafkaException(s"Error validating messages while appending to log $name", e)

}

validRecords = validateAndOffsetAssignResult.validatedRecords

appendInfo.maxTimestamp = validateAndOffsetAssignResult.maxTimestamp

appendInfo.offsetOfMaxTimestamp = validateAndOffsetAssignResult.shallowOffsetOfMaxTimestamp

appendInfo.lastOffset = offset.value - 1

appendInfo.recordConversionStats = validateAndOffsetAssignResult.recordConversionStats

if (config.messageTimestampType == TimestampType.LOG\_APPEND\_TIME)

appendInfo.logAppendTime = now

if (validateAndOffsetAssignResult.messageSizeMaybeChanged) {

for (batch <- validRecords.batches.asScala) {

if (batch.sizeInBytes > config.maxMessageSize) {

brokerTopicStats.topicStats(topicPartition.topic).bytesRejectedRate.mark(records.sizeInBytes)

brokerTopicStats.allTopicsStats.bytesRejectedRate.mark(records.sizeInBytes)

throw 

 new RecordTooLargeException(s"Message batch size is ${batch.sizeInBytes} bytes in append to" +

s"partition $topicPartition which exceeds the maximum configured size of ${config.maxMessageSize}.")

}

}

}

} else {

if (!appendInfo.offsetsMonotonic)

throw 

 new OffsetsOutOfOrderException(s"Out of order offsets found in append to $topicPartition: " +

records.records.asScala.map(_.offset))

if (appendInfo.firstOrLastOffsetOfFirstBatch < nextOffsetMetadata.messageOffset) {

val firstOffset = appendInfo.firstOffset match {

case Some(offset) => offset

case None => records.batches.asScala.head.baseOffset()

}

val firstOrLast = if (appendInfo.firstOffset.isDefined) "First offset" 

 else 

 "Last offset of the first batch"

throw 

 new UnexpectedAppendOffsetException(

s"Unexpected offset in append to $topicPartition. $firstOrLast " +

s"${appendInfo.firstOrLastOffsetOfFirstBatch} is less than the next offset ${nextOffsetMetadata.messageOffset}. " +

s"First 10 offsets in append: ${records.records.asScala.take(10).map(_.offset)}, last offset in" +

s" append: ${appendInfo.lastOffset}. Log start offset = $logStartOffset",

firstOffset, appendInfo.lastOffset)

}

}

validRecords.batches.asScala.foreach { batch =>

if (batch.magic >= RecordBatch.MAGIC\_VALUE\_V2) {

maybeAssignEpochStartOffset(batch.partitionLeaderEpoch, batch.baseOffset)

} else {

leaderEpochCache.filter(_.nonEmpty).foreach { cache =>

warn(s"Clearing leader epoch cache after unexpected append with message format v${batch.magic}")

cache.clearAndFlush()

}

}

}

if (validRecords.sizeInBytes > config.segmentSize) {

throw 

 new RecordBatchTooLargeException(s"Message batch size is ${validRecords.sizeInBytes} bytes in append " +

s"to partition $topicPartition, which exceeds the maximum configured segment size of ${config.segmentSize}.")

}

val segment = maybeRoll(validRecords.sizeInBytes, appendInfo)

val logOffsetMetadata = LogOffsetMetadata(

messageOffset = appendInfo.firstOrLastOffsetOfFirstBatch,

segmentBaseOffset = segment.baseOffset,

relativePositionInSegment = segment.size)

val (updatedProducers, completedTxns, maybeDuplicate) = analyzeAndValidateProducerState(

logOffsetMetadata, validRecords, origin)

maybeDuplicate.foreach { duplicate =>

appendInfo.firstOffset = Some(duplicate.firstOffset)

appendInfo.lastOffset = duplicate.lastOffset

appendInfo.logAppendTime = duplicate.timestamp

appendInfo.logStartOffset = logStartOffset

return appendInfo

}

segment.append(largestOffset = appendInfo.lastOffset,

largestTimestamp = appendInfo.maxTimestamp,

shallowOffsetOfMaxTimestamp = appendInfo.offsetOfMaxTimestamp,

records = validRecords)

updateLogEndOffset(appendInfo.lastOffset + 1)

for (producerAppendInfo <- updatedProducers.values) {

producerStateManager.update(producerAppendInfo)

}

for (completedTxn <- completedTxns) {

val lastStableOffset = producerStateManager.lastStableOffset(completedTxn)

segment.updateTxnIndex(completedTxn, lastStableOffset)

producerStateManager.completeTxn(completedTxn)

}

producerStateManager.updateMapEndOffset(appendInfo.lastOffset + 1)

maybeIncrementFirstUnstableOffset()

trace(s"Appended message set with last offset: ${appendInfo.lastOffset}, " +

s"first offset: ${appendInfo.firstOffset}, " +

s"next offset: ${nextOffsetMetadata.messageOffset}, " +

s"and messages: $validRecords")

if (unflushedMessages >= config.flushInterval)

flush()

appendInfo

}

}

}