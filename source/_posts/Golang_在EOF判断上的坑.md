---
title: 'Golang 在EOF判断上的坑'
date: 2018-01-29 03:22:17
tags: ['Golang']
meta: ["Golang \u5728EOF\u5224\u65ad\u4e0a\u7684\u5751"]
categories: Golang
---

读取文件流等操作中，通常通过 `if err == io.EOF` 判断文件流是否终止，此时退出循环。
通常文件中`err == io.EOF`时，此时读取的字节一般为0，但是在`gzip.Reader`中，读取到文件结尾时，`err != nil`且 `read != 0`，what...和python、java的习惯有点不一样啊，看样子在处理时不能遗漏最后一个读取出来的字节，所以还是把doSomeThing放到`Read`结束之后立即操作吧。

<!-- more -->

```golang
for {

 buf := make([]byte, 1024)

 read, err := reader.Read(buf)

 if err == io.EOF {

 break

 }

 if err != nil {

 return nil, err

 }

 doSomeThing(buf[:read])

}
```
