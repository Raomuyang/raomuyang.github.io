---
title: Spring的InvalidDataAccessApiUsageException异常解决办法
date: 2016-05-16 22:09:32
tags: [Java,Spring]
meta: [java,Spring,Spring MVC]
categories: [Spring,Java]
---
>抛出异常：org.springframework.dao.InvalidDataAccessApiUsageException: Write operations are not allowed in read-only mode (FlushMode.NEVER/MANUAL): Turn your Session into FlushMode.COMMIT/AUTO or remove 'readOnly' marker from transaction definition.

在使用SpringMVC + hibernate开发项目时，使用hibernate进行写操作时抛出InvalidDataAccessApiUsageException的异常，在网上搜索了很多资料，多是以下解决方案，然而没有解决我的问题：
<!--more-->
* 解决延迟加载，在web.xml中配置OpenSessionInViewFilter初始参数：singleSession：true、flushMode：AUTO
```xml
<filter>
	  <filter-name>OpenSessionInViewFilter</filter-name>
	  <filter-class>org.springframework.orm.hibernate3.support.OpenSessionInViewFilter</filter-class>
	  <init-param>
	    <param-name>singleSession</param-name>
	    <param-value>true</param-value>
	  </init-param>
	  <init-param>
	    <param-name>flushMode</param-name>
	    <param-value>AUTO</param-value>
	  </init-param>
</filter>

```
* 我的解决办法
我在异常信息看到一句话：
at:
&nbsp;org.springframework.orm.hibernate3.HibernateTemplate.checkWriteOperationAllowed(HibernateTemplate.java:1175)，然后就想能不能直接关闭它的检查，一试果然成功了
```xml
<bean name="hibernateTemplate" class="org.springframework.orm.hibernate4.HibernateTemplate">
        <property name="sessionFactory">
            <ref bean="sessionFactory" />
        </property>
        <property name="checkWriteOperations">
            <value>false</value>
        </property>
</bean>
```
