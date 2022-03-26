Chapter.1 底层接口

1.  对于Collection的解析：本篇
2.  对于Iterable的解析：[[Java集合-Iterable]]
3.  对于Set和List的解析：[[Java集合-Set与List]]
4.  对于Queue和Deque的解析：[[Java集合-Queue与Deque]]

Chapter.2 抽象类

1.  对于AbstractCollection的解析：[[Java集合-AbstractCollection]]

Chapter.3 实现类

1. 

___

集合类为java.util包下的重要内容，它由Java提供，类似于数组，它同样是一个容器，但集合的长度是可变的，而数组的长度是固定的。Collection是集合类层次结构中的最底层，所有的java.util包下的集合类都是实现的此接口，并根据不同的需求衍生出不同功能的集合类，同时，Collection继承于Iterable接口，使得其能够更加简便快捷地进行迭代操作。
![[Pasted image 20211124122751.png]]

## 官方简介

> The root interface in the collection hierarchy.  A collection  represents a group of objects, known as its elements. Some collections allow duplicate elements and others do not.  Some are ordered and others unordered.  The JDK does not provide any direct implementations of this interface: it provides implementations of more specific subinterfaces like Set and List.  This interface  is typically used to pass collections around and manipulate them where maximum generality is desired.

> 译文：集合层次结构中的根接口。 集合表示一组对象，称为其元素。一些集合允许重复的元素，而另一些则不允许。一些集合是有序的，而其他则是无序的。JDK不提供此接口的任何直接实现：它提供更特定的子接口（如 Set 和 List）的实现。该接口通常用于传递集合，并为各种集合类提供最大化的统一操作方法（如add() remove()等）

___

## 数组与集合

相同之处：

1.  它们都是容器，都能够容纳一组元素。

不同之处：

1.  数组的大小是固定的，集合的大小是可变的。
2.  数组可以存放基本数据类型，但集合只能存放对象。
3.  数组存放的类型只能是一种，但集合可以有不同种类的元素。

___

## 继承关系

```java
public interface Collection<E> extends Iterable<E>
```

仅继承于Iterable接口（迭代操作接口，下一篇讲解）

___

## 接口中的方法

```java
int size();
```

size方法：获取集合中元素数量，值得注意的是，当集合中元素数量超过int类型的最大值（2147483647）时，只会返回int类型的最大值。

```java
boolean isEmpty();
```

isEmpty方法：非常简单，返回集合是否为空。

```java
boolean contains(Object o);
```

contains方法：返回集合中是否包含至少一个指定的元素，且能够判断是否包含null元素，一般情况下调用对象的equals方法比较是否为同一个元素，若传入参数为null，则寻找集合中是否包含null元素。

```java
Iterator<E> iterator();
```

iterator方法：获取此集合类的迭代器，迭代顺序根据不同实现可能是有序也可能是无序的（下一章讲解）

toArray方法：返回包含集合中全部元素的数组，元素的顺序与迭代器顺序一致，需要注意的是，它包含两个不同返回类型toArray方法，第一个toArray固定返回一个类型为Object\[\]的数组，且无法进行强制类型转换，只能是Object\[\]类型；第二个toArray返回指定泛型T的数组类型，通过传入指定数组实例进行操作，若传入数组大小大于等于当前集合元素数量，则将所有元素添加到数组中，未填充满的部分用null代替，否则返回一个新的指定类型的数组。

代码演示：

```java
List<String> list = Arrays.asList("lbw", "nb");
String[] strings = new String[5];
String[] newArray = list.toArray(strings);
System.out.println(Arrays.toString(list.toArray(strings)));
System.out.println(Arrays.toString(strings));
System.out.println(strings == newArray);

List<String> list = Arrays.asList("lbw", "nb");
String[] strings = new String[0];
String[] newArray = list.toArray(strings);
System.out.println(Arrays.toString(list.toArray(strings)));
System.out.println(Arrays.toString(strings));
System.out.println(strings == newArray);
```

___

```java
boolean add(E e);
```

add方法：这个是作为集合的最基本操作方法，向集合中添加一个元素，根据子类不同实现，某些集合类可能会不允许添加重复元素，当添加了重复元素时，操作会被取消并返回false，若操作成功，返回true，当然这只是一种情况，有的集合也会限制添加null元素或是只能添加某些特定元素，如果某个集合由于包含该元素以外的其他原因而拒绝添加该元素，则它应该直接抛出异常，而不是返回false，因此无论子类如何实现或是操作结果如何，在没有抛出任何异常且得到返回值之后，集合中一定包含该元素。

```java
boolean remove(Object o);
```

remove方法：这个方法同样是集合中最基本的操作方法，从集合中移除一个指定元素。传入一个对象，并判断集合中是否包含此对象（判断方法与contains方法实现一致）若包含则移除，并返回true，否则返回false。

```java
boolean containsAll(Collection<?> c);
```

containsAll方法：判断传入的集合是否为当前集合的子集（是否包含传入集合中的全部元素）

```java
boolean addAll(Collection<? extends E> c);
```

addAll方法：将此集合变为传入集合的并集（添加传入集合的所有元素到此集合中）并返回结果是否发生了改变。

```java
boolean removeAll(Collection<?> c);
```

removeAll方法：将此集合变为传入集合的补集（删除传入集合中的所有元素）并返回结果是否发生了改变。

```java
boolean retainAll(Collection<?> c);
```

 retainAll方法：将此集合变为传入集合的交集（删除所有传入集合中不包含的元素）并返回结果是否发生了改变。

```java
void clear();
```

 clear方法：清空此集合。

```java
boolean equals(Object o);
```

 equals方法：判断两个集合的内容是否相同。

```java
int hashCode();
```

 hashCode方法：返回集合的哈希码。

___

## JDK1.8新增方法

```java
default boolean removeIf(Predicate<? super E> filter) {
	Objects.requireNonNull(filter);
	boolean removed = false;
	final Iterator<E> each = iterator();
	while (each.hasNext()) {
		if (filter.test(each.next())) {
			each.remove();
			removed = true;
		}
	}
	return removed;
}
```

removeIf方法：进行批量删除满足条件的元素。它在Collection接口中自带默认实现，通过调用迭代器进行迭代并解析断言表达式（Predicate，JDK1.8新增，用于函数式编程），对满足断言条件的元素进行删除。

```java
List<String> list = new ArrayList<>(Arrays.asList("lbw", "nb", "lbw", "nb"));
System.out.println("原集合："+list);
list.removeIf(e -> e.equals("lbw"));
System.out.println("处理后的集合："+list);
```

如上述代码中，即对所有等于 "lbw" 的字符进行删除操作。

___

```java
default Spliterator<E> spliterator() {
	return Spliterators.spliterator(this, 0);
}
```

spliterator方法：这个是JDK1.8新增的可分割迭代器，用于并行遍历而传统的迭代器是串行遍历（具体内容会在后面章节进行讲解）

```java
default Stream<E> stream() {
    return StreamSupport.stream(spliterator(), false);
}
 
default Stream<E> parallelStream() {
    return StreamSupport.stream(spliterator(), true);
}
```

stream方法：JDK1.8新增的流处理工具，能够更加方便的处理集合的元素（本篇不做讲解）以上两个方法分别是串行和并行流。

___

## 万恶之源Collection

看看Collection的庞大家族，它当之无愧的万恶之源：

![[Pasted image 20211120185602.png]]

___

## 疑惑点

既然`Collection`是一个泛型接口，那么为什么`remove、contains`等这些方法传入的参数是`Object`，难道不应该像`add`那样传入泛型E类型的参数吗？
由于`Object`类中的`equals`方法需要传入的参数为`Object`类型，而`contains`这类操作又需要通过`equals`方法进行比较，所以，传入的参数只能为`Object`，这也保证了一定的灵活性。