---
title: Windows下安装MongoDB服务并配置用户权限
date: 2016-08-12 11:35:13
tags: MongoDB
meta: [MongoDB, MongoDB服务并配置用户权限]
categories: [MongoDB]
---
> Mongo在安装好之后，默认是不需要用户验证就可以操作数据库的。所以在安装Mongo后我们需要手动配置MongoDB服务的用户权限

| 操作系统     | MongoDB版本|
| ------------- |:------:|
| Windows 10     | 3.2.8 |


MongoDB服务的安装非常简单，只有简单的三步骤：
> * 下载并安装MongoDB
* 将MongoDB的安装目录下的bin目录添加到系统环境变量Path下: "***installPath***"/bin
* 使用管理者权限打开CMD，安装服务
<!--more-->

1. 使用命令行安装MongoDB服务：
>
```cmd
mongod --install --serviceName MongoDB --serviceDisplayName MongoDB  --dbpath D:\MongoDB\db  --logpath D:\MongoDB\log\mongo.log --logappend
```
***注：dbpath和logpath指定的目录比如 “D:\\MongoDB\\log”一定要存在，否则会报错***<br>

2. 完成以，就可以在服务中找到一个叫MongoDB的服务了。通过管理员打开CMD，使用`net start MongoDB`,就可以启动mongoDB的服务

3. 使用CMD，输入`mongo`，进入mongo shell

4. 使用mongo的createUser方法创建一个管理员账号，roles对应的是授予的角色列表，使用`show roles`可以查看系统内置的所有的角色
```javascript
    > use admin
  > db.createUser({
      user:"username",
      pwdP:"userPwd",
      roles:["__system"]
      })
```
创建成功后会有提示，你也可以使用`db.system.users.find()`查看是否插入成功。

5.  重装MongoDB服务（如果报错，需将Mongo目录下的.log日志文件删除），加上权限验证
```CMD
mongod  --serviceName MongoDB --serviceDisplayName MongoDB  --dbpath D:\MongoDB\db  --logpath D:\MongoDB\log\mongo.log --logappend --auth --reinstall
```
6. 重启服务
``` python
  net stop MongoDB
  net start MongoDB
```
7. 使用`db.auth("username","userPwd")`验证并登陆,若成功，返回值会是1
```javascript
    use admin
    db.auth("username","userPwd")
```
验证登录成功了就可以操作所有的数据库了
