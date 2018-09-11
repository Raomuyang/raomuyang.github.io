---
title: Python中单线程、多线程与多进程的效率对比实验
date: 2016-09-30 07:05:47
tags: [多线程,多进程,Python]
categories: [Python]
meta: Python中多线程和多进程的对比
---
> Python是运行在解释器中的语言，查找资料知道，python中有一个全局锁（GIL），在使用多进程(Thread)的情况下，不能发挥多核的优势。而使用多进程(Multiprocess)，则可以发挥多核的优势真正地提高效率。

##### 对比实验


资料显示，如果多线程的进程是**CPU密集型**的，那多线程并不能有多少效率上的提升，相反还可能会因为线程的频繁切换，导致效率下降，推荐使用多进程；如果是**IO密集型**，多线程进程可以利用IO阻塞等待时的空闲时间执行其他线程，提升效率。所以我们根据实验对比不同场景的效率

| 操作系统     | CPU | 内存 | 硬盘 |
| ------------|---|---|---|
| Windows 10     | 双核 |8GB|机械硬盘|

<!--more-->

###### (1)引入所需要的模块
```python
import requests
import time
from threading import Thread
from multiprocessing import Process
```
###### (2)定义CPU密集的计算函数
```python
def count(x, y):
    # 使程序完成50万计算
    c = 0
    while c < 500000:
        c += 1
        x += x
        y += y
```


###### （3）定义IO密集的文件读写函数
```python
def write():
    f = open("test.txt", "w")
    for x in range(5000000):
        f.write("testwrite\n")
    f.close()

def read():
    f = open("test.txt", "r")
    lines = f.readlines()
    f.close()
```

###### (4) 定义网络请求函数
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

###### (5)测试线性执行IO密集操作、CPU密集操作所需时间、网络请求密集型操作所需时间
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

###### (6)测试多线程并发执行CPU密集操作所需时间
```python
counts = []
t = time.time()
for x in range(10):
    thread = Thread(target=count, args=(1,1))
    counts.append(thread)
    thread.start()

while True:
    e = len(counts)
    for th in counts:
        if not th.is_alive():
            e -= 1
    if e <= 0:
        break
print(time.time() - t)
```

|output|
|------|
|99.9240000248|
|101.26400017738342|
|102.32200002670288|

###### (7)测试多线程并发执行IO密集操作所需时间
```Python
def io():
    write()
    read()

t = time.time()
ios = []
t = time.time()
for x in range(10):
    thread = Thread(target=count, args=(1,1))
    ios.append(thread)
    thread.start()


while True:
    e = len(ios)
    for th in ios:
        if not th.is_alive():
            e -= 1
    if e <= 0:
        break
print(time.time() - t)
```

| Output |
|----|
|25.69700002670288|
|24.02400016784668|

###### (8)测试多线程并发执行网络密集操作所需时间
```python
t = time.time()
ios = []
t = time.time()
for x in range(10):
    thread = Thread(target=http_request)
    ios.append(thread)
    thread.start()

while True:
    e = len(ios)
    for th in ios:
        if not th.is_alive():
            e -= 1
    if e <= 0:
        break
print("Thread Http Request", time.time() - t)
```
| Output|
| ---|
|0.7419998645782471|
|0.3839998245239258|
|0.3900001049041748|

###### (9)测试多进程并发执行CPU密集操作所需时间
```python
counts = []
t = time.time()
for x in range(10):
    process = Process(target=count, args=(1,1))
    counts.append(process)
    process.start()

while True:
    e = len(counts)
    for th in counts:
        if not th.is_alive():
            e -= 1
    if e <= 0:
        break
print("Multiprocess cpu", time.time() - t)
```

|Output|
|---|
|54.342000007629395|
|53.437999963760376|

###### (10)测试多进程并发执行IO密集型操作
```python
t = time.time()
ios = []
t = time.time()
for x in range(10):
    process = Process(target=io)
    ios.append(process)
    process.start()


while True:
    e = len(ios)
    for th in ios:
        if not th.is_alive():
            e -= 1
    if e <= 0:
        break
print("Multiprocess IO", time.time() - t)
```

|Output|
|---|
|12.509000062942505|
|13.059000015258789|

###### (11)测试多进程并发执行Http请求密集型操作
```python
t = time.time()
httprs = []
t = time.time()
for x in range(10):
    process = Process(target=http_request)
    ios.append(process)
    process.start()

while True:
    e = len(httprs)
    for th in httprs:
        if not th.is_alive():
            e -= 1
    if e <= 0:
        break
print("Multiprocess Http Request", time.time() - t)
```  

|Output|
|0.5329999923706055|
|0.4760000705718994|  

---
##### 实验结果

|  | CPU密集型操作 | IO密集型操作 | 网络请求密集型操作 |
|:--:|:--------------:|:-------------:|:-------------------:|
|线性操作|94.91824996469|22.46199995279|7.3296000004|
|多线程操作|101.1700000762|24.8605000973|0.5053332647|
|多进程操作|53.8899999857|12.7840000391|0.5045000315|

通过上面的结果，我们可以看到：
>
* 多线程在IO密集型的操作下似乎也没有很大的优势（也许IO操作的任务再繁重一些就能体现出优势），在CPU密集型的操作下明显地比单线程线性执行性能更差，但是对于网络请求这种忙等阻塞线程的操作，多线程的优势便非常显著了
* 多进程无论是在CPU密集型还是IO密集型以及网络请求密集型（经常发生线程阻塞的操作）中，都能体现出性能的优势。不过在类似网络请求密集型的操作上，与多线程相差无几，但却更占用CPU等资源，所以对于这种情况下，我们可以选择多线程来执行
![多线程的效果](http://cloud.atomicer.cn/blog-img/20160930/python/multiprogress_result.png)
