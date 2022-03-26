在接口的上一级，就是集合类的抽象实现了，几乎所有的集合实现类都是从这些抽象类继承自AbstractCollection类。
[[Java集合-Collection]]
但是，在Collection接口中明确指出，此接口没有直接实现，所以AbstractCollection仅实现了部分关键接口方法，仍有一部分接口方法未被实现。
同时AbstractCollection是AbstractList、AbstractSet、AbstractQueue等抽象类的父类，所实现的一些接口方法，对于之后的延伸也起到了关键作用。

___

## 继承关系

```java
public abstract class AbstractCollection<E> implements Collection<E>
```

AbstractCollection只实现了Collection接口中的一部分方法。

```java
protected AbstractCollection() {
}
```

其构造方法也限定权限为protceted。

___

## 基本实现

```java
public boolean isEmpty() {
    return size() == 0;
}
```

 **isEmpty方法：** 直接调用size方法（此方法仍未被实现）判断是为0，若为0必定为空。

```java
public boolean contains(Object o) {
    Iterator<E> it = iterator(); 
    //判断是否为null，并对null和非null元素分别实现
    if (o==null) {
        while (it.hasNext())
            if (it.next()==null)
                return true;
    } else {
        while (it.hasNext())
            if (o.equals(it.next()))
                return true;
    }
    return false;
} 
```

**contains方法：** 从代码中可以看到，contains方法对于传入的参数，有两种不同的处理方式，第一种情况是为null的情况，这种情况直接调用迭代器并进行遍历，若在遍历过程中找到为null的元素，则包含；同理，对于非null的元素，系统会在遍历过程中调用其equals方法，一般情况下equals为Object类中的默认实现（直接比较地址）但是某些类（例如String类）equals方法被重写，也就是说如果想要在字符串集合中找一个字符串，直接创建一个新的内容相同的字符串即可判断到包含关系。最后，若是在迭代过程中没有发现包含，则返回false。

```java
public boolean add(E e) {
    throw new UnsupportedOperationException();
}
```

**add方法：** 此方法虽然被实现，但是它会直接抛出UnsupportedOperationException异常。为什么会直接抛出异常？其中一个原因是因为Collection不知道如何去实现add方法，因为add方法需要根据不同的集合实现方式（比如ArrayList数组实现，LinkedList为链表实现）决定写法；另一个原因是，某些集合类不支持add操作（比如Arrays.ArrayList类，不支持动态增删操作）所以默认抛出异常表示不支持此操作。

```java
public boolean remove(Object o) {
    Iterator<E> it = iterator();
    if (o==null) {
        while (it.hasNext()) {
            if (it.next()==null) {
                it.remove();
                return true;
            }
        }
    } else {
        while (it.hasNext()) {
            if (o.equals(it.next())) {
                it.remove();
                return true;
            }
        }
    }
    return false;
}
```

**remove方法：** 与前面的contains方法基本相同，只是通过调用迭代器的remove方法在迭代过程中移除掉判断到需要移除的元素。

```java
public boolean containsAll(Collection<?> c) {
    for (Object e : c)
        if (!contains(e))
            return false;
    return true;
}
```

**containsAll方法：** 遍历传入集合中的所有元素，直接调用已实现的contains方法判断是否包含，若在遍历途中发现任意一个不包含的元素，返回false。

```java
public boolean addAll(Collection<? extends E> c) {
    boolean modified = false;
    for (E e : c)
        if (add(e))
        modified = true;
    return modified;
}
```

**addAll方法：** 遍历传入集合中的所有元素，调用add方法（需要子类支持）依次添加每一个元素，若中途发现有任意元素添加成功，那么已修改modified标记变量会被设置为true，表示当前集合已被被修改。若完成整个遍历都没有元素被成功添加，那么返回modified标记变量的默认值false。

```java
public boolean retainAll(Collection<?> c) {
    Objects.requireNonNull(c);
    boolean modified = false;
    Iterator<E> it = iterator();
    while (it.hasNext()) {
        if (!c.contains(it.next())) {
            it.remove();
            modified = true;
        }
    }
    return modified;
}
```

**removeAll方法：** 在此方法执行前，进行了一个判断是否为空的操作，它要求传入的集合不能为null，否则Objects.requireNonNull方法会抛出空指针异常，此方法中会调用传入集合的contains方法，因此JDK不希望在方法运行时才暴露这个问题，因此在开始之前就进行了判断。遍历当前集合的所有元素，只有在判断到传入集合中包含当前遍历元素时，才会进行删除操作，同样的，此方法也有modified标记变量用于反馈操作结束后当前集合内容是否发生了变化。

```java
public boolean retainAll(Collection<?> c) {
    Objects.requireNonNull(c);
    boolean modified = false;
    Iterator<E> it = iterator();
    while (it.hasNext()) {
        if (!c.contains(it.next())) {
            it.remove();
            modified = true;
        }
    }
    return modified;
}
```

**retainAll方法：** 实现方法与removeAll方法基本相同，但是执行remove操作的条件与removeAll方法相反，当前数组中所有的传入数组中不包含的元素，都会被移除（类似于取交集）

```
public void clear() {
    Iterator<E> it = iterator();
    while (it.hasNext()) {
        it.next();
        it.remove();
    }
}
```

**clear方法：** 调用迭代器依次删除每一个元素。

___

## toArray实现讲解

为什么这个方法需要单独讲解呢？因为此方法的实现考虑到多种因素（尤其是并发）所以在实现上，要去理解它稍微有一定难度，我们单独将其列出并进行讲解。

```java
public Object[] toArray() {
    // Estimate size of array; be prepared to see more or fewer elements
    Object[] r = new Object[size()];
    Iterator<E> it = iterator();
    for (int i = 0; i < r.length; i++) {
        if (! it.hasNext()) // fewer elements than expected
            return Arrays.copyOf(r, i);
        r[i] = it.next();
    }
    return it.hasNext() ? finishToArray(r, it) : r;
}
```

首先来看没有参数的toArray方法，在方法的最开始，官方就打上了一句注释，大致意思为：**预估数组的大小，同时做好出现更多或更少元素的准备**。这句话如何理解？你可能会觉得莫名其妙，难道我集合中的元素还会在中通莫名其妙变多或是变少了不成？事实还真是如此，在并发访问此数组的情况下，就有那么一种情况会导致这个问题，其中一个线程调用了toArray方法，而另一个线程这时正在对我们的集合进行增加或是删除操作，toArray方法刚走到方法的第一行生成了一个数组，而这时集合内容发生了改变，而下一行就会生成一个包含更多或是更少元素的迭代器，于是就出现问题了。现在，数组的容量无法容纳迭代器里面所有需要迭代的内容，因此，如果不进行特殊处理，保证程序依然能正确得到结果，那么就会造成内部错误，这是一个很严重的问题。

```java
for (int i = 0; i < r.length; i++) {
    if (! it.hasNext()) // fewer elements than expected
        return Arrays.copyOf(r, i);
    r[i] = it.next();
}
```

为了解决这种情况下发生的问题，我们不能再直接对迭代器进行全部迭代了，而是需要在外层套一个刚好能够循环上面所生成的数组大小次数的for循环，优先保证不会出现数组越界之类的异常。现在就要分情况进行考虑：

1.  **生成的迭代器内容小于数组的容量：** 这种情况下很明确，for循环应该被提前终止，因为元素内容不足以填满整个数组，因此数组的大小也应该被减小。
2.  **生成的迭代器内容大于数组的容量：** 这种情况是最危险的，for循环即使已经完成了，还是残留了许多未被迭代的元素，因此不仅需要扩容数组，还需要完成剩下的迭代。
3.  **生成的迭代器内容没有因为并发的影响而与数组的容量发生差异：** 这个时候就应该按照正常流程直接返回我们的数组即可。

所以，在for循环中，我们可以看到，每次循环都会调用迭代器的hasNext方法，判断是否有新的元素，如果有，就继续，并将对应数组位置的元素设置为对应的值；如果没有元素可迭代了，说明迭代器中的内容小于数组的容量，我们需要对数组进行缩小，这里调用了Arrays类的copyOf方法为数组重新设定容量（有关Arrays类的实现，我们会在后面讲到，某些地方用到了native本地方法来提升运行效率，其中就包括copyOf方法）并保留原数组内容再返回一个容量为 **i** 的数组，而此时的 **i** 正好就是需要缩小的数组的大小，这也是为什么外层使用for循环的一个原因。得到新的数组后，就可以提前结束for循环并直接作为此方法的返回值返回。

```java
return it.hasNext() ? finishToArray(r, it) : r;
```

好了，现在for循环结束，第1种情况（生成的迭代器内容小于数组的容量）已经进行了处理，那么还剩下第2、第3种情况，其实现在无非就是看迭代器中的内容到底还有没有剩余的，如果没有剩余，那就代表在for循环完成时，迭代器也刚好完成了所有内容的迭代，则发生的是第3种情况，即没有受到外界任何影响或是影响没有造成不一致的情况，这种情况就可以直接返回我们for循环中处理完成的数组了；如果有剩余，表示还需要扩容数组并添加剩余内容，因此需要进行一次额外的处理。所以，在最后一行，依然是调用了一次hasNext查看是否有剩余，没有则直接返回数组 **r** ，如果有那就进行额外处理（调用finishToArray方法）再返回处理后的数组。

___

## 处理余下的迭代器内容

toArray需要考虑的远不止上面所说的并发情况，同时，还存在一个数组最大容量限制问题，因此，要理解finishToArray方法实现的逻辑也并不是一件简单的事情，这一部分我会讲解两个方法，一个是处理迭代器余下内容的finishToArray方法，还有一个就是辅助方法hugeCapacity（它们都是AbstractCollection私有方法），首先来看是怎么处理余下的迭代内容的：

```java
private static <T> T[] finishToArray(T[] r, Iterator<?> it) {
    int i = r.length;
    while (it.hasNext()) {
        int cap = r.length;
        if (i == cap) {
            int newCap = cap + (cap >> 1) + 1;
            // overflow-conscious code
            if (newCap - MAX_ARRAY_SIZE > 0)
                newCap = hugeCapacity(cap + 1);
            r = Arrays.copyOf(r, newCap);
        }
        r[i++] = (T)it.next();
    }
    // trim if overallocated
    return (i == r.length) ? r : Arrays.copyOf(r, i);
}
```

你会发现和你想象的可能不太一样，按照正常情况，难道不应该直接将余下内容直接放入扩容后的数组吗，为什么会有这么多不知道在干嘛的代码呢？对，按照正常情况，确实是直接添加即可，但是如果JVM能够申请得到最大的数组容量是有限制的呢？这下就不能轻易的直接添加剩余元素了吧？所以说，为了避免这种情况，还需要进行额外的处理才可以。既然存在限制，我们先来看限制是什么：

```java
private static final int MAX_ARRAY_SIZE = Integer.MAX_VALUE - 8;
```

在AbstractCollection中存在这样一个私有静态常量 **MAX_ARRAY_SIZE** 用于表示数组长度最大限制，你一定会疑惑，为什么不是Integer.MAX_VALUE而是Integer.MAX_VALUE - 8呢，难道这个8有什么特殊含义吗？其实在某些JVM中，会保留某些头部属性，比如这里的8，正好用来存储数组的长度信息，为了能够留出这个空间，所以限制为Integer.MAX_VALUE - 8，这样就不会导致某些运行时出现的问题。

```java
int i = r.length;
while (it.hasNext()) {
    int cap = r.length;
    if (i == cap) {
        int newCap = cap + (cap >> 1) + 1;
        // overflow-conscious code
        if (newCap - MAX_ARRAY_SIZE > 0)
            newCap = hugeCapacity(cap + 1);
        r = Arrays.copyOf(r, newCap);
    }
    r[i++] = (T)it.next();
}
```

了解了数组长度限制，现在我们就可以对源码进行解读了，首先创建了一个变量 i 用于标志下标位置，既然要接着往数组后加元素，那么起始位置就是 r.length 了，于是定义 i = r.length，然后使用while循环开始迭代剩余内容，现在就是很难看懂的地方了，我们来尝试去理解这样写的意义：这里新增了一个局部变量 cap 代表容量，也是等于 r.length，这里的if判断的是 i == cap，因为i每次循环都会自增（并在数组对应位置设置为迭代的内容），所以我们猜测判断的就是是否需要进行扩容操作，每次扩容后，开始下一轮循环，cap重新获取 r.length，这就不会等于i，直到 i 通过迭代循环自增到与cap重新相等，又会进行一次扩容，一直循环直到迭代器中没有内容。

```java
int newCap = cap + (cap >> 1) + 1;   //位移操作，等价于cap + (cap/2) + 1
// overflow-conscious code 译文：能够检测到溢出的代码
if (newCap - MAX_ARRAY_SIZE > 0)
    newCap = hugeCapacity(cap + 1);
r = Arrays.copyOf(r, newCap);
```

好了，现在我们已经大致推断出这个循环想要干嘛了，现在再来看看 if 条件中，它是怎么进行扩容操作的。首先定义一个新的局部变量 newCap 作为新的容量，而新容量的算法为newCap = cap + cap/2 + 1，为什么要在最后加1呢？因为有可能cap为1，1/2计算结果为0，所以这样是保证一定能完成扩容操作。然后就开始判断newCap - MAX_ARRAY_SIZE 是否大于0，如果大于0表示扩容后的数组容量超过了最大数组容量限制，或是发生了 **“溢出”** 什么是溢出？

```java
System.out.println(Integer.MAX_VALUE + 1);
```

如上代码运行的结果并不是int类型的最大值+1，而是一个负数，为什么是负数？这就涉及到二进制运算了：

```java
计算机底层计算采用补码形式，于是int类型的最值分别为：
最小值：10000000 00000000 00000000 00000000
最大值：01111111 11111111 11111111 11111111
 
如果最大值+1，根据进位规则，会变成：
10000000 00000000 00000000 00000000
 
于是，我们的最大值瞬间变为最小值，也就是一个负数。
并且由于第一位（符号位）是1（代表负数），所以继续进行小额的加法运算，也只会是负数。
所以，突破int限制往上加，只会陷入到一个循环中。
```

现在问题就来了，如果说 newCap扩大到超过int类型的最大值，那么它的值会变成一个负数！所以判断newCap - MAX_ARRAY_SIZE就起到了关键作用，如果超过了int最大值，那就减回去一个 MAX_ARRAY_SIZE 则依然可以得到是个正数，这是一个很巧妙的地方。

```java
private static int hugeCapacity(int minCapacity) {
    if (minCapacity < 0) // overflow
        throw new OutOfMemoryError
            ("Required array size too large");
    return (minCapacity > MAX_ARRAY_SIZE) ?
        Integer.MAX_VALUE :
        MAX_ARRAY_SIZE;
}
```

那么既然超越了限制或是发生了溢出，就会调用hugeCapacity方法，那么hugeCapacity方法做了什么事情来解决这些问题呢？首先传入的参数为cap + 1，如果说cap大于等于int的最大值，那么传入的参数必定是一个小于0的数（必定发生了溢出），也就满足了if的条件，直接抛出OutOfMemoryError错误。如果说传入的参数还没有超越限制，就还存在挽救的余地，这时我们需要给newCap一个正确的容量值，现在判断传入的值是否大于数组容量限制（注意不是int最大值现在）如果大于容量限制返回int最大值，否则返回最大限制值。你一定会好奇，为什么这里会返回int的最大值，难道不应该直接返回数组最大容量限制值吗？也许这是为了兼容某些JVM特殊情况吧，毕竟不是所有的JVM都有这个限制。

```java
r = Arrays.copyOf(r, newCap);
```

回到finishToArray方法的while循环中，现在newCap已经有一个能够保证不出现错误的扩容后的容量了，那么就可以调用Arrays.copyOf方法为我们的 r 重新设置容量，设置容量后就可以将新的元素添加到数组中了。由于多种限制，这一路真是非常艰辛啊。

```java
return (i == r.length) ? r : Arrays.copyOf(r, i);
```

最后，再进行一次判断，因为扩容的时候是按照公式扩容的，不一定能够刚好为迭代器剩余内容开辟刚刚好的空间，一般都是有剩余空间，所以，如果还有剩余空间，就再重新分配一次容量，没有则直接返回 r。至此，整个toArray的烧脑全过程就结束了。

___

## 带类型的toArray方法

其实带类型的toArray方法与之前的无参toArray方法逻辑基本一致，只是采用了java.lang.reflect反射包下的Array.newInstance创建了一个对应类型的数组，同时判断传入的数组是否容量满足，如果满足直接使用传入的数组作为载体，当然，具体实现中还包含native本地方法 System.arraycopy 本篇暂时不做讲解。

```java
public <T> T[] toArray(T[] a) {
    // Estimate size of array; be prepared to see more or fewer elements
    int size = size();
    T[] r = a.length >= size ? a :
              (T[])java.lang.reflect.Array
              .newInstance(a.getClass().getComponentType(), size);
    Iterator<E> it = iterator();
 
    for (int i = 0; i < r.length; i++) {
        if (! it.hasNext()) { // fewer elements than expected
            if (a == r) {
                r[i] = null; // null-terminate
            } else if (a.length < i) {
                return Arrays.copyOf(r, i);
            } else {
                System.arraycopy(r, 0, a, 0, i);
                if (a.length > i) {
                     a[i] = null;
                }
            }
            return a;
        }
        r[i] = (T)it.next();
    }
    // more elements than expected
    return it.hasNext() ? finishToArray(r, it) : r;
}
```

非常感谢您可以阅读到最后，如果对本篇文章有什么宝贵意见也可以提出。