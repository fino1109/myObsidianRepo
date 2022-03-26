## 引言

  

Gson 在 Json 解析中使用广泛, 常用的数据类型都可以解析, 特殊的可以自定义 Adapter 解析. 在解析大量具有某些相同结构的数据上, 我们总想复用已有的类型, 为了复用通常可以使用继承和泛型. 比如服务端返回的 json 都有类似结构:

  
```json
{
    "code":200,
    "message":"success",
    "data":"{...}"
}
```
  

其中`data`对应的结构不定, 一种考虑是使用泛型:

  
```java
public class Response<T>{
    public T data;
}
```
  

于是在做 json 解析是很可能会这样使用:

  
```java
String json = "{\"data\":\"data from server\"}";
Type type = new TypeToken<Response<String>>(){}.getType();
Response<String> result = new Gson().fromJson(json, type);
```
  

这个`TypeToken`是如何和类型`Response<String>`产生关系, 又是怎样存储泛型信息的? 首先需要明确 Type 是什么.

  

## Type 是什么

  

这里的 Type 指 java.lang.reflect.Type, 是 Java 中所有类型的公共高级接口, 代表了 Java 中的所有类型. Type 体系中类型的包括：数组类型 (GenericArrayType)、参数化类型 (ParameterizedType)、类型变量 (TypeVariable)、通配符类型 (WildcardType)、原始类型 (Class)、基本类型 (Class), 以上这些类型都实现 Type 接口.

  
>参数化类型, 就是我们平常所用到的泛型 List、Map；
>数组类型, 并不是我们工作中所使用的数组 String[] 、byte[]，而是带有泛型的数组，即 T[] ；
>通配符类型, 指的是 <?>, <? extends T > 等等
>原始类型, 不仅仅包含我们平常所指的类，还包括枚举、数组、注解等；
>基本类型, 也就是我们所说的 java 的基本类型，即 int,float,double 等


本文的重点在于参数化类型 (ParameterizedType).

```java
public interface ParameterizedType extends Type {

Type[] getActualTypeArguments();


Type getRawType();


Type getOwnerType();
}

 ``` 

## 获取类型的困惑

  

对于普通的类想要获取类型简单调用`.class`或者`getClass()`方法即可,

  
```java
Class<String> stringClass = String.class;
Class<?> stringClass2 = "hello".getClass();
```
  
但对于泛型你不能这样做,

  
```java
Response<String>.class 
Response.class
```
  

那么在做 json 解析时我们如果确实是需要让 Gson 解析成`Response<String>`, 可以像上文的方式处理.

  

## 自定义 TypeToken

  

先看一段代码:

  ```java

import java.lang.reflect.ParameterizedType;
import java.lang.reflect.Type;

public abstract class MyTypeToken<T> {
    private final Type type;
    public MyTypeToken() {
        Type genericSuperclass = getClass().getGenericSuperclass();
        if(genericSuperclass instanceof Class){
            throw new RuntimeException("Missing type parameter.");
        }
        ParameterizedType parameterizedType = (ParameterizedType) genericSuperclass;
        Type[] typeArguments = parameterizedType.getActualTypeArguments();
        type = typeArguments[0];
    }

    public Type getType() {
        return type;
    }
}

  ```

1.  MyTypeToken 声明为抽象类, 使用时需要对其进行实例化, 实例化过程可以分解如下:  
    相当于  
    这样分解的目的在于明确`sToken`的类型是`MyTypeToken$0(匿名的)`, 父类型是`MyTypeToken<String>`而不是`MyTypeToken<T>`.

MyTypeToken<String> sToken = new MyTypeToken<String>(){};

class MyTypeToken$0 extends MyTypeToken<String>{}
MyTypeToken<String> sToken = new MyTypeToken$0();

2.  `getClass().getSuperclass()`获取的是当前对象所属的类型的父类型. 注意到抽象类实例化时需要给具体的泛型类, 如果没有提供则使用 Object(但此时使用的已不是泛型类了, 而是原始类型, 也就是擦除泛型后的类型) 代替泛型参数. 因此如果像上面那样实例化, 那么`getClass().getGenericSuperclass()`得到的将是类型参数实例化后的父类型`MyTypeToken<String>`, 泛型信息保留下来了. 如果不用泛型得到的是`MyTypeToken`, 是原始类型.

3.  得到泛型参数实例化后的类型, `getActualTypeArguments()`返回的是确切的类型参数数组, 此处 MyTypeToken 只有一个类型参数, 返回的是数组`[String.class]`.

  

至此, 通过`new MyTypeToken<Response<String>>() {}.getType()`得到的正是表示`Response<String>`的类型, 将该类型应用在 Gson 在解析`Response<String>`上将获得和`TypeToken`一致的效果 (当然就这么点代码功能肯定是比不上了).

  

## 解决问题

  

探究 TypeToken 的目的其实为了解决以下问题而总结的.

  
```java
 public class TokenUtil{
    public static <E> Type getType(){
        return new MyTypeToken<E>() {}.getType();
    }
}

Type type = TokenUtil.<Response<String>>getType();

Response<String> o = new Gson().fromJson(json, type);

  ```

## 总结

  

Gson 解析时`TypeToken<T>`的泛型参数只能使用时传入**确切的类型**才能获取正确的 Type, 这也是`TypeToken`设计成抽象类的巧妙之处和原因（改为只有 protected 构造方法的普通类原理一样）. 一旦将`TypeToken`改成普通类, 根据上面的分析, 一切类型信息都被擦除, Gson 解析将得不到预期的类型.