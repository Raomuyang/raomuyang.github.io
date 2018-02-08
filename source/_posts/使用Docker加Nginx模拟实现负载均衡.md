---
title: 使用Docker+Nginx模拟负载均衡
date: 2016-10-12 11:35:13
tags: [Nginx, Docker]
meta: [Docker, Nginx, Docker模拟负载均衡]
categories: [Docker, Nginx]
---

> 一直听说Nginx的强大，它不仅可以作为Web服务器，按照调度规则实现动态、静态页面的分离；还可以作为反向代理服务器，构建服务集群，按轮询、权重等多种方式对后端服务器做负载均衡。以及自动剔除因故障负载均衡列表中宕机的服务器。这两天折腾了一下Nginx的安装、配置，并通过Docker模拟出Nginx在多服务器提供服务的状态下的负载均衡。

<!--more-->

### (一) 系统环境

| 操作系统     | Docker| Nginx |
| ------------|:------:|:-----:|
| Ubuntu 16   | 1.12.1 |1.8.0|

### (二) 准备Nginx环境
　　使用Docker这种容器技术，可以很方便地将所需要的环境打包和快速部署。所以我将Nginx的环境做成Docker镜像，当需要多个Nginx服务时，只需要通过镜像启动多个容器。  
* 镜像已经PUSH到Docker Hub上，如果需要，可以直接在Docker拉取配置好nginx环境的镜像`docker pull raomengnan/ubuntu:nginx-1.8.0`

* raomengnan/ubuntu:nginx-1.8.0 包含的基础环境： nginx，zsh，vim，ssh，python

#### Dockerfile
```shell
  # Ubuntu with Nginx
  # Author raomengnan
  FROM raomengnan/ubuntu-base
  MAINTAINER raomengnan

  # 安装升级gcc
  RUN rm -rf /var/lib/apt/lists/*
  RUN apt-get update

  # 添加相关的src
  RUN apt-get -y install build-essential
  RUN apt-get -y install supervisor
  RUN mkdir -p /usr/local/temp

  COPY supervisor.conf /etc/supervisor/conf.d/supervisord.conf

  RUN wget http://nginx.org/download/nginx-1.8.0.tar.gz && tar -zxvf nginx-1.8.0.tar.gz -C /usr/local/temp
  RUN wget http://zlib.net/zlib-1.2.8.tar.gz && tar -zxvf zlib-1.2.8.tar.gz -C /usr/local/temp
  RUN wget http://www.openssl.org/source/openssl-1.0.1q.tar.gz && tar -zxvf openssl-1.0.1q.tar.gz -C /usr/local/temp
  RUN wget http://downloads.sourceforge.net/project/pcre/pcre/8.37/pcre-8.37.tar.gz && tar -zxvf pcre-8.37.tar.gz -C /usr/local/temp

  RUN rm *.tar.gz

  # 安装
  RUN ls /usr/local/temp/nginx-1.8.0
  RUN cd /usr/local/temp/nginx-1.8.0 \
        && ./configure --sbin-path=/usr/local/nginx-1.8.0/nginx --conf-path=/usr/local/nginx-1.8.0/nginx.conf --pid-path=/usr/local/nginx-1.8.0/nginx.pid --with-http_ssl_module --with-pcre=/usr/local/temp/pcre-8.37 --with-zlib=/usr/local/temp/zlib-1.2.8 --with-openssl=/usr/local/temp/openssl-1.0.1q \
        && make \
        && make install

  # 设置nginx是非daemon启动，否则nginx无法启动
  RUN echo "\ndaemon off;" >> /usr/local/nginx-1.8.0/nginx.conf
  RUN echo 'master_process off;' >> /usr/local/nginx-1.8.0/nginx.conf
  RUN echo 'error_log  logs/error.log;' >> /usr/local/nginx-1.8.0/nginx.conf

  RUN rm -rf /usr/local/temp/*

  ENV NGINX_HOME /usr/local/nginx-1.8.0

  # 将nginx添加到command
  update-alternatives --install /usr/bin/nginx nginx /usr/local/nginx-1.8.0/nginx 300

  EXPOSE 80
  # 使用supervisor来管理多个进程同时启动
  # 若不想使用supervisor，可以使用：
  #   CMD nginx $/NGINX_HOME/nginx.conf
  #   或者进入容器手动启动nginx
  CMD ["/usr/bin/supervisord"]
```
#### supervisor.conf
```javascript
[supervisord]
nodaemon=true

[program:sshd]
command=/usr/sbin/sshd -D

[program:nginx]
command=/usr/local/nginx-1.8.0/nginx -c /usr/local/nginx-1.8.0/nginx.conf
```



### (三) 启动Nginx服务
启动nginx时，可以提供Nginx的welcome页面的访问服务，可以通过这个页面简单地尝试nginx提供的负载均衡。

#### 通过镜像启动三个nginx服务
``` shell
docker run --name ser1 -p 8881:80 raomengnan/ubuntu:nginx-1.8.0

docker run --name ser2 -p 8882:80 raomengnan/ubuntu:nginx-1.8.0

docker run --name ser3 -p 8883:80 raomengnan/ubuntu:nginx-1.8.0
```
*-p参数将容器的80端口映射到宿主机的888×端口上*

#### 以ser1作为主服务器，进入容器内修改nginx配置文件
使用`docker inspect ser1`便可以看到容器的详细信息，其中注意NetworkSetting下的这一段信息就可以知道容器的网关和ip地址
``` json
"Gateway": "172.17.0.1",
"GlobalIPv6Address": "",
"GlobalIPv6PrefixLen": 0,
"IPAddress": "172.17.0.3",
```
`docker exec -it ser1 bash`进入容器内部  
nginx安装目录在'/usr/local/nginx-1.8.0'下，`vim /usr/local/nginx-1.8.0/nginx.conf`编辑配置文件:

```shell
#user  nobody;
worker_processes  1;
events {
    worker_connections  1024;
}


http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile        on;
    keepalive_timeout  65;

    client_header_buffer_size    1k;
    large_client_header_buffers  4 4k;

    # 配置负载均衡，weight代表权重，权重越高，分配到的可能就越搭
    upstream 172.17.0.2 {

           server 172.17.0.2:8888 weight=5;
           server 172.17.0.3:80   weight=4;
           server 172.17.0.4:80   weight=3;
    }
    # 配置反向代理
    server {
           listen 80;
           server_name 172.17.0.2;
           location /{
              # 反向代理的主机头
              proxy_pass  http://172.17.0.2;
              proxy_set_header Host   $host;
              proxy_set_header   X-Real-IP        $remote_addr;
              proxy_set_header   X-Forwarded-For  $proxy_add_x_forwarded_for;
           }
    }

    # 侦听本地8888端口，以便为反向代理到本地的请求提供服务
    server {
           listen       8888;
           server_name  localhost;
           # 如过没有对代理的链接形式有特殊要求，可以直接将root和index写在server中
           location / {
               root   /home/html;
               index  index.html index.htm;
           }
          error_page   500 502 503 504  /50x.html;
          location = /50x.html {
                 root   /home/html;
         }
       }
}

```
在ser1这个容器中配置反向代理，要关注`server 172.17.0.2:8888 weight=5;`这一行，之所以反向代理到本机的8888端口，很好理解，因为若再次代理到80端口，永远不能代理到本机的服务中，陷入死循环。

#### 以ser×作为服务器
```shell

#user  nobody;
worker_processes  1;
events {
    worker_connections  1024;
}


http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile        on;
    keepalive_timeout  65;

    client_header_buffer_size    1k;
    large_client_header_buffers  4 4k;

    server {
           listen       80;
           server_name  172.17.0.2;
           # 如过没有对代理的链接形式有特殊要求，可以直接将root和index写在server中
           location / {
               root   /home/html;
               index  index.html index.htm;
           }
          error_page   500 502 503 504  /50x.html;
          location = /50x.html {
                 root   /home/html;
         }
       }
}
```
serx和ser1的区别就在于http的设置，没有upstream，server_name 为要负载的服务器的ip。修改好配置文件后，使用`nginx -s reload`重新载入配置。  



### (四) 刷新网页测试
* 修改三个ser中的index.html,方便观察
* 在浏览器中打开 localhost:8881 或者 172.17.0.2，刷新网页
> 不断刷新，可以看到会打开不同容器中的index页面，说明服务被Nginx均衡地分配到不同的service上，这就是Nginx的负载均衡的作用。
