---
title: gnu/parallel + nfs 实现共享文件网络的并发计算等操作
date: 2018-01-18 10:17:39
tags: [Linux]
---

Linux/MacOS中的`xargs`命令可以通过`-P`参数，利用机器的多核进行操作，堪称神器：
``` shell
# 4个进程并行压缩文件夹下的所有文件
ls |xargs -I{} -P 4 gzip "{}"
```

当然`xargs`只能利用本机的资源，如果想同时利用多台计算机进行并行的操作时，就要用到 `gnu/parallel`了，安装paralle的方式：
* mac `brew install paralle`
* ubuntu `sudo apt-get install parallel`

通常地，`xargs`和`parallel`的命令非常相似：
``` shell
ls |xargs -I{} -P 4 gzip "{}"
ls |parallel -I{} -j4  gunzip "{}"
```

<!-- more -->

如果想分配到多台机器上执行，只需在`paralle` 后面加上 `-S`参数即可

``` shell
# 4/machine1,machine2 表示在machine1、machine2上，每台机器启动4个进程执行，machine是主机名
ls |parallel  -S 4/machine1,machine2,... -I{}  gunzip "{}"

parallel -S 4/192.168.1.111,192.168.1.112 -I{} gzip "path/to/{}"
```

> 强烈推荐安装`tldr`，对于不熟悉的命令，用`tldr`可以这个命令的简洁的用法
```yml
> tldr parallel

parallel

Run commands on multiple CPU cores.

- Gzip several files at once, using all cores:
    parallel gzip ::: file1 file2 file3

- Read arguments from stdin, run 4 jobs at once:
    ls *.txt | parallel -j4 gzip

- Convert JPG images to PNG using replacement strings:
    parallel convert {} {.}.png ::: *.jpg

- Parallel xargs, cram as many args as possible onto one command:
    args | parallel -X command

- Break stdin into ~1M blocks, feed each block to stdin of new command:
    cat big_file.txt | parallel --pipe --block 1M command

- Run on multiple machines via SSH:
    parallel -S machine1,machine2 command ::: arg1 arg2
```

以上只是parallel的一些简单操作，执行一些文件无关的操作（比如`echo`命令）是没有问题的，但如果要执行gzip等操作，依赖本地的文件，显然是不可行的，parallel并不能共享文件，这个时候就要使用`NFS`搭建网络共享文件系统。

* NFS搭建
NFS网络的搭建比较简单，在ububtu可以直接apt-get install安装nfs服务：`sudo apt-get install nfs-kernel-server`，mac上已经集成了nfs服务（nsfd），无需另外安装。另外，nfs依赖`rpcbind`，所以在使用前需要检查一下本机是否安装了rpcbind，如果未安装，直接使用`sudo apt-get install rpcbind`即可。

nfs服务安装完成后，修改`/etc/exports`文件进行配置需要共享的目录：
```shell
/NFS/           *(ro,sync,no_subtree_check)
/NFS/Public/    192.168.*.*(rw,sync,no_subtree_check)
```
以上配置比较好理解：
* 共享`/NFS`目录，`*`表示允许任何主机访问，
* 共享`/NFS/Public`目录，`192.168.*.*`表示允许改网段的主机访问
* 括号内的表示访问权限等配置，如只读(ro)、读写(rw)等，可以参考：[exports file for NFS](https://www.ibm.com/support/knowledgecenter/en/ssw_aix_71/com.ibm.aix.files/exports.htm)

配置完成后，使用`showmount -e`可以看到本机的共享目录。

* NFS客户端
当nfs-server搭建好之后，客户机只需将nfs服务共享的目录挂在到本地既可。同样地，mac已经集成了该服务，无需另外安装，linux需安装 `nfs-common`：
`sudo apt-get install nfs-common`

使用`showmount -e <host>`可以看到服务端共享的文件，将其挂载到本地：
```shell
mkdir -p /NFS

# mac
sudo mount_nfs -o resvport 192.168.1.111:/NFS /NFS
# linux
sudo mount -t nfs 192.168.1.111:/NFS /NFS

# 取消挂载
sudo umount /NFS
```

在这里，我把`/NFS/`目录挂载到本地的同名目录中，便于统一执行命令，挂载完成后，所有的客户机和NFS服务机的/NFS目录就是同步的了，这样我们即可通过parallel无差别地完成并行计算等操作：

比如我们有一批超大的文件需要计算MD5，借助parallel和nfs重复利用多台机器的CPU资源(暂时忽略IO)：
```
ls /NFS/bio-test |parallel -S 4/192.168.1.111,192.168.1.112,192.168.1.113 -I{} md5sum "/NFS/bio-test/{}"
```

paralle会自动根据计算机的核心数等资源进行任务分配，使用tmux + glances(或者top)可以实时监控这些及其的性能。

![性能监控图示](http://cloud.atomicer.cn/blog-img/nfs-parallel.jpg)
