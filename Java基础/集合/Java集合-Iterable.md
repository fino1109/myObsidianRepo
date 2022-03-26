 Iterable作为Collection接口的父接口，必定有着不一般的能力，官方对它的介绍为：

> Implementing this interface allows an object to be the target of the "for-each loop" statement.

实现此接口意味着该对象就满足了进行`foreach`的标准，使得它可以成为`foreach`的目标，所有实现此接口的类都可以进行增强`for循环`（增强for循环依赖于Iterable接口） 需要注意的是，`Iterable`需要和`Iterator`进行区分，前者是迭代接口作为Collection的父接口，而`后者才是我们所说的迭代器`（它们都是接口）

___

## 用处

 既然存在普通for循环、while循环等语法，为什么还需要迭代器进行遍历呢？迭代器是一种全新的设计模式，它使得我们在拿到一个集合对象时，无需关心如何去遍历此集合，而是给予我们统一进行迭代的标准，我们只需要根据它的使用标准进行迭代即可，而底层的迭代算法实现，则由对应的实现类完成，从而实现统一，也推进了foreach操作的诞生。我们可以来进行一个简单的对比：

```
List<String> list = new ArrayList<>();for(int i = 0;i < list.size();i++){    System.out.println(list.get(i));List<String> list = new LinkedList<>();for(int i = 0;i < list.size();i++){    System.out.println(list.get(i));
```

由于ArrayList对于随机访问的速度更快，而LinkedList对于顺序访问的速度更快（它们的底层实现会在后面的章节讲解），因此在上述的传统for循环遍历操作中，ArrayList的效率更胜一筹，因此我们要使得LinkedList遍历效率提升，就需要采用顺序访问的方式进行遍历，如果没有迭代器帮助我们统一标准，那么我们在应对多种集合类型的时候，就需要对应编写不同的遍历算法，很显然这样会降低我们的开发效率，而迭代器的出现就帮助我们解决了这个问题。标准的迭代器使用：

```
LinkedList<String> list = new LinkedList<>();Iterator<String> iterable = list.iterator();while (iterable.hasNext()){    System.out.println(iterable.next());
```

___

## Iterable、Iterator与Spliterator

Iterable是迭代接口，此接口中包含生成迭代器的方法、Lambda版forEach（JDK1.8新增）、并行迭代器生成方法（JDK1.8新增）并且由Collection直接继承，

而Iterator正式我们所说的迭代器，它可以对我们的集合类进行迭代操作，从而实现遍历，而如何去实现它的迭代功能，则由每一个集合类内部维护。

Spliterator与Iterator功能大致相同，但它是并行遍历，而Iterator是串行遍历。

那么为什么有了Iterator还需要Spliterator呢？在科技飞速发展的今天，过去的单核处理器早已被时间淘汰，多核心处理器的时代到来了，我们可以利用多线程技术同时处理多个任务，而不像曾经那样将多个任务排起来一个一个处理，同样的，对于单个任务，我们可以将其拆分为几个小任务，并将这几个小任务同时处理，大大提升工作效率（将在后面章节对其进行讲解）

___

## Iterable源码解析

```java
Iterator<T> iterator();
```

**iterator方法：**  直接获得一个新的迭代器对象，注意是新的，每次调用都会生成一个新的迭代器，它的迭代位置会从头开始。如何去生成这样的一个迭代器对象，由各个集合实现类根据自己对应的算法进行维护。

```java
default void forEach(Consumer<? super T> action) {
    Objects.requireNonNull(action);
    for (T t : this) {
        action.accept(t);
    }
}cts.requireNonNull(action);
```

**forEach方法：** 此方法为JDK1.8新增方法（用于Lambda表达式），并且带有默认实现，而默认实现就是我们的foreach语句，并对该接口本身进行迭代并执行Consumer中的函数式。

```
default Spliterator<T> spliterator() {
	return Spliterators.spliteratorUnknownSize(iterator(), 0);
}
```

**spliterator方法：** 此方法为JDK1.8新增方法，同Collection中不同的是，其调用的是Spliterators.spliteratorUnknownSize方法，本篇不对其进行讲解（在后面的章节中进行详细讲解）

___

## Iterator源码解析

```java
boolean hasNext();
```

 **hasNext方法：** 作为迭代器的核心方法，它可以检查是否已经完成全部元素的迭代，通常配合while循环使用。

```java
E next();
```

 **next方法：** 此方法可以获取当前迭代位置的元素，当已经没有元素时，会抛出NoSuchElementException异常。

```java
throw new UnsupportedOperationException("remove");
```

 **remove方法：** 删除当前迭代元素，注意，它在接口中有默认实现，在调用此接口的时候，直接抛出UnsupportedOperationException异常（这个操作一般需要子类的支持）

```java
default void forEachRemaining(Consumer<? super E> action) {  Objects.requireNonNull(action);
while (hasNext())
    action.accept(next());
}
```

**forEachRemaining方法：** 类似于 Iterable的forEach的方法，但是不同之处是，此方法只会遍历余下未被迭代的元素（从当前迭代位置开始）我们可以来看一个例子：

```java
LinkedList<String> list = new LinkedList<>();
list.add("lbw");
list.add("nb");
Iterator<String> iterable = list.iterator();
iterable.next();
iterable.forEachRemaining(System.out::println);
 
/**
* 输出结果为：
* nb
*/
```

在调用 forEachRemaining之前发生的任意迭代操作都会影响forEachRemaining的遍历内容，例如上面代码中，我们在调用forEachRemaining之前调用过一次next方法，导致**迭代位置**变为第二个元素，所以forEachRemaining将从第二个元素开始进行遍历操作。

___

## 疑惑点

**迭代器和foreach到底是什么关系，为什么实现了Iterable接口的类就可以使用foreach呢？**我们可以通过反编译来找到答案：

```java
//源代码：
List<String> list = new ArrayList<String>();
for (String s : list) {
    //TODO
}
 
 
//由编译器编译后反编译的代码：
List<String> list = new ArrayList<String>();
Iterator<String> iter = list.iterator();
while(iter.hasNext()) {
    iter.next();
}
```

结果已经很明显了，在编译器编译后，我们的foreach代码发生了变化，它实质上依然是利用迭代器进行迭代操作，所以，凡是实现了Iterable接口的类，都可以通过iterator方法获取对应的迭代器对象，所以Java就将其简化为所有实现Iterable接口的类都能使用foreach操作。

___

**为什么Collection不直接继承Iterator接口，而是使用Iterable这样类似于套娃的操作呢？**
迭代器会有一个指针，告诉迭代器当前迭代任务的迭代位置，如果由集合类直接维护迭代位置，那么在使用时会产生诸多问题，
例如：在对象传递时，它的迭代位置是未知的，就算新增一个reset之类的重置迭代位置的方法，也只能用于单线程情况下，若对于此集合的多个遍历同时发生，则会出现不可预估的结果。
而使用Iterable接口可以调用接口中的方法，单独获得一个新的迭代器，这样就可以避免某些情况下出现的问题。