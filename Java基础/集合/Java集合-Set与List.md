Set和List继承自Collection接口，它们同样都是接口类，但是它们的规则却不同，其中最大的区别在于Set集合不允许重复元素存在，而List集合允许重复元素存在。

___

## Set集合

Set集合是Collection的一个分支，你会发现它的接口内容与Collection几乎相同，但是他们的规则不同，**Set集合不允许重复元素存在**，同样地，因为是直接继承Collection，它不保证元素的次序，但是某些情况下人们需要保留不允许重复元素的特性，但是想要保证元素的次序，于是衍生出SortedSet接口（将在后面的章节讲解），Set在JDK中的官方介绍为：

> A collection that contains no duplicate elements.  More formally, sets  contain no pair of elements e1 and e2 such that e1.equals(e2), and at most one null element.  As implied by its name, this interface models the mathematical set abstraction.

> 译文：不包含重复元素的集合。更确切的说，对于元素e1和e2，若满足e1.equals(e2)，则e1和e2只能同时存在其一。同样的，对于null元素，Set中也只允许存在一个。 顾名思义，此接口对数学集合抽象进行建模。 

由于源代码与Collection几乎相同，本篇不做讲解，唯一需要注意的是add方法，我们来解读它的文档描述：

 虽然Collection中也有add方法，但是Set中这个方法的使用被重新定义了，这也体现了继承与多态的思想。

___

##  List集合

List集合是我们在写代码中使用最频繁的集合类， 它**保证了元素的次序，同时允许重复元素存在**。同时List还可以生成ListIterator迭代器，它是Iterator迭代器的升级版，使得其可以进行双向遍历（将会在后面的章节讲解）List在JDK中的官方介绍为：

> An ordered collection (also known as a sequence).  The user of this  interface has precise control over where in the list each element is  inserted.  The user can access elements by their integer index (position in the list), and search for elements in the list.

> 有序集合（也称为序列）。实现该接口的类，可以精确控制List中每个元素的插入位置。还可以通过其整数索引（List中的下标位置，类似于数组）访问元素，并在List中搜索元素。 

从介绍中我们可以明确，List集合相对于Collection的扩展就非常之大了，因为它保证了元素的次序，使得它可以在任意位置插入元素，同样的也支持根据类似于数组那样的下标位置，对元素进删除，相对于Set集合，List集合的功能非常强大。 

___

## List接口新增内容

对于Collection中提供的接口方法，List做出了重新定义，所有的添加操作，都会默认在List最后一个元素的后面添加（后面的章节会讲解具体的实现），因为List现在支持在任意索引位置插入元素：

```java
boolean addAll(int index, Collection<? extends E> c);
```

 **支持插入位置的 addAll方法：** 新增了一个额外的addAll方法，对比Collection中的addAll方法，它多了一个参数，也就是我们的索引位置（index）使得它可以在List中间插入元素，索引位置超出List的长度时会抛出IndexOutOfBoundsException异常。

```java
default void replaceAll(UnaryOperator<E> operator) {
    Objects.requireNonNull(operator);
    final ListIterator<E> li = this.listIterator();
    while (li.hasNext()) {
        li.set(operator.apply(li.next()));
    }
}
```

**replaceAll方法：** 此方法为JDK1.8中新增方法，它需要用户提供一个UnaryOperator操作器，使得能够快速对List中所有元素进行批量操作（UnaryOperator为Function接口的扩展，不做讲解）依然是使用的迭代器进行批量操作，具体使用方法如下：

```java
LinkedList<String> list = new LinkedList<>();
list.add("lbw");
list.add("nb");
list.replaceAll(e -> e.replace("b", "k"));
System.out.println(list);
/**
* 输出结果：
* [lkw, nk]
*/
```

上述代码操作为对每一个元素的内容进行替换，将List内所有字符串元素中的 "b" 替换为 "k"。

___

```java
default void sort(Comparator<? super E> c) {
    Object[] a = this.toArray();
    Arrays.sort(a, (Comparator) c);
    ListIterator<E> i = this.listIterator();
    for (Object e : a) {
        i.next();
        i.set((E) e);
    }
}
```

**sort方法：** 此方法也是JDK1.8中新增方法，传入一个比较器（自定义比较规则）根据规则对List内元素进行重新排序，**默认实现调用Arrays的sort排序方法**（具体的排序算法会在后面的篇章讲解），先对List生成的数组进行排序，然后再将这些内容重新添加到List中（这里使用的是ListIterator迭代器，将会在后面的章节讲解，它支持迭代过程中的set操作）

```java
E get(int index);
```

**get方法：** 根据索引位置直接获得对应位置上的元素，索引位置超出List的长度时会抛出IndexOutOfBoundsException异常。

```java
E set(int index, E element);
```

**set方法：** 可以直接将对应索引位置的元素设置为新元素，索引位置超出List的长度时会抛出IndexOutOfBoundsException异常。

```java
void add(int index, E element);
```

**支持插入位置的 add方法：** 此方法可以直接将元素插入到任何你想要插入的位置，而不是Collection中定义的插入到一个不确定的位置，索引位置超出List的可插入范围时会抛出IndexOutOfBoundsException异常。（注意它的返回值是void，因为它不香Set那样存在一定约束条件，除非触发异常，正常情况下元素不会被拒绝插入，因此没有任何反馈）

```java
E remove(int index);
```

**remove方法：** 直接移除索引位置元素，并返回被移除的元素，索引位置超出List的长度时会抛出IndexOutOfBoundsException异常。

```java
int lastIndexOf(Object o);
```

**indexOf方法 ：** 顾名思义，寻找相同元素的下标位置，第一个方法返回的是第一个相同元素的位置；第二个方法是返回最后一个相同元素的位置，没有找到则返回 -1。

```java
ListIterator<E> listIterator();ListIterator<E> listIterator(int index);
```

**listIterator方法：** 获取一个全新的ListIterator迭代器，它基于Iterator进行了强化，支持双向遍历以及set和add操作（后面的篇章中讲解）你也可以调用第二个方法，它可以为你提供一个从指定下标位置开始迭代的ListIterator迭代器。

```java
List<E> subList(int fromIndex, int toIndex);
```

**subList方法：** 指定起始位置，对当前List进行分割，并返回分割后新生成的一个List对象。