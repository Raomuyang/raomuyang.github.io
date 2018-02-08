---
title: 'Spring的R、S、C三层代理模式的思考 [附]注入方式  Hibernate事务'
date: 2016-06-12 16:00:30
tags: [Spring, Hibernate, 事务, Spring配置, Java]
meta: [Spring, Hibernate, 事务, Spring配置]
categories: [Spring,Java]
---
Spring的repository、service、controller三层之间的交互，应该使用代理模式为佳。以service和controller通信为例：
>
- 定义UService接口
- UServiceImpl类实现Service接口，并使用@Service/@Service("name") 注解将ServiceImpl声明为Spring的service类
- Controller中注入UService，通过UService中的方法调用UServiceImpl中的业务逻辑

以上，使用代理模式，更进一步地实现层与层之间解耦和
>
-  面向接口的编程
- UServiceImpl中的其它接口不一定要和UService中一致，只需经过UserService将Controller的意图转发给UServiceImpl ，再通过UServiceImpl中维护的URepository对象，将UService的意图转发到Repository层。

<!--more-->

**Service**
```java
public interface UserService {

    public User regist(User user);

    public boolean login(String userName, String pwd);

    public boolean update(User user);

}
```

**ServiceImpl**
```java
@Transactional(readOnly = false)
@Service
public class UserImpl implements UserService {

   //@Autowired也一样
   private UserDao userDao;

   @Resource
   public void setUserDao(UserDao userDao) {
      this.userDao = userDao;
   }

   @Override
   public User reigst(User user) {
      // TODO Auto-generated method stub
      doSomething()
      return userDao.save(user);
   }

   @Override
   public boolean login(String userName, String pwd) {
      // TODO Auto-generated method stub
        doSomething()
        return userDao.queryByUserNameAndPwd(userName,pwd) == null ;
   }

   @Override
   public boolean update(User user) {
      // TODO Auto-generated method stub
      return userDao.update(user);
   }

   public void doSomething(){
        //do something  假设这是ServiceImpl中不同于Service接口的方法
   }

}
```

**Controller**
```java
@RestController
@RequestMapping(value = "/user/rest")
public class UserRestController {
    @Autowired
    private UserService userService;
}
```

#### 注入方式

@Autowired  @Resource

- @Autowired  是Spring的注解，@Resource是Java EE自带的注解
- @Autowried  不能直接指定按name注入，需要配合 @Qualifier("userDao") 才能实现按name指注入定
- @Resource 可以按照name指定也可以按照type指定

> 主要区别：@Autowired是默认按照类型装配的 ，@Resource默认是按照名称装配的

```java
@Autowired
private UserDao userRepository;//会直接按照userRepository这个字段注入

@Resource
private UserDao userDao;//当@Resource直接注解字段，则不用写set方法

@Autowired
private UserDao userDao;

@Resource
public void setUserDao(UserDao userDao) {
     this.userDao = userDao;
}

//区别
@Autowired
@Qualifier("abc")
private UserDao userDao;

@Resource(name="abc")
private UserDao userDao;
```

https://www.zhihu.com/question/39356740​

#### Hibernate的配置事务

Hibernate使用了二级缓存，其中利用将数据操作缓存在SessionFactory中，从而减少与数据库交互的，加快查询速度，只有commit之后才会将删改操作同步到数据库中【具体须了解Hibernate的二级缓存】
在Spring + Hibernate的项目中，Repository层中的每一个涉及到删改操作的方法，如果都需要声明和提交事务，就失去了Spring的AOP的优势，因此我们可以通过配置事务，避免这一繁琐的过程：
```xml
<bean id="transactionManager"
    class="org.springframework.orm.hibernate4.HibernateTransactionManager">
    <property name="sessionFactory" ref="sessionFactory"></property>
</bean>

<bean name="hibernateTemplate" class="org.springframework.orm.hibernate4.HibernateTemplate">
    <property name="sessionFactory">
        <ref bean="sessionFactory" />
    </property>
</bean>
```

***配置好之后，使用@Transactional(readOnly = false)注解为方法声明事务***

我们在一个项目中，是在Service层，注解类级的事务，也可以注解在Repository层
```java
@Transactional(readOnly = false)
@Service
public class UserImpl implements UserService {

   @Autowired
   private UserDao userDao;

   @Override
   public User reigst(User user) {
      // TODO Auto-generated method stub
      doSomething()
      return userDao.save(user);
   }

   @Override
   public boolean login(String userName, String pwd) {
      // TODO Auto-generated method stub
        doSomething()
        return userDao.queryByUserNameAndPwd(userName,pwd) == null ;
   }

   @Override
   public boolean update(User user) {
      // TODO Auto-generated method stub
      return userDao.update(user);
   }

   public void doSomething(){
        //do something  假设这是ServiceImpl中不同于Service接口的方法
   }
}
```
> ***实际上应该注解在Repository层，我们之前做一个项目，把它注解在了BaseDao上，结果报错不起作用，后来急急忙忙地就把它注解到了Service层。不能注解在抽象类和接口上***
