---
title: '从理解volatile的内存语义实现到Java的锁实现的思考'
date: 2016-11-11 12:59:54
tags: [Java, 并发, JMM]
categories: Java
meta: [volatile的内存语义, 内存模型介绍]
---
`volatile`**关键字**:　使用`volatile`关键字修饰的的变量，总能“看到”任意线程对它最后的写入，即总能保证任意线程在读写volatile修饰的变量时，总是从内存中读取最新的值。以下是volatile在内存中的语义实现及同步的原理。


##### 一：接触内存模型
Java中的实例、静态变量以及数组都存储在堆内存中，可在线程之间共享。而Java进程间通信由Java内存模型（JMM）控制，JMM可以决定共享变量的写入何时对另一个线程可见。（从JDK5开始，Java使用JSR-133内存模型，从该规定开始，即使是在32位的机器上，一个64位的double/long的读操作也必须满足原子性）
<!--more-->
![Java内存模型示意图](http://cloud.atomicer.cn/blog-img/20161113/20161112234833.jpg)  
<!-- ![Java内存模型示意图](/blog-img/20161113/20161112234833.jpg) -->
[图1.1]  
本地内存是JMM抽象的一个概念

##### 二：顺序一致性与重排序
从我学习编程语言开始，所认知的是“程序顺序执行”。然而，顺序一致性只是一种理想模型。从源代码到机器指令的这一过程中，编译器和处理器往往会对指令做一些重排序从而提高性能，但是重排序会依据一个标准：
* 不改变单线程程序语义
* 不影响数据依赖。

###### happens-before
如果一个操作的执行结果需要对另一个操作可见，则两个操作之间满足happens-before关系。happens-before具有传递性  
*对于一个volatile变量的写操作，happens-before于任意后续对这个变量的读*

###### as-if-serial
as-if-serial规定，如果操作直接存在数据依赖关系，则不允许重排序。不管怎么重排序，都必须遵守as-if-serial语义。
```Java
int a = 1;         //(1)
int b = 2;         //(2)
int c = a + b;     //(3)
```
上面的代码中，(1)(2)之间不存在以来和happens-before关系，可以重排序，而(1)(3)和(2)(3)之间都存在as-if-serial关系，不能重排序  

> as-if-serial保护单线程程程序的语义正确性，使我们无需担心重排序对我们的影响，也使我们产生一种错觉：单线程程序就是顺序执行的。

>**拓展资料**--重排序的三种类型：   
 　(1)编译器优化重排序  
 　(2)指令集并行重排序  
 　(3)内存系统的重排序  

##### 三：多线程与重排序的思考
我们将happens-before和as-if-serial的关系引入到多线程中。我们可以将多线程的所有操作想象成在时间轴上的顺序执行的单线程程序。(以下流程图使用Markdown语法绘制，有些地方不支持)

###### 互不干涉的并发
在多线程的程序中，假如线程相互之间不涉及共享的变量，亦即互相不干涉，则两个线程之间既没有happens-before的关系，也没有as-if-serial语义的约束，所以各个线程之间操作可以任意合并重排序：
* 线程A的执行流程
```flow
st=>start: 线程A
op1=>operation: op-a-1
op2=>operation: op-a-2
op3=>operation: op-a-3
e=>end
st->op1->op2->op3->e
```

* 线程B的执行流程
```flow
st=>start: 线程B
op1=>operation: op-b-1
op2=>operation: op-b-2
op3=>operation: op-b-3
e=>end
st->op1->op2->op3->e
```

* 并发的可能的执行顺序
```flow
st=>start: 重排序
op1=>operation: op-a-1
op2=>operation: op-b-1
op3=>operation: op-b-2
op4=>operation: op-a-2
op5=>operation: op-a-3
op6=>operation: op-b-3
e=>end
st->op1->op2->op3->op4->op5->op6->e
```

###### 共享变量的并发
当线程之间涉及到共享变量时，涉及到了线程之间的通信，即如图1.1所示，此时并发所存在的问题（脏读、幻读、不可重复读）明显可见，但是，如果线程没有正确地同步（通信），线程之间无法明确共享变量何时被写入。因为此时所面对的问题就如将线程合并到时间轴上和重排序后是否违反happens-before和as-if-serial的语义了：

* 线程A
```flow
st=>start: 线程A
op1=>operation: a读共享变量x
op2=>operation: a写共享变量x
e=>end
st->op1->op2->e
```

* 线程B
```flow
st=>start: 线程B
op1=>operation: b读共享变量x
op2=>operation: b写共享变量x
e=>end
st->op1->op2->e
```

* 假如不同步，程序可能的执行顺序
```flow
st=>start: 重排序
op1=>operation: a读共享变量x
op2=>operation: b写共享变量x
op3=>operation: b读共享变量x
op4=>operation: a写共享变量x
e=>end
st->op1->op2->op3->op4->e
```
上面的程序执行顺序很显然有脏读的问题，而程序并发执行的正确语义应该有如下两种：
  * a读共享变量x happens-before a写共享变量x，a写共享变量x happens-before b读共享变量x， b读共享变量x happens-before b写共享变量x
  * b读共享变量x happens-before b写共享变量x，b写共享变量x happens-before a读共享变量x，a读共享变量x happens-before a写共享变量x  

所以，为程序保证并发操作的正确性，多线程对共享变量的非原子操作上，必须采用有效的通信方式来使其对共享变量的操作对其它线程可见，这就引入了volatile同步方式。

##### 四：从volatile的内存语义到锁

JMM通过在指令序列中插入内存屏障来限制编译器的指令重排序，实现volatile的内存语义

###### JSR-133中，对于volatile变量写的内存屏障插入策略

-|----------------------
* 普通读  
* 普通写  

-|----------------------
* StoreStore屏障：*禁止前面的普通写和volatile写重排序，保证前面的普通变量写从本地内存缓存刷新到主存中*  
* `volatile写 `
* StoreLoad屏障：*防止volatile写和下面有可能出现的volatile读发生重排序*  

-|----------------------  



###### JSR-133中，对于volatile变量读的内存屏障插入策略

-|----------------------
* `volatile读`
* LoadLoad屏障：*禁止下面的普通读和volatile读重排序*
* LoadStore屏障：*禁止下面的普通写和volatile读重排序*  

-|----------------------

###### 内存屏障对同步的作用

从上面我们可以看到，通过volatile关键字，构建了happens-before的关系，限制普通变量和volatile变量读写的操作指令重排序，有效保证了程序语义的正确性。从下面图我们可以进一步分析：
![volatile使线程之间的对共享变量操作的同步](http://cloud.atomicer.cn/blog-img/20161113/20161112234935.jpg) 
<!-- ![volatile使线程之间的对共享变量操作的同步](/blog-img/20161113/20161112234935.jpg)  --> 
[图4.2 volatile使线程之间的对共享变量操作的同步]  

所以，volatile变量的`写-读`操作语义和Lock的`获取-释放`语义相同（这是JSR-133对volatile内存语义增强后的），使用volatile我们亦可以灵活、轻量地实现对共享（普通）变量的同步：

| volatile [volatile static int a = 1] | Lock |
|:-------:|:------------:|
|读volatile变量：while(a!=1);|Lock acquire()|
|操作临界资源(共享变量)|操作临界资源(共享变量)|
|写volatile变量[a=1]|Lock release()|
*写volatile变量时，会将共享变量的本地内存中的修改刷新到主存中*  

要想使用volatile完全代替锁还需谨慎，volatile比较难像锁一样可以很好地保证整个临界区域代码的原子性
* `vloatile` 保证对单个volatile变量读/写的原子性
* `锁` 保证临界区域互斥执行  

但是，volatile的内存语义为我们提供了锁的思路，正如上面表格中使用volatile模仿Lock进行同步，既保证了临界区域的互斥执行，又保证了任意线程对共享变量修改及时刷新到主内存中，保证了线程间有效通信从而避免并发操作临界资源的一些问题。  

###### 从volatile到锁的思考

锁可以让临界区域互斥执行，那么线程之间必然存在一个同步的机制。

（1）volatile读 -----> |屏障|--->临界操作--->|屏障|--->volatile写，成对的volatile构建了happens-before的关系，并且保证了普通共享变量在`volatile写`之前刷新到主内存中  

（2）结合线程间通信的方式  
![线程间通信的方式](http://cloud.atomicer.cn/blog-img/20161113/20161112234958.jpg)  
<!-- ![线程间通信的方式](/blog-img/20161113/20161112234958.jpg)   -->
[图4.3 线程间通信的方式]  


上图的线程A对共享变量的写和线程B的读共享变量，有单线程程序的顺序一致性效果，此时我们可以想到volatile的作用。通过volatile变量，可以实现从A线程发送通知到B线程并且能够保证happens-before的语义正确性（在并发时就很好理解为什么happens-before并不要求前一个操作一定要在后一个操作之前执行，只需要前一个操作的结果对后一个操作可见），此时我们可推出锁获取和释放的内存语义：
* 线程A释放一个锁，即线程A向接下来要获取锁的线程B发出消息（A修改共享的变量）
* 线程B获取一个锁，即线程B接收到之前某个线程发出的消息（共享变量发生变化）

从一个线程释放锁，到另一个线程释放锁，实际上是两条线程通过主线程同步对共享变量的操作，通过主内存相互通信。所以，在Java编码上实现锁的内存语义，可以通过对一个volatile变量的读写，来实现线程之间相互通知，保证临界区域代码的互斥执行。

[以上内容参考《Java并发编程的艺术》]
