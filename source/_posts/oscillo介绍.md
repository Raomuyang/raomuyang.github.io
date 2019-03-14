---
title: oscillo：利用psutil监控进程的cpu和内存负载
date: 2019-03-14 23:18:20
categories: [写点小玩具]
tags: [写点小玩具]
---

如果使用过`glances`，并且有一颗geek的心的话，一定会觉得它很炫酷，并且十分实用。不过如果想观察一个程序从运行开始到结束的cpu占用率怎么办？好办，利用python的`psutil`异步观察就行。

<!-- more -->

[oscillo](https://pypi.org/project/oscillo/) 这个工具的原型，来自于一次为了对比几种客户端性能而写的一个脚本，它的原理就是：

* 在程序中启动一个子进程，获取进程id
* 通过`psutil`观察该进程，每隔一段时间记录一次cpu和内存的负载
* 通过`matplotlib`画图

说一下其中碰到的一个坑：欲监控的子进程A在内部调用了另一个耗资源的子进程B，但是psutil只能观察到子进程A的资源消耗情况，粗暴的解决办法就是：观察全局的资源消耗情况：

```python
class Stopwatch(object):

    def __init__(self, pid):
        self.__is_run = False
        self.__start_time = 0
        self.__elapsed_times = 0
        self.memory_percent = []
        self.cpu_percent = []
        self.pid = pid

    def start(self):
        if self.__is_run:
            return False
        self.__is_run = True
        self.__start_time = time.time()

        if self.pid > 0:
            p = psutil.Process(self.pid)
        else:
            p = psutil
            p.memory_percent = lambda: p.virtual_memory().percent
        while self.__is_run:
            try:
                self.cpu_percent.append(p.cpu_percent(1))
                self.memory_percent.append(p.memory_percent())
            except psutil.NoSuchProcess:
                break

    @property
    def elapsed(self):

        if self.__is_run:
            return self.__elapsed_times + time.time() - self.__start_time
        return self.__elapsed_times

    def stop(self):
        self.__elapsed_times = self.elapsed
        self.__is_run = False
```


好了，以下是使用效果：


![demo](https://raw.githubusercontent.com/raomuyang/cmd-oscillo/master/demo/metrix.log.png)

![demo](https://raw.githubusercontent.com/raomuyang/cmd-oscillo/master/demo/cli.png)

### BTW

git仓库: [oscillo](https://github.com/raomuyang/cmd-oscillo)
