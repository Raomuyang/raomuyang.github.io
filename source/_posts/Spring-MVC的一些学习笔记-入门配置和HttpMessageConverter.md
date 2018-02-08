---
title: Spring MVC的一些学习笔记-入门配置和HttpMessageConverter
date: 2016-03-30 08:23:11
tags: Spring MVC
meta: [Spring,Spring MVC, Java]
categories: [Spring,Java]
---
## 1.开始使用Spring MVC
>#### 【1】. 配置web.xml以及在web.xml中配置DispatcherServlet：

>```xml
		 <context-param>
				<param-name>contextConfigLocation</param-name>
				<!—此处指定applicationContext等配置文件的位置-->
				<param-value>classpath:org.package.example</param-value>
		</ context-param >
		<listener>
				<listener-class>
		           org.springframework.web.context.ContextLoaderListener
				</listener-class>
		</listener>
		<servlet>
				<servlet-name>此处定义一个名字</servlet-name>
				<servlet-class>
						org.springframework.web.servlet.DispatcherServlet
				</servlet-class>
				<load-on-start>1</load-on-start>
				<!—以下这段可以不配置-->
				<init-param>
					<param-name>
					 	<!—使用这个指定的话，servlet文件的名字就不是<servlet-name>-servlet.xml，而是servlet-name.xml-->
					</param-name>
					<param-value>
						<!—指定DispatcherServlet的路径-->
					</param-value>
				</init-param>		
		</servlet>
		<servlet-mapping>
				<servlet-name>servlet-name<servlet-name>
				<url-pattern>*.x(如*.html等)</url-pattern>
				<!-指定处理某种后缀的http请求类型-->
		</servlet-mapping>
```
<!--more-->
> 在applicationContext等配置文件中，在最顶上要用到一下这句启动spring容器扫描类包，让注解生效
```xml
		<!-- 扫描类包，将标注Spring注解的类自动转化Bean，同时完成Bean的注入 -->
		<context:component-scan base-package="cn.jxufe"/>
```

***

>####	【2】. 在<servlet-name>-servlet.xml中配置SpringMVC配置文件，定义视图名称解析器
```xml
		<bean
			class=” org.springframework.web.servlet.view.InternalResourceViewResolver”>
				p:prefix="/WEB-INF/views"    <!-设置前缀-->
				p:suffix=".jsp" 			 <!-设置后缀-->
		/>
```
***


>#### 【3】.编写处理请求的控制器Controller
>
* 使用`@Controller`将一个POJO类转换为处理请求的控制器
* 使用`@RequestMapping`映射请求并指定某个方法处理
* 使用`@PathVariable`将URL中的{xxx}占位符绑定到处理方法的入参中
* 使用`@RequestParam`将参数绑定到入参中
* 使用`@CookieValue`和`@RequestHeader`可以将Cookie和报文头属性绑定到入参中
* 更多处理方法签名需查看资料

>**示例：**
>
* ##### @Controller和@RequestMapping的简单示例
```java
		@Controller
		@RequestMapping(“/user”)
		public class UserController{

			//----------1
			@RequestMapping(“/register”)
			public ModuleAndView register(){
					ModuleAndView mav = new ModuleAndView();
					mav.setViewName(“user/register”);
					return mav;
			}
			//-------2
			@RequestMapping(“/register”)
			public String register(){
							return “user/register”;
			}
			//----------------3
			@RequestMapping(“/createUser”)
			public ModuleAndView createUser(User user){
					ModuleAndView mav = new ModuleAndView();
					mav.setViewName(“user/register”);
					mav.addObject(“user”,user);
					return mav;
			}
		}
```
>
*  上面1和2两段代码是等价的，mvc可以自动将String转为mvc模型
*  Register方法只能处理/user/register的请求
*  代码3所示，说明mvc可以自动将表单数据按参数名和入参对象的属性绑定起来
*  /user/**/{userId}表示处理/user/xxx/123或/user/xxx/xxx/123等请求


>* ##### @PathVariable将URL中的{xxx}占位符绑定到处理方法的入参中
```java
		//@RequestMapping("/equary/{userid}")
		@RequestMapping(value = "/equary/{userid}",method = RequestMethod.GET)
		@ResponseBody
		public Object equary(@PathVariable("userid") String userid){
		    System.out.println("equary:" + userid);
		    return "success";
		}
```

>* ##### @RequestMapping的使用
（1）. 通过请求URL进行映射：@RequestMapping(value=”/user”)----和不写value差不多
（2）. 通过请求参数、方法、头进行映射
```java
			@RequestMapping(value=”/user”,method=RequestMethod.POST,params=”userId”)
			Public String test(@RequestParam(“userId”) String userId){
			//Public String test(@RequestParam(value=“userId”,required=false)String userId){
				//do sth
				return “user/index”;
			}
```
> Required默认为true，改为false时表示请求中没有相应的参数也不会报错

***

## 2.使用HttpMessageConverter<T>

>###### (1).HttpMessageConverter的介绍


**HttpMessageConverter** 负责将请求信息转换为一个对象。在Spring中默认的`AnnotationMethodHandlerAdapter`默认装配了以下的HttpMessageConverter：
* StringHttpMessageConverter
* ByteArrayHttpMessageConverter，
* SourceHttpMessageConverter
* XmlAwareFromHttpMessageConverter

如果还需装配其它的HttpMessageConverter，则需要在<servlet-name>-servlet.xml这个web容器中显式地定义

> **示例：**
>
```xml
        <!—定义一个AnnotationMethodHandlerAdapter -->
        <bean
        	class=”org.springframework.web.servlet.mvc.annotation.AnnotationMethodHandlerAdapter”
        	p:messageConverters-ref=”messageConverters”/>
        <!—定义HttpMessageConverter列表 -->
        <util:list id=” messageConverters”>
        	<bean
        	 class=”org.springframework.http.converter.BufferedImageHttpMessageConverter”/>
        	<bean
        	 class=”org.springframework.http.converter.BufferedImageHttpMessageConverter”/>
        	 ...
        		<!-…更多都可以在这里定义-->
        </util:list>
```

在容器中显示定义的AnnotationMethodHandlerAdapter会覆盖掉默认的，，所以默认的四个HttpMessageConverter还需重新装配


>###### （2）使用HttpMessageConverter
* 使用@RequestBody和@ResponseBody进行标注
* 使用HttpEntity<T>/ResponseEntity<T>作为处理方法的入参和返回值

**示例：**

>######		【1】@RequestBody和@ResponseBody的使用

```java
		@RequestMapping(“handle1”)
		Public String handle1(@RequestBody String requestBody){
			System.out.println(requestBody);
			Return “success”;
		}
```
handle1通过@RequestBody自动将请求的报文转换为字符串绑定到requestBody入参中



```java
		@ResponseBody
		@RequestMapping(value=”/handle2/{imageId}”)
		public byte[] handle2(@PathVariable(“imageId”) String imageId) throws IOException{
			System.out.println(“Load image of ”+imageId);
			Resource res=new ClassPathResource(“/image”+imageId+”.jpg”);
			byte[] fileData=FileCopyUtils.copyToByteArray(res.getInputStream());
			return fileData;
		}
```
handle2在方法体中读取一张图片，并将图片作为输出流返回，而@ResponseBody的标识即可将该返回值输出到相应流中，客户端将显示这张图片。
**内部流程：**在handle1方法中，MVC根据@RequestBody的标注查找到相应的HttpMessageConverter，将请求信息转换绑定到requestBody入参上。handle2方法最顶上拥有一个@ResponseBody的注解，返回值为byte[]，spring mvc会根据返回值类型匹配ByteArrayHttpMessageConverter对返回值进行处理，由此将图片数据流输出到客户端


>######		【2】`HttpEntity`和`ResponseEntity`

和`@RequestBody`/`@ResponseBody`类似，**HttpEntity<?>**不但可以访问请求及响应报文体的数据，还可以访问请求和响应报文头的数据。Spring mvc根据<?>泛型类型查找对应的HttpMessageConverter.
>
```java
       @RequestMapping(“/handle”)
        Public String handle(HttpEntity<String> httpentity){
        	long contentLen = httpEntity.getHeaders().getContentLength();
        	System.out.println(httpEntity.getBody());
        }
```
以上，SpringMVC会使用StringHttpMessageConverter将请求报文体及报文头的信息绑定到httpEntity中，在方法体内可以对相应的信息进行访问


```java
        @RequestMapping(value=”/handle/{imageId}”)
        public ResopnseEntity<byte[]> handle(@PathVariable(“imageId”) String imageId)
        throws Throwable{
        				Resource res = new ClassPathResource(“/image”+imageId+”.jpg”);
        byte[] fileData=FileCopyUtil.copyToByteArray(res.getInputStream());
        ResponseEntity<byte[]> responseEntity=
        new ResponseEntity<byte[]>(fileDate,HttpStatus.OK);
        return responseEntity;
        }
```
返回值设置为ResponseEntity的泛型，泛型类型为byte[]，将输出流放入到ResponseEntity中，SpringMVC会自动匹配相应的HttpMessageConverter。效果和@ResponseBody一样。
