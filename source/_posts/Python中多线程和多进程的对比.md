---
title: Python中单线程、多线程与多进程的效率对比实验
date: 2016-09-30 07:05:47
tags: [多线程,多进程,Python]
categories: [Python]
meta: Python中多线程和多进程的对比
---
> Python是运行在解释器中的语言，查找资料知道，python中有一个全局锁（GIL），在使用多进程(Thread)的情况下，不能发挥多核的优势。而使用多进程(Multiprocess)，则可以发挥多核的优势真正地提高效率。

## 对比实验

资料显示，如果多线程的进程是**CPU密集型**的，那多线程并不能有多少效率上的提升，相反还可能会因为线程的频繁切换，导致效率下降，推荐使用多进程；如果是**IO密集型**，多线程进程可以利用IO阻塞等待时的空闲时间执行其他线程，提升效率。所以我们根据实验对比不同场景的效率

| 操作系统     | CPU | 内存 | 硬盘 |
| ------------|---|---|---|
| Windows 10     | 双核 |8GB|机械硬盘|

<!--more-->

### 准备

#### (1)引入所需要的模块

```python
import requests
import time
from threading import Thread
from multiprocessing import Process
```

#### (2)定义CPU密集的计算函数

```python
def count(x, y):
    # 使程序完成50万计算
    c = 0
    while c < 500000:
        c += 1
        x += x
        y += y
```

#### (3)定义IO密集的文件读写函数

```python
def write(name=0):
    # name: 防止并发写同一个文件；
    # concurrence: 保证在不同的并发数下磁盘写入字节数相同
    f = open("test-{}.txt".format(name), "w")
    for x in range(5000000):
        f.write("testwrite\n")
    f.close()

def read(name=0):
    f = open("test-{}.txt".format(name), "r")
    lines = f.readlines()
    f.close()
```

#### (4)定义网络请求函数

```python
_head = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/48.0.2564.116 Safari/537.36'}
url = "http://www.tieba.com"
def http_request():
    try:
        webPage = requests.get(url, headers=_head)
        html = webPage.text
        return {"context": html}
    except Exception as e:
        return {"error": e}
```

### 单线程测试

#### (5)测试线性执行IO密集操作、CPU密集操作所需时间、网络请求密集型操作所需时间

```python
# CPU密集操作
t = time.time()
for x in range(10):
    count(1, 1)
print("Line cpu", time.time() - t)

# IO密集操作
t = time.time()
for x in range(10):
    write()
    read()
print("Line IO", time.time() - t)

# 网络请求密集型操作
t = time.time()
for x in range(10):
    http_request()
print("Line Http Request", time.time() - t)
```

> 输出

|               |                 |                  |                   |                   |
| -----------  |:----------------:|:-----------------:|:------------------:|:---------------:|
| CPU密集      |   95.6059999466   | 91.57099986076355 | 92.52800011634827 | 99.96799993515015|
| IO密集       |   24.25           | 21.76699995994568 | 21.769999980926514| 22.060999870300293|
| 网络请求密集型 | 4.519999980926514 | 8.563999891281128 | 4.371000051498413 | 14.671000003814697|

### 多线程测试

#### (6)测试多线程并发执行CPU密集操作所需时间

```python
# 列表生成
threads = [Thread(target=count, args=(1,1)) for _ in range(10)]
start = time.time()
for t in threads:
    t.start()
for t in threads:
    t.join()

print(time.time() - start)
```

|output|
|------|
|99.9240000248|
|101.26400017738342|
|102.32200002670288|

#### (7)测试多线程并发执行IO密集操作所需时间

```Python
def io(name):
    write(name)
    read(name)

start = time.time()
threads = [Thread(target=io, args=(i,)) for i in range(10)]
for t in threads:
    t.start()
for t in threads:
    t.join()
print(time.time() - start)
```

| Output |
|----|
|84.7796590328|
|108.204546928|

#### (8)测试多线程并发执行网络密集操作所需时间

```python
threads = [Thread(target=http_request) for _ in range(10)]
start = time.time()
for t in threads:
    t.start()
for t in threads:
    t.join()

print("Thread Http Request", time.time() - t)
```

| Output|
| ---|
|0.7419998645782471|
|0.3839998245239258|
|0.3900001049041748|

### 多进程测试

#### (9)测试多进程并发执行CPU密集操作所需时间

```python
p_list = [Process(target=count, args=(1,1)) for _ in range(10)]
start = time.time()
for p in p_list:
    p.start()
for p in p_list:
    p.join()
print("Multiprocess cpu", time.time() - start)
```

|Output|
|---|
|54.342000007629395|
|53.437999963760376|

#### (10)测试多进程并发执行IO密集型操作

```python
p_list = [Process(target=io, args=(i,)) for i in range(10)]
start = time.time()
for p in p_list:
    p.start()
for p in p_list:
    p.join()

print("Multiprocess IO", time.time() - start)
```

|Output|
|---|
|12.509000062942505|
|13.059000015258789|

#### (11)测试多进程并发执行Http请求密集型操作

```python
p_list = [Process(target=http_request) for i in range(10)]
start = time.time()
for p in p_list:
    p.start()
for p in p_list:
    p.join()

print("Multiprocess Http Request", time.time() - start)
```  

|Output|
|:---:|
|0.5329999923706055|
|0.4760000705718994|  

---

### 实验结果

|  | CPU密集型操作 | IO密集型操作 | 网络请求密集型操作 |
|:--:|:--------------:|:-------------:|:-------------------:|
|线性操作|94.91824996469|22.46199995279|7.3296000004|
|多线程操作|101.1700000762|96.4921029804|0.5053332647|
|多进程操作|53.8899999857|12.7840000391|0.5045000315|

结果中的多线程表现非常奇怪，为什么IO密集型的操作在多线程的场景下反而更慢呢？(感谢读者提出的问题) 我们看一下`write`函数：

```python
def write(name=0):
    # name: 防止并发写同一个文件；
    # concurrence: 保证在不同的并发数下磁盘写入字节数相同
    f = open("test-{}.txt".format(name), "w")
    for x in range(5000000):
        f.write("testwrite\n")
    f.close()
```

`write`函数中有5000000个循环，这妥妥的也是cpu密集型，我们把它改造一下：

```python
data = "\n".join(["testwrite" for i in range(5000)])
def write(name=None):
    f = open("test-{}.txt".format(name), "w")
    for x in range(1000):
        f.write("testwrite\n")
    f.close()
```

使用改造后的函数，重新运行IO密集的测试：

|  | 单线程 | 多线程 | 多进程 |
|:--:|:--------------:|:-------------:|:-------------------:|
|IO耗时|0.0199999|0.02644586|0.1005110740|

差异不大，反倒是速度上 `单线程 > 多线程 > 多进程`，显而易见，磁盘IO并没有被打满，多线程场景下多出的视角应该是线程切换和GIL产生的；多进程场景下的视角增长应该由于进程切换产生的；

虽然磁盘IO上无法完成测试，但是我们佐证了GIL对cpu密集型的多线程影响。

通过上面的结果，我们可以看到：

* 在CPU密集型的操作下明显地比单线程线性执行性能更差，但是对于网络请求这种忙等阻塞线程的操作，多线程的优势便非常显著了
* 多进程无论是在CPU密集型还是IO密集型以及网络请求密集型（经常发生线程阻塞的操作）中，都能体现出性能的优势。不过在类似网络请求密集型的操作上，与多线程相差无几，但却更占用CPU等资源，所以对于这种情况下，我们可以选择多线程来执行
![多线程的效果](http://cloud.atomicer.cn/blog-img/20160930/python/multiprogress_result.png)
