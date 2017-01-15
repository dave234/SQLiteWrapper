# SQLiteWrapper

[![CI Status](http://img.shields.io/travis/dave234/SQLiteWrapper.svg?style=flat)](https://travis-ci.org/dave234/SQLiteWrapper)
[![Version](https://img.shields.io/cocoapods/v/SQLiteWrapper.svg?style=flat)](http://cocoapods.org/pods/SQLiteWrapper)
[![License](https://img.shields.io/cocoapods/l/SQLiteWrapper.svg?style=flat)](http://cocoapods.org/pods/SQLiteWrapper)
[![Platform](https://img.shields.io/cocoapods/p/SQLiteWrapper.svg?style=flat)](http://cocoapods.org/pods/SQLiteWrapper)

# A very lightweight SQLIte wrapper with a SQL like API
## Creation

There are four ObjC types:  
    NSString            => k_sql_type_text,  
    NSNumber(double)    => k_sql_type_real,  
    NSNumber(int)       => k_sql_type_int,  
    NSData              => k_sql_type_blob,  
Tables are constructed using an array of alternation column name/type strings
```
NSString *personTable   = @"personTable";
NSString *ageColumn     = @"ageKey";
NSString *nameColumn    = @"nameKey";
NSString *idColumn      = @"idKey";
SqliteWrapper *sqlWrap = [[SqliteWrapper alloc]initWithPath:dbpath];
[[sqlWrap create:personTable
    withKeyTypes:@[idColumn,     k_sql_type_integer_primary_key,
                   nameColumn,   k_sql_type_text,
                   ageColumn,    k_sql_type_int]
withConstraints:NULL]execute];
```
## Insertion

* The Query object returns itself from many of it's methods so that commands can be chained.
* The actual query is done when the execute command is called. The result command calls execute.
* The result command returns a NSArray of NSDictionaries, values are stored with the column name keys
* An insertID can be obtained from an insert query after it has been executed
* Methods that take a "value_s" argument can take an object or an array of objects 

```

NSDictionary *dorkusInfo    = @{nameColumn:@"Dorkus",ageColumn:@(64)};
NSDictionary *bipkusInfo    = @{nameColumn:@"Bipkus",ageColumn:@(35)};
NSDictionary *barneyInfo    = @{nameColumn:@"Barney",ageColumn:@(45)};
NSDictionary *jennyInfo     = @{nameColumn:@"Jenny",ageColumn:@(432)};

[[sqlWrap insertInto:personTable keysAndValues:dorkusInfo]execute];
[[sqlWrap insertInto:personTable keysAndValues:bipkusInfo]execute];
[[sqlWrap insertInto:personTable keysAndValues:barneyInfo]execute];
Query *jennyInsertQuery = [[sqlWrap insertInto:personTable keysAndValues:jennyInfo]execute];

[jennyInsertQuery checkError:@"jennyInsertQuery error"];

NSLog(@"print all %@",[[sqlWrap select:NULL from:personTable]results]);
```
## Updating
```
NSNumber *jennyID = jennyInsertQuery.insertID;

Query *updateQuery = [[[sqlWrap update:personTable keysAndValues:@{ageColumn: @(25)}] where:idColumn is:equal_to value_s:jennyID]execute];
[updateQuery checkError:@"jenny age update error"];

```
## Selecting
```
Query *namesQuery = [[sqlWrap select:nameColumn from:personTable]execute];
if (![namesQuery checkError:@"name query"]) {
    for (NSDictionary *result in namesQuery.results) {
        NSLog(@"%@",result[nameColumn]);
    }
}

Query *over30Query = [[[sqlWrap select:@[nameColumn,ageColumn] from:personTable]where:ageColumn is:greater_than value_s:@(30)]execute];

for (NSDictionary *result in over30Query.results) {
    NSLog(@"%@ is %@",result[nameColumn],result[ageColumn]);
}

Query *over30under50Query = [[[[sqlWrap select:@[nameColumn,ageColumn] from:personTable]where:ageColumn is:greater_than value_s:@(30)] where:ageColumn is:less_than value_s:@(50)]execute];

for (NSDictionary *result in over30under50Query.results) {
    NSLog(@"%@ is %@",result[nameColumn],result[ageColumn]);
}
```
## Deleting
```
[[[sqlWrap deleteFrom:personTable]where:nameColumn is:like_string value_s:@"%kus"]execute]; 
[[[sqlWrap deleteFrom:personTable]where:nameColumn is:equal_to value_s:@[@"Barney",@"Jenny"]]execute];

NSLog(@"all %@",[[sqlWrap select:NULL from:personTable]results]);
```


## Installation

SQLiteWrapper is available through [CocoaPods](http://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
pod "SQLiteWrapper"
```

## Author

dave234, dave234@users.noreply.github.com

## License

SQLiteWrapper is available under the MIT license. See the LICENSE file for more info.
