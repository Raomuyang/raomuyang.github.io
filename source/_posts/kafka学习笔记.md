---
title: Kafka学习笔记 - 生产与消费
date: 2018-04-12 12:01:30
tags: [Java,Kafka]
meta: [Java, Kafka]
categories: [Java, Kafka]
---


![](http://cloud.atomicer.cn/blog-img/20180412/Image0.png)

<!-- more -->

## 命令行操作


### 创建一个主题

```
kafka-topics.sh --create --zookeeper localhost:2181 --replication-factor 1 --partitions 1 --topic test
```
`replication-fator`: broker的复制次数

### 生产者投入消息

```
kafka-console-producer.sh --broker-list localhost:9092 --topic test
```

### 消费者取消息

```
kafka-console-consumer.sh —bootstrap-server localhost:9092 --topic test --from-beginning
```

## Java SDK实践


### 生产者

#### 通过Properties配置KafkaProducer

基本配置包括：

* bootstrap.servers=localhost:9092
* value.serializer=org.apache.kafka.common.serialization.StringSerializer
* key.serializer=org.apache.kafka.common.serialization.StringSerializer  （可以自定义序列化工具）

#### 创建ProducerRecord
```java
Properties kafkaProfile = new Properties();
try (InputStream inputStream = ProducerTest.class.getResourceAsStream("/producer.properties")) {
    kafkaProfile.load(inputStream);
}

KafkaProducer<String, String>  producer = new KafkaProducer<>(kafkaProfile);
ProducerRecord<String, String> record = new ProducerRecord<>(
        "test", "Test product2", "product-2" + new Random(100).nextDouble());
Future<RecordMetadata> future = producer.send(record);
RecordMetadata metadata = future.get();
System.out.println(record.value() + " : " + metadata.partition());
```

#### 同步或异步发送消息


### 消费者

#### 通过Properties配置KafkaConsumer
基本配置包括
* bootstrap.servers=localhost:9092
* group.id=TestGroup
* key.deserializer=org.apache.kafka.common.serialization.StringDeserializer
* value.deserializer=org.apache.kafka.common.serialization.StringDeserializer

如果不加入group，kafka不能进行balance，Consumer宕机时，kafka不能Rebalance

#### 通过poll取消息

```java
try {

    while (true) {
        ConsumerRecords<String, String> records = consumer.poll(100);
        records.forEach(record -> System.out.println(String.format(
                "topic: %s, value: %s, partition: %s, offset: %s",
                record.topic(), record.value(),
                record.partition(), record.offset())));
    }
} finally {
    consumer.close();
}
```

在同一个组中的如果起了多个Consumer，而主题分区数小于Consumer数量，那么多余的Consumer也会被闲置:
  比如起了两个Consumer订阅同一个主题，主题分区只有一个，那么只有一个消费者和主题的分区绑定并订阅新到且未被读取的消息；当这个Consumer挂掉时，等待一段时间后，协调者会协调另一个消费者会开始从kafka中读取消息

多个group订阅了topic时，topic的动态会同时发送给多个group；在不选择seek到指定的offset时，会从订阅那一刻之后的消息开始poll

##### 疑惑：为什么提交错误的offset并不能导致异常，所有的消息都能够正常地poll

```Java
while (true) {
    ConsumerRecords<String, String> records = consumer.poll(1);
    records.forEach(record -> {
        System.out.println(String.format(
            "topic: %s, value: %s, partition: %s, offset: %s",
            record.topic(), record.value(), record.partition(), record.offset()));
        currentOffsets.put(
                    new TopicPartition(record.topic(), record.partition()),
                    new OffsetAndMetadata(record.offset() + 10, "None"))
            ;
        consumer.commitSync(currentOffsets);
    });

}
```

在书中（Kafka权威指南）可以找到答案：

![](http://cloud.atomicer.cn/blog-img/20180412/Image1.png)

* 第一个分区正常poll，但是始终设置offset为1 (关闭自动提交： enable.atuo.commit=false)
![](http://cloud.atomicer.cn/blog-img/20180412/Image2.png)

* 第二个Consumer接管后，从offset处开始读取
![](http://cloud.atomicer.cn/blog-img/20180412/Image3.png)

#### Seek
```java
consumer.poll(1);
consumer.seekToBeginning(Collections.singleton(new TopicPartition("test", 0)));
```

##### 探索：consumer.subscribe并不会真正地订阅，只有poll请求发出时才自动订阅，否则会抛出异常

![](http://cloud.atomicer.cn/blog-img/20180412/Image4.png)

#### 再均衡监听器 ( ConsumerRebalanceListener )

绑定再均衡监听器，可以在分配分区后和再均衡前执行特点的任务，比如在再均衡前提交已处理的offset

##### onPartitionsRevoked
再均衡时调用 ->      [  停止读取数据之后 -   再均衡之前  )
再均衡时可能失去对分区的所有权，此时应该确保提交offset

##### onPartitionsAssigned
再均衡时调用 ->      [  再均衡之后 - 读取数据之前  )

#### 通过weakup退出consumer
