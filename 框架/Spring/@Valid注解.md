用于验证注解是否符合要求，直接加在变量 user 之前，在变量中添加验证信息的要求，当不符合要求时就会在方法中返回 message 的错误提示信息。

  

public class UserController {public User create (@Valid @RequestBody User user) {        System.out.println(user.getId());        System.out.println(user.getUsername());        System.out.println(user.getPassword());```

然后在 User 类中添加验证信息的要求：

```java
@NotBlank(message = "密码不能为空")
```

@NotBlank 注解所指的 password 字段，表示验证密码不能为空，如果为空的话，上面 Controller 中的 create 方法会将message 中的"密码不能为空"返回。

当然也可以添加其他验证信息的要求：

| 限制 | 说明 |
| --- | --- |
| @Null | 限制只能为null |
| @NotNull | 限制必须不为null |
| @AssertFalse | 限制必须为false |
| @AssertTrue | 限制必须为true |
| @DecimalMax(value) | 限制必须为一个不大于指定值的数字 |
| @DecimalMin(value) | 限制必须为一个不小于指定值的数字 |
| @Digits(integer,fraction) | 限制必须为一个小数，且整数部分的位数不能超过integer，小数部分的位数不能超过fraction |
| @Future | 限制必须是一个将来的日期 |
| @Max(value) | 限制必须为一个不大于指定值的数字 |
| @Min(value) | 限制必须为一个不小于指定值的数字 |
| @Past | 限制必须是一个过去的日期 |
| @Pattern(value) | 限制必须符合指定的正则表达式 |
| @Size(max,min) | 限制字符长度必须在min到max之间 |
| @Past | 验证注解的元素值（日期类型）比当前时间早 |
| @NotEmpty | 验证注解的元素值不为null且不为空（字符串长度不为0、集合大小不为0） |
| @NotBlank | 验证注解的元素值不为空（不为null、去除首位空格后长度为0），不同于@NotEmpty，@NotBlank只应用于字符串且在比较时会去除字符串的空格 |
| @Email | 验证注解的元素值是Email，也可以通过正则表达式和flag指定自定义的email格式 |

除此之外还可以自定义验证信息的要求，例如下面的 @MyConstraint：

```java
@MyConstraint(message = "这是一个测试")
```

注解的具体内容：

```java
@Constraint(validatedBy = {MyConstraintValidator.class})
@Target({ELementtype.METHOD, ElementType.FIELD})
@Retention(RetentionPolicy.RUNTIME)
public @interface MyConstraint {
	Class<?>[] groups() default {};    
	Class<? extends Payload>[] payload() default {};
}
```

下面是校验器：

```java
public class MyConstraintValidator implements ConstraintValidator<MyConstraint, Object> {
	private UserService userService;
	public void initialie(@MyConstraint constarintAnnotation) {        
	System.out.println("my validator init");
	public boolean isValid(Object value, ConstraintValidatorContext context) {
	  	userService.getUserByUsername("seina");        
	    System.out.println("valid");
	}
}
```