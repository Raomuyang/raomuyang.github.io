---
title: hexo 搭建笔记[测试博客]
date: 2016-03-24 14:47:47
tags: hexo
meta: hexo
categories: [转载]
---


* ## 安装Git

下载并安装msysgit或者是msysgit中文版，如果你想了解点Git的基础命令，我推荐以下博文：Git常用的基础命令，史上最全github使用方法：github入门到精通,当然即使你不懂Git的命令，跟着本博文走，也完全没问题。

* ## 安装Node.js

下载并安装Node.js，此处我建议安装完毕后重启电脑，因为我当初安装完没重启，结果后面使用命令安装hexo的时候，提示无效的命令，因此推荐重启。当然，你也可以选择等到后面遇到问题，再选择重启。
<!--more-->

* ## 安装hexo

安装前先介绍几个hexo常用的命令,#后面为注释。

```
$ hexo g #完整命令为hexo generate,用于生成静态文件
$ hexo s #完整命令为hexo server,用于启动服务器，主要用来本地预览
$ hexo d #完整命令为hexo deploy,用于将本地文件发布到github上
$ hexo n #完整命令为hexo new,用于新建一篇文章
```
鼠标右键任意地方，选择Git Bash，使用以下命令安装hexo

```
$ npm install hexo-cli -g
```

如果之后在使用的过程中，遇到以下的错误

```
ERROR Deployer not found : github
```
则运行以下命令,或者你直接先运行这个命令更好。
```
$ npm install hexo-deployer-git --save
$ hexo g
$ hexo d
```
* ## 初始化博客文件夹
接下来创建放置博客文件的文件夹：hexo文件夹。在自己想要的位置创建文件夹，如我hexo文件夹的位置为E:\hexo，名字和地方可以自由选择，当然最好不要放在中文路径下，至于原因，我想很多人懂得。之后进入文件夹，即E:\hexo内，点击鼠标右键，选择Git Bash，执行以下命令，Hexo会自动在该文件夹下下载搭建网站所需的所有文件。
```
$ hexo init
```
安装依赖包
```
$ npm install
```

* ## 创建
让我们看看刚刚下载的hexo文件带来了什么，执行以下命令，
```
$ hexo g
$ hexo s
```
然后用浏览器访问http://localhost:4000/
