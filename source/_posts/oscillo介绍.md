---
title: oscillo：利用psutil监控进程的cpu和内存负载
date: 2019-03-14 23:18:20
categories: [写点小玩具]
tags: [写点小玩具]
---

![demo](https://raw.githubusercontent.com/raomuyang/cmd-oscillo/master/demo/compare-gzip.png)

如果使用过`glances`，如果有一颗geek的心的话，一定会觉得不但酷炫而且十分实用。不过如果想观察一个程序从运行开始到结束的cpu占用率怎么办？好办，利用python的`psutil`异步观察就行。


介绍一下放在github上的一个项目： [oscillo](https://pypi.org/project/oscillo/) 

<!-- more -->

### 使用方式
使用方式很简单，直接 `pip install oscillo`即可安装使用.

命令行参数的格式是 `"<name>: <command [args]>"`：

* `name`: 命令行的别名/id (任意字符串)，当`--commands/-c`参数指定多个命令时，该值将作为命令的唯一标识，不可重复
* `command [args]`: 需要测试资源消耗的命令，比如 `gzip file.ext`

示例如下，监控gzip压缩一个文件时耗费的cpu、memory和时间：
 
``` 
oscillo -c 'gzip: gzip file.ext' -o output-file
```

* -c 代表将执行一个linux cmd 命令。参数后面可以跟以空格隔开的多个参数

* -o 结果输出文件:

命令执行完成后，会在当前目录下生成一个`<output-file>.log` 文件。文本结构是json 格式. 数据结构如下
```
{
  "test": {
            "elapsed": 0.022143125534057617,  //总执行时间
            "cpu": [], 
            "memory": []
          }
}

```
同时会产生一个`<output-file>.png`文件，`<output-file>`由`-o`参数指定，默认值为`metrix`

在控制台上，`oscillo`会打印summary信息，其中包含命令的耗时、最大内存使用、最大cpu使用、退出码等在控制台上，`oscillo`会打印summary信息，其中包含命令的耗时、最大内存使用、最大cpu使用、退出码等

如果想对比多个命令对资源的消耗，可以使用 `-c/--commands` 选项指定多条命令, e.g.:

对比`gzip`和`tar`命令对资源的消耗：

```shell
oscillo -c 't1: gzip file.ext'  't2: tar czf target.tar.gz file1' -o output
```

效果如下：

![demo](https://raw.githubusercontent.com/raomuyang/cmd-oscillo/master/demo/metrix.log.png)

![demo](https://raw.githubusercontent.com/raomuyang/cmd-oscillo/master/demo/compare-gzip.png)



### 实现原理

这个工具的原型，来自于一次为了对比几种客户端性能而写的一个脚本，它的原理就是：

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


### BTW

当前的功能比较简单，可能有很多东西没用想到，欢迎使用和完善

git仓库: [oscillo](https://github.com/raomuyang/cmd-oscillo)
