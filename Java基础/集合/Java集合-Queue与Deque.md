Queue同样继承自Collection接口，但是它不像List和Set那样，它有着一种全新的约束：
先入先出（FIFO, First Input First Output）Queue队列通常情况下都为先入先出模式，同时也有多种衍生类型：优先级队列、先入后出（FILO）队列或堆栈。那么什么是先入先出呢？就好比超市收银台前排起来的长长的队伍一样，先到达收银台的顾客，可以优先结账并离开，队列也是如此，它不像List那样可以进行随机访问，能够随便移除任意位置的元素，队列只能移除队头的元素；同样的，它也不能像List那样可以插入元素到任意位置，在队列中要遵守秩序，新来的元素只能排到队尾，等待前面的元素全部被移除才能被访问。

___

## 经典队列Queue接口

Queue接口就是队列操作的具体体现 ，它的实现类有很多种，比如优先级队列会在插入元素时自动判断优先级并将元素排到对应位置，但是出队规则不变，官方描述为：

> Queues typically, but do not necessarily, order elements in a FIFO (first-in-first-out) manner.  Among the exceptions are priority queues, which order elements according to a supplied comparator, or the elements' natural ordering, and LIFO queues (or stacks) which order the elements LIFO (last-in-first-out). Whatever the ordering used, the head of the queue is that element which would be removed by a call to remove() or poll().  In a FIFO queue, all new elements are inserted at the tail of the queue. Other kinds of queues may use different placement rules.

> 队列通常但不一定以FIFO（先进先出）的方式对元素进行排序，但是也存在特殊情况包括优先级队列（根据提供的比较器对元素进行排序或元素的自然排序）和LIFO队列（或堆栈），对LIFO进行排序（后进先出）。无论使用哪种顺序，位于队列队头的元素都可以通过调用remove方法或poll方法将其删除。在FIFO队列中，所有新元素都被插入队列的尾部，其他类型的队列可能使用不同的插入规则。 

我们来看看它基于Collection接口发生了哪些改变：

最主要的就是add方法，它的定义变得适用于队列操作，相对于Collection中的add方法定义，它多出了一个容量限制的概念，同时，add操作一般情况下只会在队尾插入元素（这与List的add(E e)方法基本相同）

___

## Queue详解

我们来看看Queue接口相较于Collection接口新增了哪些内容：

```java
boolean offer(E e);
```

**offer方法：** 与add方法相同，同样是按照队列规则插入元素，但是add方法在超出容量时会抛出异常，而offer方法只会返回false作为结果，因此官方不推荐使用add方法。

```java
E remove();
E poll();
```
-   **remove方法：** 和List的remove方法不同，它没有任何参数，调用此方法只会位于移除队头的元素，并返回此元素，在队列为空时抛出NoSuchElementException异常。
-   **poll方法：** 和remove方法功能相同，但是在没有队列为空时不会抛出异常，而是返回null作为结果，因此官方不推荐使用remove方法。
```java
E element();
E peek();
```
-   **element方法：** 只检索队头元素，但是不会移除，并返回此元素，在队列为空时抛出NoSuchElementException异常。
-   **peek方法：** 功能与element方法相同，但是在没有队列为空时不会抛出异常，而是返回null作为结果。

队列（LinkedList实现了Queue接口）使用示例：

```java
Queue<String> queue = new LinkedList<>();
queue.offer("伞");
queue.offer("兵");
queue.offer("一");
queue.offer("号");
for(String q : queue){
    System.out.printf("%s", q);  //为了显示方便我们用printf方法
}
 
System.out.println("\n-> 出队: "+queue.poll());
for(String q : queue){
    System.out.printf("%s", q);
}
 
/**
* 运行结果：
* 伞兵一号
* -> 出队: 伞
* 兵一号
*/
```

___

## 双端队列Deque接口 

双端队列Deque为Queue的子接口，它使得队列的两端都可以进行入队和出队操作，如果你学习过数据结构，你一定会很好奇，为什么Java中很难找到一个带栈名称（Stack）的实现类呢？因为Deque胜任了这份工作，Deque这样的扩展使得其能够完成多种设计模式，比如栈，满足先入后出规则（FILO，First Input Last Output）那么什么又是先入后出呢？一群人排队走进了一个狭窄到只能通过一人的死胡同，当所有人进入后，第一个进入的人发现这是一个死胡同，因此，他们只能从进来的地方再出去，而这时，他们出去的顺序就刚好和进入的顺序完全相反，也就是先进入的人，反而后出去；后进入的人，反而先出去。像这样的先入后出结构，双端队列就可以完美实现。

```java
Deque<String> deque = new LinkedList<>();
deque.push("伞");
deque.push("兵");
deque.push("一");
deque.push("号");
for(String q : deque){
    System.out.printf("%s", q);  //为了显示方便我们用printf方法
}
 
System.out.println("\n-> 出栈："+deque.pop());
 
for(String q : deque){
    System.out.printf("%s", q);
}
 
 
/**
 * 运行结果：
 *
 * 号一兵伞
 * -> 出栈：号
 * 一兵伞
 */
```

___

## Deque详解

由于队列现在支持在任意一端进行操作，所有，之前Queue的方法全部获得了升级：
```java
//抛出异常型（不推荐）
void addFirst(E e);
void addLast(E e);
 
//返回null型（推荐）
boolean offerFirst(E e);
boolean offerLast(E e);
```

**add和offer方法：** 现在区分为在队头或是队尾添加元素，当然，addLast与原有的add方法相同，offerLast与原有的offer方法相同。
```java
//抛出异常型（不推荐）
E getFirst();
E getLast();
 
//返回null型（推荐）
E peekFirst();
E peekLast();
```

**remove和poll方法：** 现在也分为在队头或是队尾删除元素，同理，removeFirst与原有的remove方法相同，pollFirst与原有的poll方法相同。
```java
//抛出异常型（不推荐）
E getFirst();
E getLast();
 
//返回null型（推荐）
E peekFirst();
E peekLast();
```

**get和peek方法：** 同样分为在队头和队尾获取元素，需要注意getFirst方法对应element方法（名字上稍有不同）peekFirst与原有peek方法相同；

___

Deque带来的不仅仅是原有方法的升级，它还带了一系列全新的操作：

```java
boolean removeFirstOccurrence(Object o);
boolean removeLastOccurrence(Object o);
```

-   **removeFirstOccurrence方法：** 它可以找到队列中排最前的指定元素，并将其删除，同时返回true，若未找到则返回false。
-   **removeLastOccurrence方法：** 找到排最后的指定元素，与removeFirstOccurrence方法相同。
```java
//栈操作
void push(E e);
E pop();
```
-   **push方法：** 入栈操作，优先入栈的元素会被压入栈低。
-   **pop方法：** 出栈操作，移除并返回最后入栈的元素，没有元素时抛出NoSuchElementException异常。

```java
Iterator<E> descendingIterator();
```

**descendingIterator方法：** 它与常规的iterator方法一样，会生成一个新的迭代器，但是它是反向的，你会得到一个从队尾向队头进行迭代的迭代器。

```java
Deque<String> deque = new LinkedList<>();
deque.add("伞");
deque.add("兵");
deque.add("一");
deque.add("号");
Iterator<String> descendingIterator = deque.descendingIterator();
while (descendingIterator.hasNext()){
    System.out.println(descendingIterator.next());
}
 
/**
* 运行结果：
* 
* 号
* 一
* 兵
* 伞
*/
```

上述代码结果中便是使用了反向迭代器的效果。