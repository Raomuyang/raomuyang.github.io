---
title: RX-Java中，life操作内部实现的优雅之处
date: 2016-11-23 17:04:08
tags: [Java, RXJava]
categories: Java
meta: RXJava的observable类型的转换原理，适配器模式
---

> RX-* 系列的库是一款开源的并发流程控制的框架，有多种语言的实现[1]。用户可以通过它使用流式的编程风格，写出高可读性的并发流程控制代码。以下是针对RX-Java中，observable的各种变换（如map、flatmap）的内部实现的分析。

<!-- more -->
如果使用过RX-Java，我们知道，map可以使一种类型的可订阅者被另一种类型的订阅者订阅：
* `Observable<Integer>`可被`Subscriber<Integer>`订阅
* `Observable<Integer>` --> `map<Integer, String>` ：可被`Subscriber<String>`订阅  
不论是map、还是flatmap，在底层都是通过life实现。那么通过life转换后的的observable如何将原来的类型参数<Integer>发射到新的subscriber上（observable<Integer> --> observable<String>）:    

* 1: 调用operator<R, T>的call方法（*R为目标类型， T为原始类型*）
    * （1）call中传入新的Subscriber<R>(*将来新的subscriber订阅observable<R>时会自动传入*) ,
    * （2）实例化旧的的Subscriber<R>(*和原本旧的observer<T>绑定*),通过旧的Subscriber<T>中的onNext、onCompleted，将T类型的数据处理并转为R类型，发送通知给subscriber<R>


* 2:
      * 实例化一个新的observable<R>，绑定新的OnSubscribe  
      * 通过 newOnSubscribe<R>.call()调用oldOnSubscribe<T>.call()
      * oldOnSubscribe<T> 通知 subscriber<T> ,subscriber<T> 在onNext onError onComplate中调用subscriber<R>  

通过代码来理解：  


**定义一个Integer 的 observable**
```java
        Observable observable = Observable.create(new Observable.OnSubscribe<Integer>() {
            @Override
            public void call(Subscriber<? super Integer> subscriber) {
                System.out.println("Observable:" + Thread.currentThread().getId());
                try{
                    for (int i = 0; i < 5; i++)
                        subscriber.onNext(i);
                    subscriber.onCompleted();
                }catch (Exception e){
                    subscriber.onError(e);
                }

            }
        });
```

**通过life将Integer的observable转为String的observable**  
注意看其中subsubscriber<Integer>是如何通知Subscriber<String>的
```java
        observable = observable.lift(new Observable.Operator<String, Integer>() {
                            @Override
                            public Subscriber<? super Integer> call(Subscriber<? super String> subscriber) {
                                return new Subscriber<Integer>() {
                                    @Override
                                    public void onCompleted() {
                                        System.out.println("Integer Subscriber Completed --|");
                                        subscriber.onCompleted();
                                    }

                                    @Override
                                    public void onError(Throwable throwable) {
                                        System.out.println("Integer Subscriber: Error-->");
                                    }

                                    @Override
                                    public void onNext(Integer integer) {
                                        System.out.println(
                                                String.format("Integer Subscriber --> Next:%s, Thread:%s -->",
                                                        integer, Thread.currentThread().getId()));
                                        subscriber.onNext(integer + "");
                                    }
                                };
                            }
                        }
           );
```

**注册Subscriber<String>并订阅observable**
```java
observable.observeOn(Schedulers.newThread())
          .subscribe(new Subscriber<String>() {
              @Override
              public void onCompleted() {
              System.out.println("String Subscriber Complete");
              }

              @Override
              public void onError(Throwable throwable) {
              System.out.println(throwable);
              }

              @Override
              public void onNext(String str) {
              System.out.println("String Subscriber Next:" + str + ",Thread:" + Thread.currentThread().getId());
              System.out.println("TR2:" + Thread.currentThread().getId());
              }

      });
```
我们可以看到：
* RX-Java在life的实现中，将observable<Integer>转为observable<String>，并没有去考虑将observable<Integer>中的call方法中发出的事件克隆过来，而是直接将observable<String>的创建与observable<Integer>的OnSubscribe相关联，直接通过observable<Integer>产生事件通知observable<String>。
* 在subscriber<String>与observable<String>的订阅事件(call)注册过程中，也很巧妙，通过observable<Integer>产生事件，通知observable<String> `-->` 然后observable<String>通知subscriber<Integer>执行事件 `-->` subscriber<Integer>中再通知subscriber<String>执行订阅事件  
这一整套过程，就优雅地使用了设计模式中的`适配器模式`和`代理`模式
