# 概要
下面的两个对象和八个方法构成了SQLite接口的基本要素：
- 核心对象
  - sqlite3 → 数据库连接对象。通过sqlite3_open()创建，通过sqlite3_close()销毁。
  - sqlite3_stmt → 预编译语句对象。通过sqlite3_prepare()创建，通过sqlite3_finalize()销毁。
- 核心方法
  - sqlite3_open() → 打开与新的或现有的SQLite数据库的连接。sqlite3的构造函数。
  - sqlite3_prepare() → 编译SQL文本为会执行查询或更新数据库工作的字节码。sqlite3_stmt的构造函数。
  - sqlite3_bind() → 将应用程序数据存储到原始SQL的参数中。
  - sqlite3_step() → 将sqlite3_stmt推进到下一个结果行或完成。
  - sqlite3_column() → sqlite3_stmt当前结果行中的列值。
  - sqlite3_finalize() → sqlite3_stmt的析构函数。
  - sqlite3_close() → sqlite3的析构函数。
  - sqlite3_exec() → 一个包装函数，对一个或多个SQL语句的字符串执行sqlite3_prepare()、sqlite3_step()、sqlite3_column()和sqlite3_finalize()。

# 运行原理
SQLite数据库引擎的主要任务是评估SQL语句。为了完成这个任务，开发者需要两个对象：

- 数据库连接对象：sqlite3
- 预准备语句对象：sqlite3_stmt

严格来说，预准备语句对象不是必需的，因为可以使用便利包装接口，如sqlite3_exec或sqlite3_get_table，这些便利包装封装并隐藏了预准备语句对象。尽管如此，为了充分利用SQLite，还是需要了解预准备语句。

数据库连接和预准备语句对象由以下几个C/C++接口例程控制：

- sqlite3_open()
- sqlite3_prepare()
- sqlite3_step()
- sqlite3_column()
- sqlite3_finalize()
- sqlite3_close()

以下是核心接口的总结：

## sqlite3_open()
此例程打开一个到SQLite数据库文件的连接，并返回一个数据库连接对象。

## sqlite3_prepare()
此例程将SQL文本转换为预准备语句对象，并返回该对象的指针。该API实际上并不评估SQL语句。它仅仅是为评估准备SQL语句。

可以将每个SQL语句视为一个小型电脑程序。sqlite3_prepare()的目的是将该程序编译成对象代码。然后sqlite3_step()接口运行对象代码以获得结果。

新应用程序应该始终调用sqlite3_prepare_v2()而不是sqlite3_prepare()。旧的sqlite3_prepare()是为了向后兼容而保留的。但sqlite3_prepare_v2()提供了一个更好的接口。

## sqlite3_step()
此例程用于评估之前通过sqlite3_prepare()接口创建的预准备语句。该语句被评估直到第一行结果可用为止。要进入到结果的第二行，再次调用sqlite3_step()。继续调用sqlite3_step()，直到语句完成。不返回结果的语句（例如：INSERT、UPDATE或DELETE语句）在一次对sqlite3_step()的调用中运行完成。

## sqlite3_column()
此例程从通过sqlite3_step()评估的预准备语句的当前结果行中返回一个列。每次sqlite3_step()停在一个新的结果集行时，都可以多次调用此例程，以找到该行中所有列的值。

如上所述，实际上并没有名为"sqlite3_column()"的函数在SQLite API中。相反，我们在这里所称的“sqlite3_column()”是一系列函数的占位符，这些函数以各种数据类型返回结果集中的值。这个家族中还有一些例程返回结果的大小（如果它是一个字符串或BLOB）和结果集中的列数。

- sqlite3_column_blob()
- sqlite3_column_bytes()
- sqlite3_column_bytes16()
- sqlite3_column_count()
- sqlite3_column_double()
- sqlite3_column_int()
- sqlite3_column_int64()
- sqlite3_column_text()
- sqlite3_column_text16()
- sqlite3_column_type()
- sqlite3_column_value()

## sqlite3_finalize()
此例程销毁之前通过sqlite3_prepare()调用创建的预准备语句。为了避免内存泄漏，必须使用对此例程的调用来销毁每个预准备语句。

## sqlite3_close()
此例程关闭之前通过对sqlite3_open()的调用打开的数据库连接。关闭连接之前，应该完成与连接相关的所有准备语句。

# 编程步骤
要运行一个 SQL 语句，应用程序遵循以下步骤：

* 使用 sqlite3_prepare() 创建一个准备好的语句。
* 通过多次调用 sqlite3_step() 来评估准备好的语句。
* 对于查询，通过在两次调用 sqlite3_step() 之间调用 sqlite3_column() 来提取结果。
* 使用 sqlite3_finalize() 销毁准备好的语句。
* 以上就是一个人在使用 SQLite 时需要了解的全部内容。其他都是优化和细节。

# 包装函数
sqlite3_exec() 接口是一个便利的包装器，通过单个函数调用执行了上述的全部四个步骤。传递给 sqlite3_exec() 的回调函数用于处理结果集的每一行。sqlite3_get_table() 是另一个便利的包装器，执行了上述的全部四个步骤。sqlite3_get_table() 接口与 sqlite3_exec() 的区别在于它将查询结果存储在堆内存中，而不是调用回调函数。

重要的是要意识到，无论是 sqlite3_exec() 还是 sqlite3_get_table() 都不会执行任何不能通过核心例程实现的操作。事实上，这些包装器纯粹是基于核心例程实现的。

# 如何重复使用SQL语句
在先前的讨论中，假定每个SQL语句都被准备一次，评估一次，然后被销毁。然而，SQLite 允许同一个准备好的语句被多次评估。这是通过以下例程实现的：

- sqlite3_reset()
- sqlite3_bind()

在一个或多个对 sqlite3_step() 的调用对已经准备好的语句进行评估后，可以通过调用 sqlite3_reset() 来重置该语句，以便再次通过调用 sqlite3_step() 进行评估。可以将 sqlite3_reset() 理解为将准备好的语句程序倒带回到开始。使用 sqlite3_reset() 来重置现有的准备好的语句，而不是创建一个新的准备好的语句，可以避免不必要的调用 sqlite3_prepare()。对于许多 SQL 语句，运行 sqlite3_prepare() 所需的时间等于或超过运行 sqlite3_step() 所需的时间。因此，避免调用 sqlite3_prepare() 可以显著提高性能。

通常情况下，不会有必要评估完全相同的 SQL 语句多次。更常见的情况是要评估类似的语句。例如，您可能希望多次使用不同的值评估一个 INSERT 语句。或者您可能希望使用 WHERE 子句中的不同键多次评估相同的查询。为了适应这一点，SQLite 允许 SQL 语句包含参数，在评估之前将这些参数“绑定”到值。稍后这些值可以更改，然后可以使用新值再次评估相同的准备好的语句。

在查询或数据修改语句（DQL或 DML）中，SQLite 允许参数出现在字符串文字、二进制数据文字、数字常量或 NULL 的位置。 （参数不能用作列名或表名，也不能用作约束或默认值的值。 （DDL）） 参数可以采用以下形式：

- ?
- ?NNN
- :AAA
- $AAA
- @AAA

在上述示例中，NNN 是整数值，AAA 是标识符。参数最初具有 NULL 值。在首次调用 sqlite3_step() 前或立即在 sqlite3_reset() 后，应用程序可以调用 sqlite3_bind() 接口将值附加到参数。每次调用 sqlite3_bind() 都会覆盖同一参数上先前的绑定。

应用程序允许预先准备多个SQL语句并根据需要对其进行评估。准备好的语句的数量没有任意限制。一些应用程序在启动时多次调用 sqlite3_prepare()，以创建它们将来需要的所有准备好的语句。其他应用程序会保留最近使用的准备好的语句的缓存，然后在可用时重用这些从缓存中提取出的准备好的语句。另一种方法是仅在循环内部重用准备好的语句。

# 配置sqlite3
SQLite的默认配置对绝大多数应用程序来说都非常合适。但有时候，开发者可能想要调整设置以尝试挤压出更多的性能，或利用某些不常见的特性。

sqlite3_config() 接口用于进行 SQLite 的全局性、进程范围内的配置更改。必须在创建任何数据库连接之前调用 sqlite3_config() 接口。sqlite3_config() 接口允许程序员做一些事情，比如：

- 调整 SQLite 如何进行内存分配，包括为安全关键的实时嵌入式系统设置替代内存分配器，以及应用程序定义的内存分配器。
- 设置一个进程范围的错误日志。
- 指定一个应用程序定义的页面缓存。
- 调整互斥锁的使用，使其适合各种线程模型，或者替换为应用程序定义的互斥锁系统。

在进程范围的配置完成且数据库连接已经创建之后，可以使用对 sqlite3_limit() 和 sqlite3_db_config() 的调用来配置单个数据库连接。


# 核心方法深入研究
## sqlite3_prepare
编译sql语句

```c
int sqlite3_prepare(
  sqlite3 *db,            /* Database handle */
  const char *zSql,       /* SQL statement, UTF-8 encoded */
  int nByte,              /* Maximum length of zSql in bytes. */
  sqlite3_stmt **ppStmt,  /* OUT: Statement handle */
  const char **pzTail     /* OUT: Pointer to unused portion of zSql */
);
int sqlite3_prepare_v2(
  sqlite3 *db,            /* Database handle */
  const char *zSql,       /* SQL statement, UTF-8 encoded */
  int nByte,              /* Maximum length of zSql in bytes. */
  sqlite3_stmt **ppStmt,  /* OUT: Statement handle */
  const char **pzTail     /* OUT: Pointer to unused portion of zSql */
);
int sqlite3_prepare_v3(
  sqlite3 *db,            /* Database handle */
  const char *zSql,       /* SQL statement, UTF-8 encoded */
  int nByte,              /* Maximum length of zSql in bytes. */
  unsigned int prepFlags, /* Zero or more SQLITE_PREPARE_ flags */
  sqlite3_stmt **ppStmt,  /* OUT: Statement handle */
  const char **pzTail     /* OUT: Pointer to unused portion of zSql */
);
int sqlite3_prepare16(
  sqlite3 *db,            /* Database handle */
  const void *zSql,       /* SQL statement, UTF-16 encoded */
  int nByte,              /* Maximum length of zSql in bytes. */
  sqlite3_stmt **ppStmt,  /* OUT: Statement handle */
  const void **pzTail     /* OUT: Pointer to unused portion of zSql */
);
int sqlite3_prepare16_v2(
  sqlite3 *db,            /* Database handle */
  const void *zSql,       /* SQL statement, UTF-16 encoded */
  int nByte,              /* Maximum length of zSql in bytes. */
  sqlite3_stmt **ppStmt,  /* OUT: Statement handle */
  const void **pzTail     /* OUT: Pointer to unused portion of zSql */
);
int sqlite3_prepare16_v3(
  sqlite3 *db,            /* Database handle */
  const void *zSql,       /* SQL statement, UTF-16 encoded */
  int nByte,              /* Maximum length of zSql in bytes. */
  unsigned int prepFlags, /* Zero or more SQLITE_PREPARE_ flags */
  sqlite3_stmt **ppStmt,  /* OUT: Statement handle */
  const void **pzTail     /* OUT: Pointer to unused portion of zSql */
);
```

要执行一个SQL语句，必须首先使用这些例程将其编译成一个字节码程序。换句话说，这些例程是用来构建预编译语句对象的构造函数。

首选使用的例程是sqlite3_prepare_v2()。sqlite3_prepare()接口是遗留接口，应该避免使用。sqlite3_prepare_v3()有一个额外的“prepFlags”选项，用于特殊目的。

推荐使用UTF-8接口，因为SQLite目前使用UTF-8进行所有解析。提供UTF-16接口是为了方便。UTF-16接口的工作方式是将输入文本转换为UTF-8，然后调用相应的UTF-8接口。

第一个参数“db”是一个先前通过成功调用sqlite3_open()、sqlite3_open_v2()或sqlite3_open16()获取的数据库连接。数据库连接不能已经被关闭。

第二个参数“zSql”是要编译的语句，编码为UTF-8或UTF-16。sqlite3_prepare()、sqlite3_prepare_v2()和sqlite3_prepare_v3()接口使用UTF-8，sqlite3_prepare16()、sqlite3_prepare16_v2()和sqlite3_prepare16_v3()使用UTF-16。

如果nByte参数为负，则zSql将被读取直到第一个零终结符。如果nByte为正，则它是从zSql中读取的字节数。如果nByte为零，则不会生成预编译语句。如果调用者知道提供的字符串是以空终结符结尾的，那么传递一个nByte参数，该参数是输入字符串中的字节数，包括空终结符，会带来一点性能优势。

如果pzTail不为NULL，则*pzTail指向zSql中第一个SQL语句结束后的第一个字节。这些例程只编译zSql中的第一个语句，因此*pzTail将指向未编译的部分。

*ppStmt指向一个编译好的预编译语句，可以使用sqlite3_step()来执行。如果出现错误，*ppStmt设置为NULL。如果输入文本不包含SQL（如果输入为空字符串或注释），则*ppStmt设置为NULL。调用程序负责在使用完毕后使用sqlite3_finalize()删除编译后的SQL语句。ppStmt不能为空。

成功时，sqlite3_prepare()系列例程返回SQLITE_OK；否则返回一个错误代码。

推荐对所有新程序使用sqlite3_prepare_v2()，sqlite3_prepare_v3()，sqlite3_prepare16_v2()和sqlite3_prepare16_v3()接口。旧的接口（sqlite3_prepare()和sqlite3_prepare16()）保留用于向后兼容，但建议不使用。在“vX”接口中，返回的准备好的语句（sqlite3_stmt对象）包含原始SQL文本的副本。这使得sqlite3_step()接口在三个方面表现不同：

如果数据库模式发生更改，sqlite3_step()将自动重新编译SQL语句并尝试再次运行，而不是像以前一样始终返回SQLITE_SCHEMA，直到sqlite3_step()放弃并返回错误之前会进行最多SQLITE_MAX_SCHEMA_RETRY次重试。

发生错误时，sqlite3_step()将返回详细的错误码或扩展错误码。旧的行为是sqlite3_step()只会返回一个通用的SQLITE_ERROR结果代码，应用程序必须再次调用sqlite3_reset()才能找到问题的根本原因。使用“v2”准备接口，错误的根本原因会立即返回。

如果WHERE子句中主机参数绑定的特定值可能影响语句的查询计划选择，那么在绑定参数发生任何更改后的第一次sqlite3_step()调用后，语句将被自动重新编译，就像发生了模式更改一样。如果WHERE子句参数的特定值是LIKE或GLOB运算符的左操作数，或者如果参数与索引列进行比较并且启用了SQLITE_ENABLE_STAT4编译选项，则参数可能影响查询计划的选择。

sqlite3_prepare_v3()与sqlite3_prepare_v2()的区别仅在于有一个额外的prepFlags参数，它是一个位数组，由零个或多个SQLITE_PREPARE_*标志组成。sqlite3_prepare_v2()接口与sqlite3_prepare_v3()在具有零prepFlags参数时完全相同。

## sqlite3_step
执行SQL语句
```c
int sqlite3_step(sqlite3_stmt*);
```
在使用任何sqlite3_prepare_v2()、sqlite3_prepare_v3()、sqlite3_prepare16_v2()、sqlite3_prepare16_v3()或旧版接口sqlite3_prepare()或sqlite3_prepare16()准备好声明后，必须调用这个函数一次或多次来评估声明。

sqlite3_step()接口的行为细节取决于声明是使用较新的“vX”接口（sqlite3_prepare_v3()、sqlite3_prepare_v2()、sqlite3_prepare16_v3()、sqlite3_prepare16_v2()）还是较旧的遗留接口（sqlite3_prepare()和sqlite3_prepare16()）准备的。建议新应用程序使用“vX”接口，但遗留接口将继续得到支持。

在遗留接口中，返回值将是 SQLITE_BUSY、 SQLITE_DONE、 SQLITE_ROW、 SQLITE_ERROR 或 SQLITE_MISUSE。使用“v2”接口，可能会返回其他任何结果代码或扩展结果代码。

SQLITE_BUSY 表示数据库引擎无法获取执行其工作所需的数据库锁。如果声明是 COMMIT 或在显式事务之外发生，则可以重试该声明。如果声明不是 COMMIT 并且发生在显式事务中，则应该在继续之前回滚事务。

SQLITE_DONE 表示声明已成功执行完毕。在没有先调用 sqlite3_reset() 将虚拟机重置为初始状态之前，不应再次在此虚拟机上调用 sqlite3_step()。

如果被执行的 SQL 声明返回任何数据，则每当有新的数据行准备好由调用者处理时，都会返回 SQLITE_ROW。可以使用列访问函数来访问这些值。再次调用 sqlite3_step() 来检索数据的下一行。

SQLITE_ERROR 表示发生了运行时错误（如约束违反）。不应在 VM 上再次调用 sqlite3_step()。通过调用 sqlite3_errmsg() 可以找到更多信息。在遗留接口中，可以通过在准备好的声明上调用 sqlite3_reset() 来获取更具体的错误代码（例如，SQLITE_INTERRUPT、SQLITE_SCHEMA、SQLITE_CORRUPT 等）。在“v2”接口中，更具体的错误代码直接通过 sqlite3_step() 返回。

SQLITE_MISUSE 表示此例程被不当调用。可能是在已经完成或之前已经返回 SQLITE_ERROR 或 SQLITE_DONE 的准备好的声明上调用它。或者可能是同一数据库连接在同一时刻被两个或更多线程使用。

对于所有版本的 SQLite，包括并且直到 3.6.23.1，sqlite3_step() 返回除 SQLITE_ROW 之外的任何内容后，在任何后续调用 sqlite3_step() 之前，都需要调用 sqlite3_reset()。不使用 sqlite3_reset() 重置准备好的声明将导致 sqlite3_step() 返回 SQLITE_MISUSE。但在 3.6.23.1 版本之后（2010-03-26），在这种情况下，sqlitet3_step() 开始自动调用 sqlite3_reset() 而不是返回 SQLITE_MISUSE。这不被认为是一个兼容性破坏，因为任何接收到 SQLITE_MISUSE 错误的应用程序根据定义就是有缺陷的。可以使用 SQLITE_OMIT_AUTORESET 编译时选项来恢复遗留行为。

怪异接口警告：在遗留接口中，sqlite3_step() API 在任何错误（除了 SQLITE_BUSY 和 SQLITE_MISUSE）后总是返回一个通用错误代码，SQLITE_ERROR。你必须调用 sqlite3_reset() 或 sqlite3_finalize() 来找到更具体地描述错误的特定错误代码。我们承认，这是一个奇怪的设计。这个问题在“v2”接口中已经得到修复。如果你使用 sqlite3_prepare_v3()、sqlite3_prepare_v2()、sqlite3_prepare16_v2() 或 sqlite3_prepare16_v3() 而不是遗留的 sqlite3_prepare() 和 sqlite3_prepare16() 接口准备所有的 SQL 声明，那么更具体的错误代码将直接通过 sqlite3_step() 返回。建议使用“vX”接口。

## sqlite3_column
```c
const void *sqlite3_column_blob(sqlite3_stmt*, int iCol);
double sqlite3_column_double(sqlite3_stmt*, int iCol);
int sqlite3_column_int(sqlite3_stmt*, int iCol);
sqlite3_int64 sqlite3_column_int64(sqlite3_stmt*, int iCol);
const unsigned char *sqlite3_column_text(sqlite3_stmt*, int iCol);
const void *sqlite3_column_text16(sqlite3_stmt*, int iCol);
sqlite3_value *sqlite3_column_value(sqlite3_stmt*, int iCol);
int sqlite3_column_bytes(sqlite3_stmt*, int iCol);
int sqlite3_column_bytes16(sqlite3_stmt*, int iCol);
int sqlite3_column_type(sqlite3_stmt*, int iCol);
```

这些例程返回有关查询当前结果行的单个列的信息。在每种情况下，第一个参数都是指向正在评估的预处理语句的指针（由sqlite3_prepare_v2()或其变体返回的sqlite3_stmt*），第二个参数是要返回信息的列的索引。结果集的最左边列的索引为0。可以使用sqlite3_column_count()确定结果中的列数。

如果SQL语句当前不指向有效的行，或者列索引超出范围，则结果是未定义的。这些例程只能在最近调用的sqlite3_step()返回SQLITE_ROW，且之后没有调用sqlite3_reset()或sqlite3_finalize()时调用。如果在调用sqlite3_reset()或sqlite3_finalize()之后，或者在sqlite3_step()返回除SQLITE_ROW之外的任何值之后调用这些例程中的任何一个，则结果未定义。如果在这些例程中的任何一个待处理时，从不同的线程调用了sqlite3_step()、sqlite3_reset()或sqlite3_finalize()，则结果未定义。

前六个接口（_blob、_double、_int、_int64、_text和_text16）每个都以特定数据格式返回结果列的值。如果结果列最初不在请求的格式中（例如，如果查询返回一个整数，但使用了sqlite3_column_text()接口来提取值），则会执行自动类型转换。

sqlite3_column_type()例程返回结果列的初始数据类型的数据类型代码。返回的值是SQLITE_INTEGER、SQLITE_FLOAT、SQLITE_TEXT、SQLITE_BLOB或SQLITE_NULL之一。sqlite3_column_type()的返回值可以用来决定应该使用前六个接口中的哪一个来提取列值。只有在没有为所讨论的值发生自动类型转换时，sqlite3_column_type()的返回值才有意义。在发生类型转换后，调用sqlite3_column_type()的结果是未定义的，尽管是无害的。SQLite的未来版本可能会在发生类型转换后改变sqlite3_column_type()的行为。

如果结果是BLOB或文本字符串，则可以使用sqlite3_column_bytes()或sqlite3_column_bytes16()接口来确定该BLOB或字符串的大小。

如果结果是BLOB或UTF-8字符串，则sqlite3_column_bytes()例程返回该BLOB或字符串中的字节数。如果结果是UTF-16字符串，则sqlite3_column_bytes()将字符串转换为UTF-8，然后返回字节数。如果结果是数值，则sqlite3_column_bytes()使用sqlite3_snprintf()将该值转换为UTF-8字符串，并返回该字符串中的字节数。如果结果是NULL，则sqlite3_column_bytes()返回零。

如果结果是BLOB或UTF-16字符串，则sqlite3_column_bytes16()例程返回该BLOB或字符串中的字节数。如果结果是UTF-8字符串，则sqlite3_column_bytes16()将字符串转换为UTF-16，然后返回字节数。如果结果是数值，则sqlite3_column_bytes16()使用sqlite3_snprintf()将该值转换为UTF-16字符串，并返回该字符串中的字节数。如果结果是NULL，则sqlite3_column_bytes16()返回零。

sqlite3_column_bytes()和sqlite3_column_bytes16()返回的值不包括字符串末尾的零终止符。为了清晰起见：sqlite3_column_bytes()和sqlite3_column_bytes16()返回的值是字符串中的字节数，而不是字符数。

即使空字符串，由sqlite3_column_text()和sqlite3_column_text16()返回的字符串始终以零终止。对于长度为零的BLOB，sqlite3_column_blob()的返回值为NULL指针。

由sqlite3_column_text16()返回的字符串始终具有平台原生的字节序，无论数据库的文本编码如何设置。

警告：由sqlite3_column_value()返回的对象是一个未受保护的sqlite3_value对象。在多线程环境中，未受保护的sqlite3_value对象只能安全地与sqlite3_bind_value()和sqlite3_result_value()一起使用。如果以任何其他方式使用由sqlite3_column_value()返回的未受保护的sqlite3_value对象，包括调用像sqlite3_value_int()、sqlite3_value_text()或sqlite3_value_bytes()这样的例程，那么行为就不是线程安全的。因此，sqlite3_column_value()接口通常只在实现应用定义的SQL函数或虚拟表时有用，而不在顶层应用代码中使用。

这些例程可能会尝试转换结果的数据类型。例如，如果内部表示为FLOAT并且请求文本结果，sqlite3_snprintf()将内部用于自动执行转换。下面的表格详细说明了应用的转换：

## sqlite3_reset
```c
int sqlite3_reset(sqlite3_stmt *pStmt);
```
`sqlite3_reset()` 函数被调用以将预处理语句对象重置为其初始状态，准备重新执行。使用 `sqlite3_bind_*()` API 绑定值的任何 SQL 语句变量保留其值。要重置绑定，请使用 `sqlite3_clear_bindings()`。

`sqlite3_reset(S)` 接口将预处理语句 S 重置为其程序的开始。

`sqlite3_reset(S)` 的返回代码表明预处理语句 S 的先前评估是否成功完成。如果从未在 S 上调用过 `sqlite3_step(S)`，或者自从上一次调用 `sqlite3_reset(S)` 以来没有调用过 `sqlite3_step(S)`，则 `sqlite3_reset(S)` 将返回 `SQLITE_OK`。

如果对预处理语句 S 的最近一次调用 `sqlite3_step(S)` 指示了一个错误，那么 `sqlite3_reset(S)` 返回一个适当的错误代码。如果在重置预处理语句的过程中没有先前的错误，但是重置过程引起了一个新错误，`sqlite3_reset(S)` 接口也可能返回一个错误代码。例如，如果一个带有 `RETURNING` 子句的 `INSERT` 语句只执行了一次，那么对 `sqlite3_step(S)` 的这一次调用可能会返回 `SQLITE_ROW`，但整体语句可能仍然失败，如果锁定约束阻止数据库更改提交，`sqlite3_reset(S)` 调用可能会返回 `SQLITE_BUSY`。因此，即使对 `sqlite3_step(S)` 的先前调用没有指示问题，应用程序也很重要检查 `sqlite3_reset(S)` 的返回代码。

`sqlite3_reset(S)` 接口不会改变预处理语句 S 上的任何绑定值。

## sqlite3_bind
```c
int sqlite3_bind_blob(sqlite3_stmt*, int, const void*, int n, void(*)(void*));
int sqlite3_bind_blob64(sqlite3_stmt*, int, const void*, sqlite3_uint64,
                        void(*)(void*));
int sqlite3_bind_double(sqlite3_stmt*, int, double);
int sqlite3_bind_int(sqlite3_stmt*, int, int);
int sqlite3_bind_int64(sqlite3_stmt*, int, sqlite3_int64);
int sqlite3_bind_null(sqlite3_stmt*, int);
int sqlite3_bind_text(sqlite3_stmt*,int,const char*,int,void(*)(void*));
int sqlite3_bind_text16(sqlite3_stmt*, int, const void*, int, void(*)(void*));
int sqlite3_bind_text64(sqlite3_stmt*, int, const char*, sqlite3_uint64,
                         void(*)(void*), unsigned char encoding);
int sqlite3_bind_value(sqlite3_stmt*, int, const sqlite3_value*);
int sqlite3_bind_pointer(sqlite3_stmt*, int, void*, const char*,void(*)(void*));
int sqlite3_bind_zeroblob(sqlite3_stmt*, int, int n);
int sqlite3_bind_zeroblob64(sqlite3_stmt*, int, sqlite3_uint64);
```
在输入到`sqlite3_prepare_v2()`及其变体的SQL语句文本中，字面量可以被参数替换，这些参数匹配以下模板之一：

```
?
?NNN
:VVV
@VVV
$VVV
```

在上述模板中，`NNN`代表一个整数字面量，而`VVV`代表一个字母数字标识符。这些参数（也称为“宿主参数名”或“SQL参数”）的值可以使用这里定义的`sqlite3_bind_*()`例程设置。

`sqlite3_bind_*()`例程的第一个参数始终是指向由`sqlite3_prepare_v2()`或其变体返回的sqlite3_stmt对象的指针。

第二个参数是要设置的SQL参数的索引。最左边的SQL参数的索引为1。当同一个命名的SQL参数使用超过一次时，第二次及后续出现具有与第一次出现相同的索引。如果需要，可以使用`sqlite3_bind_parameter_index()` API查找命名参数的索引。"?NNN"参数的索引是NNN的值。NNN的值必须在1到`sqlite3_limit()`参数`SQLITE_LIMIT_VARIABLE_NUMBER`（默认值：32766）之间。

第三个参数是要绑定到参数的值。如果`sqlite3_bind_text()`、`sqlite3_bind_text16()`或`sqlite3_bind_blob()`的第三个参数是NULL指针，那么第四个参数将被忽略，最终结果与`sqlite3_bind_null()`相同。如果`sqlite3_bind_text()`的第三个参数不是NULL，那么它应该是指向格式良好的UTF8文本的指针。如果`sqlite3_bind_text16()`的第三个参数不是NULL，那么它应该是指向格式良好的UTF16文本的指针。如果`sqlite3_bind_text64()`的第三个参数不是NULL，那么它应该是指向格式良好的Unicode字符串的指针，该字符串是UTF8（如果第六个参数是SQLITE_UTF8）或UTF16（否则）。

UTF16输入文本的字节顺序由字节顺序标记（BOM，U+FEFF）确定，该标记在第一个字符中找到并被移除，或者在没有BOM的情况下，字节顺序是宿主机的原生字节顺序，对于`sqlite3_bind_text16()`，或第六个参数中指定的字节顺序对于`sqlite3_bind_text64()`。如果UTF16输入文本包含无效的Unicode字符，则SQLite可能会将这些无效字符更改为Unicode替换字符：U+FFFD。

在具有第四个参数的那些例程中，其值是参数的字节数。为了清楚起见：该值是值的字节数，而不是字符数。如果`sqlite3_bind_text()`或`sqlite3_bind_text16()`的第四个参数为负，则字符串的长度是到第一个零终止符的字节数。如果`sqlite3_bind_blob()`的第四个参数为负，则行为未定义。如果为`sqlite3_bind_text()`或`sqlite3_bind_text16()`或`sqlite3_bind_text64()`提供了非负的第四个参数，那么该参数必须是假设字符串以NUL终止时NUL终止符将出现的字节偏移量。如果任何NUL字符出现在小于第四个参数值的字节偏移量处，则结果字符串值将包含嵌入的NUL。涉及带有嵌入NUL的字符串的表达式的结果未定义。

BLOB和字符串绑定接口的第五个参数控制或指示第三个参数引用的对象的生命周期。存在以下三个选项：(1) 可以传递一个析构函数来处理SQLite完成使用后的BLOB或字符串。即使绑定API的调用失败，也会调用它来处理BLOB或字符串，除非第三个参数是NULL指针或第四个参数为负。(2) 可以传递特殊常量SQLITE_STATIC，以指示应用程序负责处理对象。在这种情况下，对象和指向它的指针必须保持有效，直到准备语句被最终确定，或者同一个SQL参数被绑定到其他内容，以先发生者为准。(3) 可以传递常量SQLITE_TRANSIENT，以指示在返回sqlite3_bind_*()之前先复制对象。对象和指向它的指针必须保持有效，直到那时。SQLite将管理其私有副本的生命周期。

`sqlite3_bind_text64()`的第六个参数必须是SQLITE_UTF8、SQLITE_UTF16、SQLITE_UTF16BE或SQLITE_UTF16LE之一，以指定第三个参数中文本的编码。如果`sqlite3_bind_text64()`的第六个参数不是上面允许的值之一，或者文本编码与第六个参数指定的编码不同，则行为未定义。

`sqlite3_bind_zeroblob()`例程绑定了一个长度为N的BLOB，该BLOB填充了零。零BLOB在处理时使用固定数量的内存（仅一个整数来保存其大小）。零BLOB旨在作为稍后使用增量BLOB I/O例程写入内容的BLOB的占位符。零BLOB的负值会导致零长度的BLOB。

`sqlite3_bind_pointer(S,I,P,T,D)`例程导致准备语句S中的第I个参数具有NULL的SQL值，但也与类型为T的指针P关联。D要么是NULL指针，要么是P的析构函数指针。SQLite在完成使用P后将调用析构函数D，带有一个P的单个参数。T参数应该是一个静态字符串，最好是一个字符串字面量。`sqlite3_bind_pointer()`例程是为SQLite 3.20.0添加的指针传递接口的一部分。

如果任何`sqlite3_bind_*()`例程被调用，并且准备了语句的指针为NULL，或者自上次调用`sqlite3_reset()`以来已经调用了`sqlite3_step()`，则该调用将返回SQLITE_MISUSE。如果任何`sqlite3_bind_()`例程传递了一个已经最终确定的准备语句，则结果未定义，可能有害。

`sqlite3_reset()`例程不会清除绑定。未绑定的参数被解释为NULL。

`sqlite3_bind_*`例程在成功时返回SQLITE_OK，如果出现问题则返回错误代码。如果字符串或BLOB的大小超过了由`sqlite3_limit(SQLITE_LIMIT_LENGTH)`或SQLITE_MAX_LENGTH施加的限制，则可能返回SQLITE_TOOBIG。如果参数索引超出范围，则返回SQLITE_RANGE。如果malloc()失败，则返回SQLITE_NOMEM。


# 示例
## sqlite3_bind
```c
    sqlite3_stmt *pstmt;
	const char *sql = "INSERT INTO person(name, age, sex) VALUES(?,?,?);";
	nRet = sqlite3_prepare_v2(pdb, sql, strlen(sql), &pstmt, &pzTail);
	int i;

	for(i = 0; i < 10; i++){
		nCol = 1; // 注意从 1 开始
		sqlite3_bind_text(pstmt, nCol++, a[i].name, strlen(a[i].name), NULL);
		sqlite3_bind_int(pstmt, nCol++, a[i].age);
		sqlite3_bind_text(pstmt, nCol++, a[i].sex, strlen(a[i].name), NULL);

		sqlite3_step(pstmt);
		sqlite3_reset(pstmt);
	}

	sqlite3_finalize(pstmt);
```
## sqlite3_column
```c
    sqlite3_stmt *pstmt;
	const char *sql = "SELECT* FROM person；";
	nRet = sqlite3_prepare_v2(pdb, sql, strlen(sql), &pstmt, &pzTail);

	while(sqlite3_step( pstmt ) == SQLITE_ROW){
		nCol = 0;
		pTmp = sqlite3_column_text(pstmt, nCol++);
		printf("%s|", pTmp);

		age = sqlite3_column_int(pstmt, nCol++);
		printf("%d|", age);

		pTmp = sqlite3_column_text(pstmt, nCol++);
		printf("%s\n", pTmp);

		//注意，这里就不能够运行 sqlite3_reset(pstmt); 因为查询命令会循环返回所有的数据，
        //每次返回一次 SQLITE_ROW,
		//如果我们重置pstmt，相当于终止了查询结果。
	}

	sqlite3_finalize(pstmt);
```
