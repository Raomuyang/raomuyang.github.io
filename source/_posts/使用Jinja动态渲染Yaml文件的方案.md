---
title: 动态渲染Yaml文件（使用 模板映射 + Jinja2 方案）
date: 2019-06-05 15:48:14
tags: [yml, Jinja2]
meta: [参数渲染, yml]
---

最近在开发一个工具时遇到了一个根据输入参数渲染yml文件的问题:

* 需要在yaml样板的指定的位置上填入指定的值，yml样板随时可能更新
* 需要根据输入参数以及对应字段的生成规则动态生成对象、数组（长度不固定）、字符串等各种类型的值

这种情况下，最先想到的就是直接使用占位符或者模板语言。但是经过实践发现了两个问题：

1. yaml文件样板更新时，必须从旧模板上的迁移占位符，增大了维护的负担（特别是生产中用到的yaml文件通常有上千行）
2. 生成规则不固定，需要在工具中硬编码指定某些特定属性的生成规则，使业务逻辑高度耦合

所以使用占位符或者模板语言直接作用在yaml样板上思路就是错的，我们应该通过一个中间的配置来定义yml文件的生成规则，这样才能使工具和业务逻辑解耦合，并且降低维护的难度。

<!-- more -->

## 二维结构的转换

首先要解决的是，如何在yml结构的指定位置插入指定的值：即`Key - Value`映射关系的定义。yml和json是等价的，不过层层嵌套的结构显然增大了模板渲染的难度，我们可以通过这种方式将多维的结构转为二维的：

```yml
Inputs:
  datas:
    - data1
    - data2
    - data3  
```

转为二维的结构：

```properties
Inputs.datas.$0 = data1
Inputs.datas.$1 = data2
Inputs.datas.$2 = data3
```

有没有想起MongoDB的查询语句或者Spring boot的配置？没错，这就是参考`application.yml`转写`application.properties`的格式，将yaml文件展开为二维的。 转为二维之后，模板就变成了简单的键值渲染逻辑：通过`Key Name`定位到yaml的指定属性将`Value`填充

## 参数与属性的映射

如果只是简单地定义了一些属性的值，那么到前文提到的键值映射解析就结束了，但是我们的场景是通过 `输入` + `规则`生成指定属性的值，举个例子:

输入参数：

```json
{
    "project_id": "F19",
    "subproject_id": "HUM",
    "sample_id": "AW",
    "lane_id": "B2"
}
```

目标输出：

```yml
Inputs:
  loaddata_fq:
    data:
    - name: "F19/HUM/AW/clean_data/B2.fq.gz"
  loaddata_bam:
    data:
    - name: "F19/HUM/AW/clean_data/B2.bam1.bam"
    - name: "F19/HUM/AW/clean_data/B2.bam2.bam"
    - name: "F19/HUM/AW/clean_data/B2.bam3.bam"
    - name: "F19/HUM/AW/clean_data/B2.bam4.bam"
    - name: "F19/HUM/AW/clean_data/B2.bam5.bam"
Outputs:
  storedata:
    data:
    - name: "F19/HUM/AW/clean_data/B2.fq.clean.check"

```

观察输出规则，不难得出以下映射规则

```ini
Outputs.loaddata_fq.data.$0.name = "{{project_id}}/{{subproject_id}}/{{sample_id}}/clean_data/{{lane_id}}.fq.clean.check"

Inputs.loaddata_fq.data.$0.name = "{{project_id}}/{{subproject_id}}/{{sample_id}}/clean_data/{{lane_id}}.fq.gz"

Inputs.loaddata_fq.data.$0.name = "{{project_id}}/{{subproject_id}}/{{sample_id}}/clean_data/{{lane_id}}.bam0.bam"
Inputs.loaddata_fq.data.$1.name = "{{project_id}}/{{subproject_id}}/{{sample_id}}/clean_data/{{lane_id}}.bam1.bam"
Inputs.loaddata_fq.data.$2.name = "{{project_id}}/{{subproject_id}}/{{sample_id}}/clean_data/{{lane_id}}.bam2.bam"
Inputs.loaddata_fq.data.$3.name = "{{project_id}}/{{subproject_id}}/{{sample_id}}/clean_data/{{lane_id}}.bam3.bam"
Inputs.loaddata_fq.data.$4.name = "{{project_id}}/{{subproject_id}}/{{sample_id}}/clean_data/{{lane_id}}.bam4.bam"
```

但是 `loaddata_bam`参数的映射如果需要手写那太痛苦了，假设有100个bam的输入，我们就得写100条映射规则，这显然不是我们想看到的。
没有什么是一条`for`循环不能解决的，如果有，就加个`if`（呸）。这个时候模板语言就派上用场了，我马上联想到其它模块中用到的[Jinja](http://docs.jinkan.org/docs/jinja2/templates.html)模板，不但能够将参数渲染到文件中，还能解决动态生成规则的问题：

```ini
Outputs.loaddata_fq.data.$0.name = "{{project_id}}/{{subproject_id}}/{{sample_id}}/clean_data/{{lane_id}}.fq.clean.check"

Inputs.loaddata_fq.data.$0.name = "{{project_id}}/{{subproject_id}}/{{sample_id}}/clean_data/{{lane_id}}.fq.gz"
{% for n in range(5)  %}
Inputs.loaddata_fq.data.${{n}}.name = "{{project_id}}/{{subproject_id}}/{{sample_id}}/clean_data/{{lane_id}}.bam{{n}}.bam"
{% endfor %}
```

如此便解决了动态生成规则的问题，这样就将属性值的生成规则抽离到配置文件中。通过Jinja模板渲染后，就可以得到完整的`键-值`映射关系，剩下的通过`Key Name`找到指定的属性就不是什么难事了。

### 使用宏定义更高级的生成规则

不仅仅是前面示例中的列表生成，我们甚至可以通过宏定义更复杂的规则：

1. 声明宏：根据lane_id生成对象

```jinja
{%macro _loadbamData(lane_id, prefix, pos) -%}
{"enid": null, "name": "{{cloud_out_dir}}/tmp/fq_bam/{{sample_id}}/{{lane_id}}/{{lane_id}}.{{prefix}}{{pos}}.bam", "property": {"block_file": {"block_name": null, "is_block": false, "split_format": "default"}} }
{%- endmacro %}
```

2. 声明宏：根据坐标生成`loadnode_bam<pos>`的值，比如loadnode_bamY

```jinja
{% macro loadbamList(prefix, pos) -%}
[{%for lane_id in lane_id_list -%}
{{_loadbamData(lane_id, prefix, pos)}} {%-if not loop.last%}, {%endif-%}
{%-endfor%}]
{%- endmacro%}
```

3. 通过调用生成`loaddata_node_bam1` 到 `loaddata_node_bam22`

```jinja
{%-for index in range(1, 23) -%}
loaddata_node_bam{{index}}.data = {{ loadbamList('bam', index)}}
{%endfor-%}
```

> 更多Jinja模板的语法请参考[文档](http://docs.jinkan.org/docs/jinja2/templates.html)

## 映射文件的管理、解析，渲染到yml文件

我们回顾一下参数映射的大体思路：

1. 将yml文件中的属性转为二维结构
2. 使用Jinja模板填充各个属性的映射规则
3. 如果有动态生成规则，使用"宏"

作为一个程序员，多多少少都有点代码洁癖，如果各种宏定义和键值映射的声明混在一起，一定非常难受；而且参数直接写在键值映射中，没有在一个地方统一声明，可能不便维护，既然已经抽离出一个独立的映射配置，那么就进一步完善一下，将其声明为一个伪`ini`文件(使用`ini`配置只是一种方案，我们只要利用Jinja渲染后的输出文件消除了宏定义和Jinja模板的特性，可以利用任意想要的中间配置输出)

### 映射管理

#### DECLARE

在`DECLARE`下声明参数，为处理程序提前获知合法参数留入口

```ini
[DECLARE]
; 这里声明参数
project_id = {{project_id}}
subproject_id = {{subproject_id}}
sample_id = {{sample_id}}
cloud_out_dir ={{cloud_out_dir}}
lane_id_list = {{lane_id_list}}
reference_buildversion = {{reference_buildversion}}
date = {{date}}
task_name = {{task_name}}
```

#### MAPPING

在`MAPPING`下声明映射，如有动态的生成规则，尽量使用宏的调用来，不直接在这里定义宏

```ini
[MAPPING]
Outputs.loaddata_fq.data.$0.name = "{{project_id}}/{{subproject_id}}/{{sample_id}}/clean_data/{{lane_id}}.fq.clean.check"
Inputs.loaddata_fq.data.$0.name = "{{project_id}}/{{subproject_id}}/{{sample_id}}/clean_data/{{lane_id}}.fq.gz"

{% for n in range(5)  %}
Inputs.loaddata_fq.data.${{n}}.name = "{{project_id}}/{{subproject_id}}/{{sample_id}}/clean_data/{{lane_id}}.bam{{n}}.bam"
{% endfor %}

{%-for index in range(1, 23) -%}
loaddata_node_bam{{index}}.data = {{ loadbamList('bam', index)}}
{%endfor-%}
```

#### MACROS

将宏定义在`MACROS`下，避免与参数、映射的声明混在一起

```ini
[MACROS]

{%macro _loadbamData(lane_id, prefix, pos) -%}
{"enid": null, "name": "{{cloud_out_dir}}/tmp/fq_bam/{{sample_id}}/{{lane_id}}/{{lane_id}}.{{prefix}}{{pos}}.bam", "property": {"block_file": {"block_name": null, "is_block": false, "split_format": "default"}} }
{%- endmacro %}

{% macro loadbamList(prefix, pos) -%}
[{%for lane_id in lane_id_list -%}
{{_loadbamData(lane_id, prefix, pos)}} {%-if not loop.last%}, {%endif-%}
{%-endfor%}]
{%- endmacro%}

```

### 映射解析


当定义好一个映射模板后，我们只须以下三步就能完成最终的yaml文件输出：

1. 通过使用Jinja渲染，映射文件。就像前面我们准备的那样，我们可以在渲染参数后得到一个`ini`配置文件
2. 解析渲染后的`ini`配置，从中获取键值映射
3. 读取yaml样板，通过`Key Name`找到yaml对象中的属性并赋值

当然这里面一定会碰到一些其它的问题，比如像我说的那样使用`ini`配置就会碰到映射类型的问题（如何区分`str`和`number`），还有如何区分空字符串`""`和和`null`的问题。当然这些都是实现上的一些细节，通过编码和中间配置的选择就能处理，我这里也只是简单谈谈我是“如何将大象装进冰箱里的”。

> 另外，如果想知道我的具体实现代码，可以参考这个工具 [`gparams`](https://pypi.org/project/gparams/)，这是我为了解决前方提到的问题开发的python库。当然这个并不是完全通用的，里面结合实际的业务特点做了一些定制

> 关于Jinja模板对语言支持的问题，Java也有相关的工具库用于处理渲染： [Jinjava](https://github.com/HubSpot/jinjava)，当然我们也是可以选择其它模板语言的
