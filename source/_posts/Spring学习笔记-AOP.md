---
title: Spring学习笔记-AOP,配置切面和声明事务
date: 2016-03-30 09:46:10
tags: [Java, Spring, Spring MVC, AOP, Aspect, Advisor]
meta: [Spring MVC, AOP, Aspect, Advisor, AOP, 配置切面和声明事务]
categories: [Spring,Java]
---
### 1：Aspect切面的配置

>#### （1）通过@Aspect注解定义切面，调用被定义为切点的方法时，会自动加入增强
```java
@Aspect//注解将PreGreetingAspect定义为一个切面

public class PreGreetingAspect{

            @Before("execution(* greetTo(..))")//@Before,@After等注解表示增强类型

            public void beforeGreeting(){

         System.out.println("-----before advice-----");

}
```
<!--more-->   

*`@Before中的"execution(* greetTo(..))"为切点表达式函数，目的是匹配切入点，* greetTo(..)是通过正则表达式匹配目标类的greetTo()方法`*

>
###### 【1】增强类型有如下几种
* @Before: 前置增强（value , argNames）
* @AfterReturning: 后置增强（value, pointcut,returning, argNames）
* @Around: 环绕增强（value,argNames）
* @AfterThrowing: 抛出增强（value,pointcut,throwing,argNames）
* @After: Final增强(value,argNames)
* @DeclareParents: 引介增强(value,defaultImpl)
>
###### 【2】切入点函数
* execution() 最常用的切点函数
	+ 通过方法签名定义切点：
		+ `execution(public * *(..))`  匹配方法签名为public的切点
		+ `execution(* *To(..))` 匹配方法名中带To的方法为切点
	+ 通过类定义切点
		+ `execution(* com.package.Waiter.*(..))`匹配Waiter接口中的所有方法
	+ 通过类包定义切点  
		+ `.*`：匹配包下所有类
		+ ..*：匹配包、子包下所有类
		+ `* com..*.*Dao.find*(..)` 匹配所有前缀为com的包和子包下的后缀为Dao的类（接口）的所有前缀为find的方法
    + 通过方法的入参定义切点  
		+ execution(*joke(int,String,*))
		+ execution(*joke(int,…))
* args() 在目标类方法的入参是指定的类时（包含子类），匹配切点
	+ args(com.test.Waiter)

*` args和execution(* *(com.test.Waiter))的区别在于，execution是针对方法签名而言的，只匹配入参为(Waiter waiter)的，args还匹配(NaiveWaiter naiveWaiter)`*
* target() 按目标类类型匹配
	+ target(M)表示若目标类匹配M，则目标类所有方法都匹配切点
* within() 通过类匹配模式串声明切点，不能做方法级的匹配
	+ within(com.test.*)匹配test包下所有类
	+ within(com.test..*)匹配test包和子包下所有类

*`**@within()**,** @target()**, **@annotation()**,** args()** 都是只接受注解类名作为入参`*
###### 【3】切点复合运算：可以通过运算符，通过多个切点函数匹配切点
 **示例：**
```java
     @After("wintin(com.test.*) && execution(* greetTo(..))")
		 @Before("!target(com.test.Waiter) && execution("* serveTo(..)")")
		 @AfterReturning("target(com.test1..*) || target(com.test2..*)")
```


>#### （2）基于Schema配置切面

* 首先定义增强方法的bean
* 然后配置<aop:config>:
	+ Config中有<aop:pointcut>,<aop:aspect>，如果pointcut直接在config中直接定义，则须满足前面的顺序。
	+ 可以定义多个`<aop:config>`, `<aop:config>`中还可以直接定义`<aop:advisor>`
	+ `<aop:aspect>` 须配置的信息有*ref=*（引用增强方法bean），*method=*（增强方法）,*pointcut/pointcut-ref=*
	+ <`aop:pointcut>`中须配置的有 *id=,expression=*（定义切点）
> 【1】简单的示例
```java
<bean id="adviceMethods" class="com.test.AdviceMethods"/>
     <aop:config proxy-target-class="true">
	     <aop:aspect ref="adviceMethods">
		 	<aop:before pointcut="target(com.test.Waiter) and execution(* greetTo(..))" method="preGreeting"/>
		 </aop:aspect>    
     </aop:config>   
</bean>       
```
*`这里的切入点为一个匿名切入点，只能在这个aop:aspect里面使用proxy-target-class="true"表示使用CGLib动态代理`*

>【2】配置命名的切入点
```xml
<aop:config proxy-target-class="true">
	<aop:aspect ref="adviceMethods">
		<aop: pointcut id="greetToPointcut"expression="target(com.test.Waiter) and execution(* greetTo(..))" />
		<aop:before pointcut-ref="greetToPointcut" method="preGreeting"/>
	</aop:aspect>    
</aop:config>
```
> aop:config中可以定义多个aop:aspect，所以配置命名pointcut就可以被不同的增强切面所访问（pointcut在aspect外面）
```xml
<aop:config proxy-target-class="true">
	<aop: pointcut id="greetToPointcut" expression="target(com.test.Waiter) and execution(* greetTo(..))" />
	<!--第一个切面-->
	<aop:aspect ref="adviceMethods">
		<aop:before pointcut-ref="greetToPointcut" method="preGreeting"/>
	</aop:aspect>    
	<!--第二个切面-->
	<aop:aspect ref="adviceMethods">
		<aop:before pointcut-ref="greetToPointcut" method="postGreeting"/>
	</aop:aspect>    
</aop:config>
```

>【3】配置Advisor，advisor是切面和增强的复合体
```xml
<aop:config proxy-target-class="true">
	<aop: pointcut id="greetToPointcut" expression="target(com.test.Waiter) and execution(* greetTo(..))" />
	<aop:advisor advice-ref:"testAdvice" pointcut-ref="greetToPointcut"/>
</aop:config>
<bean id="testAdvice" class="com.test.TestBeforeAdvice">
```
*【Advisor中的advice所依赖的类TestBeforeAdvice必须是实现了MethodBeforeAdvice等接口的advisor类】*
```java
public class TestBeforeAdvice implements MethodBeforeAdvice{
         public class before(Method method,Object[] args, Object target)throws Throwable{
                   System.out.println("------Test Before Advice");
         }
}
```

### 2.  事务通知的声明
>#### （1）在xml中配置声明事务

+ 通过tx Schema中定义的<tx:advice>声明事务通知。使用前须先将schema定义添加到<beans>根元素中去
+ 声明事务通知后，通过aop织入，在<aop:config>元素中声明一个advisor，将事务与切入点关联起来。
+ 配置dataSource -> 声明事务管理器，包裹数据源 –>
+ 声明事务通知，transaction-manager参数引用事务管理器 ->
+ 配置<aop:config>，定义切入点<aop:pointcut>在<aop:advisor>设置属性pointcut-ref和advice-ref，advice-ref为刚刚声明的事务通知 ->
+ 事务的配置完成


*a.声明事务管理器，将dataSource包裹*
```xml
<bean
	id="transactionManager"class="org.springframework.jdbc.datasource.DataSourceTransactionManager"
	p:dataSource-ref="dataSource"/>
```
*b.声明事务通知,引用事务管理器*
```xml
<tx:advice id="txAdvice" transaction-manager="transactionManager">
         <tx:attributes>
                   <tx:method name="*"/>
         </tx:attributes>
</tx:advice>
```

*c.声明事务通知需要通知方法（即织入事务管理）*
```xml
<aop:config proxy-traget-class="true">
         <!—定义切入点-->
         <aop:pointcut id="serviceMethod"expression="execution(* com.test.service..*(..))"/>
         <!--定义增强类，引用前面声明的事务通知-->
         <aop:advisor  pointcur-ref="serviceMethod" advice-ref="txAdvice">
</aop:config>
```

>#### （2）使用@Transactional，通过annotation声明事务
简单地使用@Transcational注解来标注方法，将方法定义为支持事务处理的（只能标注共有方法。也能标注类级的，则这个类中所有的共有方法都被定义为支持事务处理的）。
```java
@Transactional
public void save() {
   // TODO Auto-generated method stub
   userDao.save();
}
```

*使用这种方法，则在bean配置文件中只需启用<tx:annotation-driven>元素,如下所示：*
```xml
<tx:annotation-driven
	proxy-target-class="false"
	transaction-manager="transactionManager"/>
```
*事务处理器的名称是transactionManager的话，可以省略transaction-manager这个属性*


>#### （3）配置数据源及hibernate
+ 配置数据源 ->
+ 配置sessionFactory ->
+ 配置hibernateTemplate，设置属性sessionFactory为引用刚刚配置的sessionFactory ->
+ 配置transactionManager，设置属性sessionFactory为引用刚刚配置的sessionFactory

*配置数据源示例*
```xml
<bean id="dataSource" class="org.apache.commons.dbcp.BasicDataSource"
	destroy-method="close"
	p:driverClassName="com.mysql.jdbc.Driver"
	p:url="jdbc:mysql://localhost:3306/sampledb"
	p:username="root"
	 p:password="123456" />
```


*配置sessionFactory*
```xml
<bean id="sessionFactory"
	class="org.springframework.orm.hibernate3.annotation.AnnotationSessionFactoryBean">
     <!—引用数据源dataSource-->
	<property name="dataSource"><ref local="dataSource" /></property>

	<!—hibernate参数-->
	<property name="hibernateProperties">
		<props>
			<!-- 配置Hibernate的方言-->
			<prop key="hibernate.dialect">
				org.hibernate.dialect.MySQLDialect
			</prop>
			<prop key="hibernate.hbm2ddl.auto">update</prop>
			<prop key="hibernate.show_sql">true</prop>
			<prop key="current_session_context_class">thread</prop>
		</props>
	</property>

	<!—设置要扫描的包->
	<property name="packagesToScan">
		<list>
			<value>cn.jxufe.domain</value>
		</list>
	</property>

	<list>
		<value>cn.jxufe.domain.User</value>
	</list>
	</property> -->
</bean>
```
> 使用hibernate的话，无论是template还是transactioManager都要特别地去定义
hibernateTemplate引用的包不是在jdbc中，而是hibernate3中，参数sessionFactory引用的是前面包裹了数据源的sessionFactory:
```xml
 <bean name="hibernateTemplate"
	class="org.springframework.orm.hibernate3.HibernateTemplate">
        <property name="sessionFactory">
               <ref bean="sessionFactory"/>
     </property>
 </bean>
```


> 使用hibernate的话，事务管理器也是继承自hibernate3，还有一点和普通的transactionManager不同的是，这里不引用数据源，而是引用sessionFactory
```xml
 <bean id="transactionManager"
	class="org.springframework.orm.hibernate3.HibernateTransactionManager">
        <property name="sessionFactory" ref="sessionFactory"/>
 </bean>
```

> 使用annotation定义事务

false默认用JDK动态代理，true使用cglib动态代理
```xml
<tx:annotation-driven proxy-target-class="false" transaction-manager="transactionManager"/>
```
