---
title: doemm：使用gist帮忙同步常用而难记的操作
date: 2018-12-06 14:50:39
categories: [写点小玩具]
tags: [写点小玩具]
---

`func this-is-a-very-very-long-command.fasfas@fsfaf*-afsaf-who-know..` 这是一个很长很长的命令，我时不时地需要执行一遍，通常都是使用`ctrl+R`或者`history`翻找历史记录，当我完全忘了这个命令怎么写时或者换了一台电脑时就头疼了。这个时候，我想有一个自己的工具用于索引和同步。

<!-- more -->

对工具的简单期望：
1. 可以很方便地将一个命令保存为别名，并且可以通过别名执行
2. 有一个索引列表并可以将命令打印出来
3. 支持同步

1、2两点很容易，像kindle的笔记一样，在本地保存文本文件即可；第3点，我想到了github的gist，将命令保存到`private gist`中既方便又安全。ok，工具比较简单，用golanng语言写，这样就不依赖虚拟机或者解释器了。

项目地址：[doemm](https://github.com/raomuyang/doemm)
编译好的二进制文件：[下载地址](https://github.com/raomuyang/doemm/releases)
