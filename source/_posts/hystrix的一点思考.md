---
title: Hystrix的一点思考
date: 2018-11-02 14:05:21
tags: [Java,hystrix]
meta: [Java, hystrix]
categories: [Java, hystrix]
---

![](http://cloud.atomicer.cn/blog-img/201801102/Image1.png)

<!-- more -->


### 对于一些非幂等的请求，若hystrix设置的超时时间过短，请求被中断，但操作实际已经执行？

就像SEQFLOW的相关服务一样，通过API访问DataManager/Auth/ComputerSystem等服务时，可能会碰到一些内部错误导致请求已经执行，但是API因某些异常返回500给客户端。最典型的是上传文件之后的callback操作（post），客户端上传完成时执行callback，DataManager执行确认操作之后返回200给API，API层意外地返回500给客户端，此时客户端无法简单地重试，只能尝试先判断状态再决定下一步是重试还是跳过。

### 关于请求合并器

* get: `/users/{userid}`
* get: `/users/?ids={id-list}`

![](http://cloud.atomicer.cn/blog-img/20181102/Image2.png)


多个客户端同时通userid查询时，负载均衡服务要是一个一个地请求第一个接口，势必造成资源的消耗，若能够将一段时间内的请合并发送，再将返回值在本地处理分别返回给每个客户端，就可以节约请求的资源或查询的次数.

hystirx提供了这个功能，我觉得，要使用这个特性还需要一定的场景支持