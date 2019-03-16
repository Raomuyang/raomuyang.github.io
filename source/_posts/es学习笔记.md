---
title: Elasticsearch学习笔记
date: 2019-03-15 00:50:39
tags: [写点小玩具]
---

> Initially, we spoke about an “index” being similar to a “database” in an SQL database, and a “type” being equivalent to a “table”. This was a bad analogy that led to incorrect assumptions. [[ref]][1]

> 本文参考《Elasticsearch权威指南》

## 基础概念

<!-- more -->

### 映射

分析器自动通过映射将查询、域中的数据映射成不同的类型（整型、字符串、日期等）:

* which string fields should be treated as full text fields.
* which fields contain numbers, dates, or geolocations.
* whether the values of all fields in the document should be indexed into the catch-all `_all` field.
* the format of date values.
* custom rules to control the mapping for dynamically added fields.

>  索引中每个文档都有 类型 。每种类型都有它自己的 映射 ，或者 模式定义 。映射定义了类型中的域，每个域的数据类型，以及Elasticsearch如何处理这些域。映射也用于配置与类型有关的元数据。[[ref]][2]

[es 6.0以上，多个映射类型将被弃用，一个索引只允许一个映射类型]

#### 查看映射

使用 `/<index>/_mapping/<_type>`查看指定类型的映射

```shell
> curl http://192.168.1.103:9200/gb/_mapping/tweet | jq

# resp
{
  "gb": {
    "mappings": {
      "tweet": {
        "properties": {
          "date": {
            "type": "date"
          },
          "name": {
            "type": "text"
          },
          "tweet": {
            "type": "text",
            "analyzer": "english"
          },
          "user_id": {
            "type": "long"
          }
        }
      }
    }
  }
}
```


#### 创建映射

```shell
curl -X PUT "192.168.1.103:9200/gb" -H 'Content-Type: application/json' -d'
{
  "mappings": {
    "tweet" : {
      "properties" : {
        "tweet" : {
          "type" :    "text",
          "analyzer": "english"
        },
        "date" : {
          "type" :   "date"
        },
        "name" : {
          "type" :   "text"
        },
        "user_id" : {
          "type" :   "long"
        }
      }
    }
  }
}
'


# resp

{
  "acknowledged": true,
  "shards_acknowledged": true,
  "index": "gb"
}
```


尽管你可以 `增加` 一个存在的映射，你不能 `修改` 存在的域映射。我们可以更新一个映射来添加一个新域，但不能将一个存在的域从 `analyzed` 改为 `not_analyzed` , 只能将其重新索引 [[reindex]][4] [[create]][5]


```shell

# 创建索引 （"settings可省略"），mapping在创建索引时指定
curl -X PUT "192.168.1.103:9200/new_twitter" -H 'Content-Type: application/json' -d'
{
  "settings" : {
        "index" : {
            "number_of_shards" : 3,
            "number_of_replicas" : 2
        }
  },
  "mappings": {
    "tweet" : {
      "properties" : {
      }
    }
  }
}
'

# reindex原来的数据
curl -X POST "192.168.1.103:9200/_reindex" -H 'Content-Type: application/json' -d'
{
  "source": {
    "index": "twitter"
  },
  "dest": {
    "index": "new_twitter"
  }
}
'

# 删除旧的索引
curl -X DELETE "192.168.1.103:9200/twitter"

```
> 如果不改变映射类型，指向重命名一个`field`，那么引入 [alias][6] 可能更合理。

#### 多领域

> A mapping type contains a list of fields or properties pertinent to the document

以一条日志的映射类型为例（省略部分字段），一个属性可以包含多个领域信息（fields）：

```json
{
    "mappings": {
        "logs": {
            "properties": {
                "logdate": {
                    "type": "text",
                    "fields": {
                        "keyword": {
                            "type": "keyword",
                            "ignore_above": 256
                        }
                    }
                },
                "message": {
                    "type": "text",
                    "fields": {
                        "keyword": {
                            "type": "keyword",
                            "ignore_above": 256
                        }
                    }
                },
                "op_elapsed": {
                    "type": "long"
                },
                "thread": {
                    "type": "text",
                    "fields": {
                        "keyword": {
                            "type": "keyword",
                            "ignore_above": 256
                        }
                    }
                },
                "user": {
                    "type": "text",
                    "fields": {
                        "keyword": {
                            "type": "keyword",
                            "ignore_above": 256
                        }
                    }
                }
            }
        }
    }
}
```

> 为了不同目的以不同的方式索引相同的字段通常很有用，比如一个字符串属性可以被索引为`text field`用于全文检索，同时又可以作为`keyword field`用于排序或聚合。*又或者你可以分别以标准分析器、英语分析器、法语分析器索引一个`string field` (Alternatively, you could index a string field with the standard analyzer, the english analyzer, and the french analyzer.)*
以上，是`multi-fields`的目的，大部分datatypes支持通过`fields`参数支持多领域

#### 避免一个索引中定义过多的 field (属性? properties?)

Defining too many fields in an index is a condition that can lead to a mapping explosion, which can cause out of memory errors and difficult situations to recover from.[[ref]][3]

### 索引

一个索引对应了一个映射类型（ES6.0+）, 在创建索引时可以同时指定映射类型，使数据可以自动被索引

#### 创建

```shell
# 创建索引 （"settings可省略"），mapping在创建索引时指定
curl -X PUT "192.168.1.103:9200/new_twitter" -H 'Content-Type: application/json' -d'
{
  "settings" : {
        "index" : {
            "number_of_shards" : 3,
            "number_of_replicas" : 2
        }
  }
}
```

#### 删除索引

* 删除一个索引： `DELETE /index-name`
* 删除多个： `DELETE /index1,index2`, `DELETE /index-*`

#### alias

```python
# POST /_alias
{
    "actions": [
        { "remove": { "index": "my_index_v1", "alias": "my_index" }},
        { "add":    { "index": "my_index_v2", "alias": "my_index" }}
    ]
}
```
将别名`my_index`从旧索引`my_index_v1`移除，添加到新索引`my_index_v2`，可实现索引迁移的平滑过渡

## 搜索

### URL字符串简单搜索 (query string search)
#### 空查询

不带任何限制查询所有的结果： `GET: /_search/`

```json
{
   "hits" : {
      "total" :       14,
      "hits" : [
        {
          "_index":   "us",
          "_type":    "tweet",
          "_id":      "7",
          "_score":   1,
          "_source": {
             "date":    "2014-09-17",
             "name":    "John Smith",
             "tweet":   "The Query DSL is really powerful and flexible",
             "user_id": 2
          }
       },
        ... 9 RESULTS REMOVED ...
      ],
      "max_score" :   1
   },
   "took" :           4,
   "_shards" : {
      "failed" :      0,
      "successful" :  10,
      "total" :       10
   },
   "timed_out" :      false
}
```

* took 请求耗时 (ms)
* _shards 参与的分片信息
* timeout 查询是否超时（可以通过设置 ?timeout=10ms限定查询时间，请求超时之前，es会返回已查询到的结果）
* hits 包含10个（默认）查询到的结果，可以直接使用返回的文档

#### 带索引、映射类型的查询

> Each document had a meta-field containing the type name: `_type`

es支持多个索引、多种类型同时查询以及索引的模糊匹配

索引：_index
映射类型：_type

##### 单索引查询

* 查询索引以`sz-gdc-`为prefix的任意类型的记录: `GET: /sz-gdc-*/_search`
* 查询类型以`sz-gdc-20180101`为索引，类型为`logs`的记录: `GET: /sz-gdc-20180101/logs/_search`

##### 多索引查询
* 查询索引以`bioservice`和`frontline`为索引的任意映射类型的记录: `GET: /bioservice,frontline/_search`
* 查询映射类型以以`bioservice`和`frontline`为索引，映射类型为`logs`的记录: `GET: /bioservice,frontline/logs/_search`

##### 不限索引的映射类型查询

查询任意索引的为
查询任意索引的映射类型为`logs`的记录: `GET: /_all/logs/_search`

#### 分页

每次搜索默认展示10条记录，记录长度可以根据需要通过`size`参数调整；如不指定`from`参数，则默认返回第一页，可通过`from`参数选择要访问的页面
> pageNo = (from / size) + 1

* 指定获取的分页大小： `GET /_search?size=5`

* 指定获取的分页大小及页面： `GET /_search?size=5&from=5`

NOTE:

1. `GET /_search?size=5` + `GET /_search?size=5&from=5` 的10条结果，无法保证与 `GET /_search?size=10`始终相等（每个分片上各自排序，再由协调点排序取前n）
2. 避免做深度分页（web 搜索引擎对任何查询都不要返回超过 10000 个结果）

> Note that from + size can not be more than the index.max_result_window index setting which defaults to 10,000. See the Scroll or Search After API for more efficient ways to do deep scrolling.

为什么滚动过深会有问题：

假设在一个有 5 个主分片的索引中搜索。 当我们请求结果的第一页（结果从 1 到 10 ），每一个分片产生前 10 的结果，并且返回给 协调节点 ，协调节点对 50 个结果排序得到全部结果的前 10 个。
现在假设我们请求第 1000 页，结果从 10001 到 10010 。所有都以相同的方式工作除了每个分片不得不产生前10010个结果以外。 然后协调节点对全部 50050 个结果排序最后丢弃掉这些结果中的 50040 个结果。 (此处执行的是`query then fetch`操作，汇总、排序、向其它分片取回完整信息)

如果要深度翻页，需要使用 [scrolling api][8]

#### 轻量搜索

轻量搜索即在URL中附带查询条件

查询log_level属性包含`ERROR`, class属性包含`DownloadBlockTask`的记录： `GET /_search?q=+log_level:ERROR +class:DownloadBlockTask`
> 每个参数之间使用空格间隔，多个参数时前面带 `+`, 如不带空格，则查询条件变成 “或”

更复杂的搜索

* name 字段中包含 mary 或者 john
* date 值大于 2014-09-10
* _all 字段包含 aggregations 或者 geo

`GET /_search?q=+name:(mary john) +date:>2014-09-10 +(aggregations geo)`
（+ 前缀表明这个词必须存在）
> 查询字符串搜索允许任何用户在索引的任意字段上执行可能较慢且重量级的查询，这可能会暴露隐私信息，甚至将集群拖垮。

#### 查询时使用的分析器

当我们 索引 一个文档，它的全文域被分析成词条以用来创建倒排索引。 但是，当我们在全文域 搜索 的时候，我们需要将查询字符串通过 相同的分析过程 ，以保证我们搜索的词条格式与索引中的词条格式一致。

全文查询，理解每个域是如何定义的，因此它们可以做 正确的事：

* 当你查询一个 全文 域时， 会对查询字符串应用相同的分析器，以产生正确的搜索词条列表。
* 当你查询一个 精确值 域时，不会分析查询字符串， 而是搜索你指定的精确值。

现在你可以理解在 开始章节 的查询为什么返回那样的结果：

date 域包含一个精确值：单独的词条 `2014-09-15`。
_all 域是一个全文域，所以分词进程将日期转化为三个词条： `2014`， `09`， 和 `15`。

* 当我们在 _all 域查询 `2014`，它匹配所有的12条推文，因为它们都含有 `2014` ：

```shell
GET /_search?q=2014              # 12 results
```

* 当我们在 _all 域查询 `2014-09-15`，它首先分析查询字符串，产生**匹配 `2014`， `09`， 或 `15` 中 `任意` 词条的查询**。这也会匹配所有12条推文，因为它们都含有 `2014` ：

```shell
GET /_search?q=2014-09-15        # 12 results !
```

* 当我们在 date 域查询 `2014-09-15`，它寻找 精确 日期，只找到一个推文：

```shell
GET /_search?q=date:2014-09-15   # 1  result
```

* 当我们在 date 域查询 `2014`，它找不到任何文档，因为没有文档含有这个精确日志：

```shell
GET /_search?q=date:2014         # 0  results !
```

##### 使用分析器分析

* 查看分析器的分析方式
```shell
curl -X GET "192.168.1.103:9200/_analyze" -H 'Content-Type: application/json' -d'
{
  "analyzer": "standard",
  "text": "+log_level:ERROR +thread:download-tid"
}
'
```

* 查看指定映射类型的分析方式

> **此处的field对应的是上面提到的映射类型`_type`**

```shell
curl 192.168.1.103:9200/gb/_analyze -H "Content-Type: application/json" -d '
{
  "field": "tweet",
  "text": "Black-cats"
}
'
```

### 请求体搜索

#### 基本语法
`GET/POST /<_index>/<_mapping_type>/_search`

和URL字符串简单搜索请求的资源相同，将 `-q` `from` `size`等参数移到body中

```shell
curl -X GET "localhost:9200/twitter/_search" -H 'Content-Type: application/json' -d'
{
    "query" : {
        "term" : { "user" : "kimchy" }
    },
    "from": 0,
    "size": 10
    ...
}
'


```

支持的参数列表： [[ref]][7]

* timeout
* from
* size
* search_type
* request_cache
* allow_partial_search_results
* terminate_after
* batched_reduce_size

#### DSL

查询表达式的基本结构：
```json

{ "query":
    {
        QUERY_NAME: {
            ARGUMENT: VALUE,
            ARGUMENT: VALUE,
            ...
        }
    }
}
```
一条复合语句可以将多条语句 — 叶子语句和其它复合语句 — 合并成一个单一的查询语句

##### match_all

```json
{
    "query": {
        "match_all": {}
    }
}
```

等价于空查询

`match_all` 经常与 filter 结合使用，对应的还有 `match_none`

##### match
全文搜索/精确查询

* 在精确值的字段上使用时：（数字、日期、布尔或者一个 not_analyzed字段）
```json
{
    "query": {
        "match": {
            "log_level": "ERROR"
        }
    }
}
```

##### multi_match

在多个字段上执行相同的match查询

```json
{
    "query": {
        "multi_match": {
            "query": "2018-07-13",
            "fields": ["path", "log_date"]
        }
    }
}

```

##### term
精确查询 （数字、日期、布尔或者一个 not_analyzed字段）

使用方法和match相似，当不匹配或字段是analyzed的，则返回空

##### terms
精确查询，和term相似，允许多值匹配

```json
{
    "query": { "terms": { "log_level": [ "WARNING", "ERROR" ] }}
}
```

##### exists/missing

和SQL中的 `NOT IS_NULL`、mongo中的`$exists`很相似, 这些查询经常用于某个字段有值的情况和某个字段缺值的情况。

```json
{
    "query": {
        "exists": {
            "field": "log_level"
        }
    }
}
```

missing在2.2.0之后被弃用，使用组合的方式表达相同的意义

```json
{
    "query": {
        "bool": {
            "must_not": {
                    "exists": {
                    "field": "log_level"
                }
            }
        }
    }
}
```

##### range

范围查询，`gt` `gte` `lt` `lte`和mongo的参数非常相似

```json

{
    "query": {
        "range": {
            "age": {
                "gte":  20,
                "lt":   30
            }
        }
    }
}

```

##### 组合多查询

使用以下关键词，可以根据自己的需求，无限组合出想要的查询条件

* must 必须匹配这些条件才包含到结果中
* must_not 必须不匹配这些条件才包含到结果中
* should 如果满足给出的任意条件，则增加`_score`，否则无影响（用于修正每个文档的相关性得分）
* filter 必须匹配，但它以不评分、过滤模式来进行。（即这些条件不影响评分，只过滤出结果, 单独使用filter时，结果不评分  *CHECK: 会使用内存缓存？*）

这些关键词都需要配合 `bool` 使用。每一个子查询都独自地计算文档的相关性得分, 一旦他们的得分被计算出来， bool 查询就将这些得分进行合并并且返回一个代表整个布尔操作的得分

```json
{
    "bool": {
        "must":     { "match": { "title": "how to make millions" }},
        "must_not": { "match": { "tag":   "spam" }},
        "should": [
            { "match": { "tag": "starred" }}
        ],
        "filter": {
          "range": { "date": { "gte": "2014-01-01" }}

        }
    }
}
```

评分对查询性能的影响：
通过将 range 查询移到 filter 语句中，我们将它转成不评分的查询，将不再影响文档的相关性排名。由于它现在是一个不评分的查询，可以使用各种对 filter 查询有效的优化手段来提升性能。

所有查询都可以借鉴这种方式。将查询移到 bool 查询的 filter 语句中，这样它就自动的转成一个不评分的 filter 了。

bool和must、must_not、should、filter可以无限地嵌套使用

###### 使用 constant_score

使用一个不变的常量评分，用于所有的返回结果中，通常用于 只有 `filter` 时，代替 `bool`

###### 验证查询是否合法

```json
curl -X GET "localhost:9200/gb/tweet/_validate/query?explain" -H 'Content-Type: application/json' -d'
{
   "query": {
      "tweet" : {
         "match" : "really powerful"
      }
   }
}
'

```

### 搜索结果排序

es默认以搜索结果的相关性评分进行排序，如果评分相同，则以随机的顺序返回

相关性评分的依据：
* 检索词频率：检索词在文本中出现的频率，正相关
* 反向文档频率：检索词在索引中出现的频率，负相关（在越多的文档中出现则越说明相关性更小）
* 字段长度准则：文档的长度越长，相关性越低

#### 按照字段值排序

* 只需在查询后面指定字段，并且指定排序方式即可
```json
{
    "query": {},
    "sort": {
        "date": {
            "order": "desc"
        }
      }
}
```

* 或者使用简洁的方式指定字段进行排序 (默认升序)
```json
{
    "query": {},
    "sort": "date"
}
```

当指定其它字段进行排序时，则默认不进行评分

> Fielddata is disabled on text fields by default.


#### 多级排序

```json
{
    "query" : {...},
    "sort": [
        { "date":   { "order": "desc" }},
        { "_score": { "order": "desc" }},
        ...
    ]
}

```

按照 sort列表中的顺序，当`date`的值完全相同时，以第二个值`_score`进行排序，以此类推

#### 多值字段的排序

有时，部分字段有多个值，但这些多值字段中的值是没有固定顺序的，对于数字和日志，可以使用 `min` `max` `avg` `sum`将其减为单值


### 搜索过程及对节点的性能影响

一次查询分为几个步骤：

1. 客户端发送查询请求到一个节点A {"from": 90, "size": 10}
2. 节点A变成协调点，向其它节点（分片）广播查询信息；同时节点A创建一个大小为 `from + size`的空“优先队列”
3. 每个分片在本地查询结果，并添加结果到大小为 `from + size` 的优先队列中，然后将各自查到的文档ID和任何排序需要用到的值返回给协调点
4. 协调点合并这些值到自己的优先队列中来产生一个全局排序后的结果列表，向其它分片取回完整的文档信息添加到优先队列中

所以，当分页请求过深（`from`过大）时，必然对每个分片/协调节点带来更重的负担。

#### 使用scroll进行大批量的文档获取操作

```shell

# scroll=1m 保持游标查询窗口一分钟
curl localhost:9200/old_index/_search?scroll=1m -H 'Content-Type: application/json' -d'
{
    "query": {},
    "sort": "_doc",
    "size": 1000
}
'

# resp
{
    "scroll_id" : "cXVlcnlUaGVuRmV0Y2g...",
    "hits": {...}
}

# scroll, 参数中需要再次将查询过期时间设为1m
curl localhost:9200/_search/scroll=1m -H 'Content-Type: application/json' -d'
{
    "scroll_id" : "cXVlcnlUaGVuRmV0Y2g...",
    "scroll": "1m"
}
'
```
每次滚动的请求会返回一个新的`_scroll_id`，每次滚动需要使用最新的`_scroll_id`才能完成滚动的效果


[1]: https://www.elastic.co/guide/en/elasticsearch/reference/current/removal-of-types.html#_parent_child_without_mapping_types
[2]: https://www.elastic.co/guide/en/elasticsearch/reference/current/mapping.html
[3]: https://www.elastic.co/guide/en/elasticsearch/reference/current/mapping.html#mapping-limit-settings
[4]: https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-reindex.html#docs-reindex
[5]: https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-create-index.html
[6]: https://www.elastic.co/guide/en/elasticsearch/reference/current/alias.html
[7]: https://www.elastic.co/guide/en/elasticsearch/reference/current/search-request-body.html#_parameters_4
[8]: https://www.elastic.co/guide/en/elasticsearch/reference/current/search-request-scroll.html
