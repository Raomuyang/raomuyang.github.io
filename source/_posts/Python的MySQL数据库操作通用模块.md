---
title: Python的MySQL数据库操作通用模块
date: 2016-05-12 18:33:16
tags: [Python,MySQL]
meta: [Python,MySQL]
categories: [Python]
---
> 在使用Python开发爬虫工具的时候，有时候需要把数据存储进MySQL数据库中（尽管现在大多使用NoSQL如MongoDB）,这个时候使用Python写一个类似Java中的数据库访问通用类就很方便了。以下是用Python实现Mysql数据库访问通用类

### 导入MySQLdb模块，实现数据库操作。
```Python
#-*-coding:utf8-*-
import MySQLdb
from importlib import reload
```
另外Python中的字符集特别麻烦，所有在文件头将其设为utf8的字符集

### 定义数据库访问通用类
使用MySQLdb中的connect(host = host,user = user, passwd = password, db = db, port = port,charset= 'utf8')进行数据库连接。直接上代码：
<!--more-->
```Python
class MySqlDBHelper(object):
	#将数据库连接配置作为参数传入
    def __init__(self,host,user,password,db,port):
        self.connecter = self.getConnect(host,user,password,db,port)

    def __del__(self):
        try:
            self.connecter.close()
        except:
            print("connecter close ERROR")

    def getConnect(self,host,user,password,db,port):
        #python3.x之后，str字符集默认是Unicode，故没有了encode这个内置函数
        #将数据库的字符集设为utf8后，就不再发生 'latin-1' codec can't encode character '\u8d5e'
        con = MySQLdb.connect(host = host,user = user, passwd = password, db = db, port = port,charset= 'utf8')
        return con

    def query(self,sql,arg = None):
        """ Return the results(Tuples) after executing SQL statement """
        cur = self.connecter.cursor()
        cur.execute(sql,arg)
        result = cur.fetchall()
        cur.close()
        return result

    def insert(self,table,args):
        """ insert a row into the table,please make sure that the location of the parameter in the line is correct"""
        num = args.__len__()
        sql = 'insert into ' + table + " values(";
        i = 0
        while i< num:
            sql += '%s'
            i += 1
            if i == num:
                sql += ')'
            else:
                sql += ','
        cur = self.connecter.cursor()
        r = cur.execute(sql,args)
        self.connecter.commit()

        cur.close()
        return r

    def batchInsert(self, table, values):
        """ Batch insertions of row data into :table.Values must be a LIST of TUPLES """
        num = values[0].__len__()
        sql = 'insert into ' + table + " values(";
        i = 0
        while i< num:
            sql += '%s'
            i += 1
            if i == num:
                sql += ')'
            else:
                sql += ','
        cur = self.connecter.cursor()
        r = cur.executemany(sql,values)
        self.connecter.commit()
        cur.close()
        return

    def update(self,sql,args=None):
        """ Update or delete, args must be a list"""
        try:
            cur = self.connecter.cursor()
            r = cur.execute(sql,args)
            self.connecter.commit()
            cur.close()
            return r
        except:
            print("Update/Delete Error:"+sql)
            return 0

    def createDatabase(self,name):
        cursor = self.connecter.cursor()
        sql = "create database " + name
        cursor.execute(sql)
        return True


    def createTable(self,tableName):
        cursor = self.connecter.cursor()
        sql = "create database " + tableName
        cursor.execute(sql)
        return True

    def getAllDatabase(self):
       dbList = []
       cursor = self.connecter.cursor()
       cursor.execute("show databases")
       for db in cursor.fetchall():
           dbList.append(db[0])
       return dbList

    def getAllTables(self,database):

        cursor = self.connecter.cursor()
        cursor.execute("use "+database)
        cursor.execute("show tables")
        tables = []
        for tab in cursor.fetchall():
            tables.append(tab)
        return tables


    def createTable(self,db,tableName,fields,keys,types):
        """db 数据库名, fields: 字段列表，keys: 主键列表，types:字段对应的类型"""

        if fields == None or fields.__len__() == 0 or fields.__len__() != types.__len__():
            return False
        if keys == None:
            keys = []

        self.connecter.cursor().execute("use "+db)
        if(tableName not in self.getAllTables(db)):
            sql = "create TABLE " + tableName;
            fs = "("
            i = 0
            while i < fields.__len__():
                if fs != "(":
                    fs +=","
                fs +=( fields[i]+" " + types[i] + " ")
                i += 1

            i = 0
            pk = ""
            if keys.__len__() != 0:
                while i < keys.__len__():
                    if pk == "":
                        pk += "primary key("+keys[i]
                    else:
                        pk += ","+keys[i]
                    i+=1
            pk+=")"
            if pk != "":
                fs+=","+pk
            fs += ")"
            sql += fs
            self.connecter.cursor().execute(sql)
            print("create_table Success")
            return True
        else:
            return False

```
