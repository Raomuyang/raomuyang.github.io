---
title: Python多线程以及自定义一个Python线程池
date: 2016-05-6 15:29:57
tags: [Python,多线程]
meta: [Python]
categories: [Python]
---
> 网上许多人说Python多线程的性能不好，我觉得应该是“相对”吧，而且性能好不好也要视程序员设计代码的情况而定。我查了一些资料，Python运行在解释器中，有一个全局锁（GIL），不使用使用多进程的话就不能发挥多核的优势。所以，如果多线程的进程是**CPU密集型**的，那多线程并不能有多少效率上的提升，相反还可能会因为线程的频繁切换，导致效率下降，推荐使用多进程；如果是**IO密集型**，多线程进程可以利用IO阻塞等待时的空闲时间执行其他线程，提升效率。

#### 以下是python的多线程的使用，以及如何简单地设计一个线程池。<br>
在这里我们可以看到，线程池是模仿操作系统中的FIFO（先进先出）的任务调度实现。
* 定义两个队列，一个存储正在运行的任务，一个存储排队等待的任务。
* 定义一个最大并行任务数MAX_RUN，决定线程池的容量，MAX_WAIT,限制等待队列的长度
* 通过一个轮询线程，周期性地扫描是否有任务结束
* 通过另一个线程，调度正在排队等待的任务
<!--more-->
下面是实现代码

* #### 引入time、 threading相关的库
```Python
import time
import os
from threading import Thread, activeCount, Condition, Lock, Semaphore;
```

* #### 线程池的实现
##### 关于线程同步
> * 锁： python的list是非线程安全的，所以用到互斥锁来同步线程对waitQueue和runTask的操作
> * 信号量： 这里我在限制最多加入等待队列的任务数时，使用了资源信号量semphore来同步调度和回收线程，注释部分也保留了之前通过对象内共享的内存中self.waitingTasks的长度来判断是在调度任务时否阻塞线程。因为没有大量测试，这里不讨论哪种实现性能会更佳，就给出两种实现方式。[semaphore和是内核对象（但python中如何实现我还不太清除），并且特别占用系统资源，线程的同步包括用户模式下的同步和内核模式下的同步，如果用内核对象来同步被保护的资源，系统需要从用户模式切换到内核模式，这个时间大概是1000个cpu周期]

##### 线程池的结构
```Python
# coding=utf-8
class ThreadPool:

    def __init__(self, max_run=10, max_wait=10000):
        self.MAX_WAIT = max_wait
        self._MAX_RUN = max_run
        self.wait_queue_semap = Semaphore(max_wait)
        self._STOP_TIME = 60 * 60
        self.no_task_time = 0

        self._start = True
        self._runningTasks = []
        self._waitingTasks = []
        self._gcThread = Thread(target=self._taskGC)
        self._gcThread.start()
        self._dispatchThread = Thread(target=self._taskDispatch)
        self._dispatchThread.start()

        self._lock = Condition(Lock())

    def addTask(self, target, args):
        '''资源不足时忙等，和信号量的原理相同'''
        # while self._waitingTasks.__len__() + 1 > self.m:
        #     pass

        self.wait_queue_semap.acquire()
        if self._lock.acquire():#互斥锁
            '''先将锁添加到等待队列中,剩下的事情由调度线程去完成'''
            task = Task(target, args)
            self._waitingTasks.append(task)

            # print("task wait",args)
            self._lock.release()

    # 不断地检测线程池中是否有退出的线程
    def _taskGC(self):

        while self._start:
            '''remove the task in runningTasks'''
            if self._runningTasks.__len__() > 0:
                for task in self._runningTasks:
                    if not task._thread.is_alive():
                        print("[task remove stop]--------{0}".format(task._args))
                        self._runningTasks.remove(task)
                    '''这里我本来想为每个任务设置时间片，令其移除任务，但是一直找不到合适的办法结束线程'''
                    # else:
                    #      if task.getTimeUsed() > self.MAX_TIME_BLOCK:
                    #          print("task remove timeout",task._args)
                    #          task._thread.stop()
                    #          self.runningTasks.remove(task)

            if(self._runningTasks.__len__() > 0 or self._waitingTasks.__len__() > 0):
                self.no_task_time = 0
            else:
                if self.no_task_time == 0:
                    self.no_task_time = time.time()

            if(self.no_task_time != 0 and int(time.time() - self.no_task_time) > self._STOP_TIME):
                self._start = False
                print ("[INFO]----------exit")
            print("[wait]------------" + str(self._waitingTasks.__len__()))
            print("[run]-------------" + str(self._runningTasks.__len__()))

    def _taskDispatch(self):
      '''当前执行的线程数不大于最大并行任务数，则将正在排队的等待任务队列中最前面的任务取出执行'''
        while self._start:
            if self._runningTasks.__len__() < self._MAX_RUN:
                if self._waitingTasks.__len__() > 0:
                    task = self._waitingTasks.pop()
                    task.start()
                    '''释放信号量'''
                    self.wait_queue_semap.release()
                    self._runningTasks.append(task)

    def stop(self):
        self._start = False
        os._exit(0)

    def getWaits(self):
        return self._waitingTasks

```
* #### 定义任务的结构。将方法和参数作为任务传入，实例化为任务对象，然后可以将其添加到排队等待序列
```Python
class Task:
    def __init__(self,_target,_args):
        self._beginTime = time.time()
        self._args = _args
        self._thread = Thread(target=_target,args=_args)

    def getTimeUsed(self):
        return time.time() - self._beginTime

    def start(self):
        self._thread.start()
```

* #### 最后，通过一小段demo来验证我们的线程池

```Python
if __name__ == '__main__':
    def test(i):
        print(i)
        time.sleep(10)

    pool = ThreadPool(10,10)
    arg = [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20]
    for i in arg:
        args = [i]
        pool.addTask(test,args)
```
