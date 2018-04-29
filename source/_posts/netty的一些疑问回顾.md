---
title: Netty的一些问题回顾
date: 2018-02-04 09:35:20
tags: [Java,Netty]
meta: [Java, Netty]
categories: [Java, Netty]
---


1. 启动服务时，无所谓使用sync还是await，执行时语句都是非阻塞的，那么它们的意义是什么？
```
server.bind().await().channel().closeFuture().sync(); //这么做的意义是什么
```

> 都是阻塞当前线程，等待直到前面任务所在的线程结束。异步操作失败时，sync会抛出异常，而await()不会抛出异常，调用closeFuture().sync()之后，线程才会阻塞在当前的位置
<!-- more -->


2. 如果ServerBootstrap的线程设为1，所有的io事件到达时，动作的执行是线性的，如何通过异步的形式执行任务？

> 异步 + Listener？


3. 启动客户端连接服务时，无论sync()还是await()都不会阻塞当前语句，反而会影响向channel中writeAndFlush（不会有任何行为），倒是`closeFuture().sync()`可以使当前的连接阻塞在当前语句。并且，无论哪种写法，都会阻塞主线程的退出


```Java
future.sync().channel().writeAndFlush(); // 阻塞主线程
future.channel().closeFuture().sync()/.await(); // 都会阻塞在当前的语句


int port = 12345;

ChannelFuture clientFuture = new Bootstrap()
        .group(new NioEventLoopGroup())
        .handler(new DefaultInitializer())
        .channel(NioSocketChannel.class).connect("127.0.0.1", port);

Channel channel = clientFuture.channel();
channel.writeAndFlush(MessageEncoder.PING);
System.out.println("test");
channel.closeFuture().await();
System.out.println("finished”);
```

> future.sync().channel()是同步获取创建好连接之后的channel，连接失败时会抛出异常，而await后不会重新抛出异常 
> closeFuture()会等待连接关闭后关闭连接，


4. 以下代码注释了closeFuture().sync()，则group的shutdown时，若服务端的数据未返回，则客户端再也无法接受服务端返回的信息，会造成一种不调用closeFuture().sync()就无法接受数据的错觉

```java
       Bootstrap bootstrap = new Bootstrap();
        EventLoopGroup group = new NioEventLoopGroup(1);
        ChannelFuture future = bootstrap.group(group)
                .handler(new Initializer())
        .option(ChannelOption.SO_KEEPALIVE, true)
                .channel(NioSocketChannel.class)
                .connect("127.0.0.1", 12345);

        future.channel().writeAndFlush(MessageEncoder.PING);
//        future.channel().closeFuture().sync();
        group.shutdownGracefully();
```
   


5. 客户端建立连接之后，channelFuture.channel().writeAndFlush()为什么无法发送数据？

非同步，为什么需要等待连接完成之后才能写数据？将Thread.sleep注释之后，数据写进缓冲的数据为什么不会自动发送？

```java
//1
future = bootstrap.connect(host, port)
Thread.sleep(1000); //等待建立连接
future.channel().writeAndFlush(MessageEncoder.PING);

//2
future.sync().channel().writeAndFlush(MessageEncoder.PING);
```

6. 无论是Server还是Client，即使关闭所有的channel，仍然无法shutdown group，线程始终阻塞着

> [issue-7694](https://github.com/netty/netty/issues/7694) 这是4.1.20的bug，升级到4.1.21以上就行


7. 关于连接池，官方给出的用例如下，不需要担心并发的问题吗？：


```java
new AbstractChannelPoolMap<InetSocketAddress, FixedChannelPool>() {
    @Override
    protected FixedChannelPool newPool(InetSocketAddress key) {
        return new FixedChannelPool(bootstrap.remoteAddress(key), channelPoolHandler, maxConn);
    }
};
```
