//
//  SQLiteWrapper.m
//  MidiBeatBoxFFT
//
//  Created by david oneill on 4/16/15.
//  Copyright (c) 2015 David O'Neill..
//

/*
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *
 */

#import <sqlite3.h>
#import "SQLiteWrapper.h"

NSString *const k_sql_type_int =                    @"integer";
NSString *const k_sql_type_real =                   @"real";
NSString *const k_sql_type_blob =                   @"blob";
NSString *const k_sql_type_text =                   @"text";
NSString *const k_sql_type_integer_primary_key =    @"integer primary key";
NSString *const k_sql_type_text_primary_key =       @"text primary key";


NSString *const k_sql_table_name =                  @"table_name";
NSString *const k_sql_column_keys =                 @"column_key";
NSString *const k_sql_column_type =                 @"column_type";
NSString *const k_sql_column_blocks =               @"column_block";


NSString *const k_comparator_key =                  @"comparator";
NSString *const k_sql_where_values =                @"values";
//NSString *const k_sql_joins =                       @"joins";

typedef enum{
    QueryTypeSelect,
    QueryTypeInsert,
    QueryTypeUpdate,
    QueryTypeDelete,
    QueryTypeCreateTable
}QueryType;

static NSArray* forceArray(id object){
    if (object) {
        if ([object isKindOfClass:[NSArray class]]) {
            return object;
        }
        else{
            return @[object];
        }
    }
    return NULL;
}

//These are convenience methods to (de)serialize short arrays of doubles or ints to be stored as strings.
@implementation NSArray(ArrayToCSV)
-(NSString *)toCSV{
    NSMutableString *csvString = [[NSMutableString alloc]init];
    for (NSNumber *number in self){
        [csvString appendFormat:@"%@,",number.stringValue];
    }
    [csvString deleteCharactersInRange:NSMakeRange(csvString.length - 1, 1)];
    return csvString;
}


@end
@implementation NSString(ArrayToCSV)
-(NSArray *)intsFromCSV{
    return [[self componentsSeparatedByString:@","]valueForKey:@"intValue"];
}
-(NSArray *)floatsFromCSV{
    return [[self componentsSeparatedByString:@","]valueForKey:@"doubleValue"];
}
@end


@interface Query()
@property (weak)        SQLiteWrapper           *sqliteWrapper;
@property               NSString                *table;
@property               NSArray                 *keys;
@property               NSArray                 *values;
@property               NSArray                 *types;
@property (readonly)    NSMutableDictionary     *queryData;
@property (readonly)    NSMutableArray          *whereClauses;  //array of dictionary containing NSString key,NSNumber comparator,and NSArray of values
@property (readonly)    NSMutableArray          *orderBys;      //array of keys to order by
@property               QueryType               queryType;
@property (readonly)    BOOL                    hasWhereClauses;
@property (readonly)    BOOL                    hasOrderBys;
-(NSString *)buildSelectString;
@end

@implementation NSArray (ContainsString)
-(BOOL)containsString:(NSString *)string{
    for (NSString *exString in self) {
        if ([exString isEqualToString:string]) {
            return 1;
        }
    }
    return 0;
}
@end


typedef int (^BindBlock)(sqlite3_stmt *,id, int);
typedef id (^ColumnBlock)(sqlite3_stmt *,int);


@interface SQLiteWrapper()
@property (readonly)    sqlite3    *database;
@end


//_blockTable contains the blocks which convert sqlite bindings to their ObjC counterparts. The k_sql_type constants are the keys.
//When a table is created,

@implementation SQLiteWrapper{
    pthread_mutex_t *mutex;
    NSDictionary *_blockTable;
    NSString *_path;
}

-(id)initWithPath:(NSString *)dbPath{
    
    self = [super init];
    if (self) {
        if (sqlite3_open(dbPath.UTF8String, &_database) != SQLITE_OK){
            printf("error opening database\n");
        }
        else{
            _path = dbPath;
            mutex = malloc(sizeof(pthread_mutex_t));
            pthread_mutex_init(mutex, NULL);
            _blockTable = createBlockTable();
            _schema = [[NSMutableDictionary alloc]init];
            [self rebuildSchema];
        }
        
    }
    return self;
}
-(NSData *)dataBaseData{
    int err = sqlite3_close(_database);
    if (err)printf("%s\n", sqlite3_errmsg(_database));
    NSError *error = NULL;
    NSData *data = [NSData dataWithContentsOfFile:_path];
    if(err)NSLog(@"copyDatabase %@",error);
    if (sqlite3_open(_path.UTF8String, &_database) != SQLITE_OK){
        printf("error opening database\n");
    }
    return data;
}

-(void)alter:(NSString *)table addColumn:(NSString*)columnName ofType:(NSString *)type{
    
    NSString *alterString = [NSString stringWithFormat:@"ALTER TABLE %@ ADD COLUMN %@ %@",table,columnName,type];
    char *error = NULL;
    int status = sqlite3_exec(self.database, alterString.UTF8String, NULL, NULL, &error);
    if (status != SQLITE_OK) {
        NSLog(@"addColumn error %s",error);
        return;
    }

    
}

-(Query *)create:(NSString *)table withKeyTypes:(NSArray *)keyTypeArray withConstraints:(NSString *)constraints{
    Query *query = [[Query alloc]init];
    query.sqliteWrapper = self;
    
    query.queryType = QueryTypeCreateTable;
    
    if ([query.sqliteWrapper tableExists:table]) {
        NSLog(@"table %s exists",table.UTF8String);
        return query;
    }
    
    NSMutableArray *createTypes = [[NSMutableArray alloc]initWithCapacity:keyTypeArray.count / 2];
    NSMutableArray *createKeys = [[NSMutableArray alloc]initWithCapacity:keyTypeArray.count / 2];
    NSMutableString *stmtString = [[NSMutableString alloc]initWithFormat:@"create table if not exists %@(",table];
    for (int i = 0; i < keyTypeArray.count; i += 2){
        [createKeys addObject:keyTypeArray[i]];
        [createTypes addObject:keyTypeArray[i +1]];
        [stmtString appendString:[NSString stringWithFormat:@" %@ %@,",keyTypeArray[i],keyTypeArray[i + 1]]];
    }
    
    if (constraints) {
        [stmtString appendFormat:@" CONSTRAINT %@",constraints];
    }
    else{
        [stmtString deleteCharactersInRange:NSMakeRange(stmtString.length - 1, 1)];
    }
    [stmtString appendString:@")"];
    
    
    query.table = table;
    query.keys  = [NSArray arrayWithArray:createKeys];
    query.types = [NSArray arrayWithArray:createTypes];
    [query.queryData setObject:[NSString stringWithString:stmtString] forKey:@"statementString"];
    return query;
}

//-(Query *)replaceInto:(NSString *)table keysAndValues:(NSDictionary *)keysAndValues{
//    return [self _insertInto:table keysAndValues:keysAndValues replace:1];
//}
-(Query *)insertInto:(NSString *)table keysAndValues:(NSDictionary *)keysAndValues{
    return [self _insertInto:table keysAndValues:keysAndValues replace:0];
}
-(Query *)_insertInto:(NSString *)table keysAndValues:(NSDictionary *)keysAndValues replace:(BOOL)replace{
    Query *query = [[Query alloc]init];
    query.sqliteWrapper = self;
    query.queryType = QueryTypeInsert;
    query.table = table;
    query.keys = keysAndValues.allKeys;
    NSMutableArray *insertValues = [[NSMutableArray alloc]initWithCapacity:keysAndValues.count];
    NSMutableString *stmtString = [[NSMutableString alloc]initWithFormat:@"%s into %@ (",replace ? "replace" : "insert",table];
    for (NSString *key in query.keys) {
        [insertValues addObject:keysAndValues[key]];
        [stmtString appendFormat:@" %@,",key];
    }
    [stmtString deleteCharactersInRange:NSMakeRange(stmtString.length - 1, 1)];
    [stmtString appendString:@") values (?"];
    for (int i = 1; i < query.keys.count; i++) {
        [stmtString appendString:@",?"];
    }
    [stmtString appendString:@")"];
    [query.queryData setObject:[NSString stringWithString:stmtString] forKey:@"statementString"];
    query.values = [NSArray arrayWithArray:insertValues];
    
    return query;
}
-(Query *)select:(id)key_s from:(NSString *)table{
    Query *query = [[Query alloc]init];
    query.sqliteWrapper = self;
    query.queryType = QueryTypeSelect;
    query.table = table;
    if (key_s) {
        query.keys = forceArray(key_s);
    }
    return query;
}
-(Query *)update:(NSString *)table keysAndValues:(NSDictionary *)keysAndValues{
    Query *query = [[Query alloc]init];
    query.sqliteWrapper = self;
    query.queryType = QueryTypeUpdate;
    query.table = table;
    query.keys = keysAndValues.allKeys;
    NSMutableArray *updateValues = [[NSMutableArray alloc]initWithCapacity:keysAndValues.count];
    for (NSString *key in query.keys) {
        [updateValues addObject:keysAndValues[key]];
    }
    query.values = [NSArray arrayWithArray:updateValues];
    return query;
}
-(Query *)deleteFrom:(NSString *)table{
    Query *query = [[Query alloc]init];
    query.sqliteWrapper = self;
    query.queryType = QueryTypeDelete;
    query.table = table;
    
    return query;
}
-(NSMutableArray *)fetchTableNames
{
    sqlite3_stmt* statement;
    NSString *query = @"SELECT name FROM sqlite_master WHERE type=\'table\'";
    int retVal = sqlite3_prepare_v2(self.database,
                                    [query UTF8String],
                                    -1,
                                    &statement,
                                    NULL);
    
    NSMutableArray *selectedRecords = [NSMutableArray array];
    if ( retVal == SQLITE_OK )
    {
        while(sqlite3_step(statement) == SQLITE_ROW )
        {
            NSString *value = [NSString stringWithCString:(const char *)sqlite3_column_text(statement, 0)
                                                 encoding:NSUTF8StringEncoding];
            [selectedRecords addObject:value];
        }
    }
    
//    sqlite3_clear_bindings(statement);
    sqlite3_finalize(statement);
    
    return selectedRecords;
}


-(NSArray *)tables{
    return self.schema.allKeys;
}
-(NSArray *)keysForTable:(NSString *)table{
    return self.schema[table][k_sql_column_keys];
}

static NSDictionary *createBlockTable(){
    BOOL(^valNull)(id) = ^BOOL(id p){
        static id _snull = NULL;
        if (!_snull) {
            _snull = [NSNull null];
        }
        return p == _snull;
    };
    BOOL(^colNull)(sqlite3_stmt*,int) = ^BOOL(sqlite3_stmt* stmt, int column){
        return sqlite3_column_type(stmt, column) == SQLITE_NULL;
    };
    
    NSArray *stringBinders  = @[
                                ^int (sqlite3_stmt *stmt, NSString *string, int column){
                                    return valNull(string) ? sqlite3_bind_null(stmt, column) : sqlite3_bind_text(stmt, column, string.UTF8String, (int)string.length + 1, SQLITE_STATIC);
                                },
                                 ^NSString *(sqlite3_stmt *stmt, int column){
                                     return colNull(stmt, column) ? (NSString *)[NSNull null] : [NSString stringWithUTF8String:(char *)sqlite3_column_text(stmt, column)];
                                 }];
    NSArray *intBinders     = @[
                                ^int (sqlite3_stmt *stmt, NSNumber *number, int column){
                                    return valNull(number) ? sqlite3_bind_null(stmt, column) : sqlite3_bind_int(stmt, column, [number intValue]);
                                },
                                 ^NSNumber *(sqlite3_stmt *stmt, int column){
                                     return colNull(stmt, column) ? (NSNumber *)[NSNull null] : [NSNumber numberWithInt:sqlite3_column_int(stmt, column)];
                                 }];
    
    NSArray *doubleBinders  = @[
                                ^int (sqlite3_stmt *stmt, NSNumber *number, int column){
                                    return valNull(number) ? sqlite3_bind_null(stmt, column) : sqlite3_bind_double(stmt, column, [number doubleValue]);
                                },
                                 ^NSNumber *(sqlite3_stmt *stmt, int column){
                                     return colNull(stmt, column) ? (NSNumber *)[NSNull null] : [NSNumber numberWithDouble:sqlite3_column_double(stmt, column)];
                                 }];
    NSArray *blobBinders    = @[
                                ^int (sqlite3_stmt *stmt, NSData *data, int column){
                                    return valNull(data) ? sqlite3_bind_null(stmt, column) : sqlite3_bind_blob(stmt, column, data.bytes, (int)data.length, SQLITE_STATIC);
                                },
                                 ^NSData *(sqlite3_stmt *stmt, int column){
                                     if (colNull(stmt,column)) {
                                         return (NSData *)[NSNull null];
                                     }
                                     int length = sqlite3_column_bytes(stmt, column);
                                     const void *blob = sqlite3_column_blob(stmt, column);
                                     return [NSData dataWithBytes:blob length:length];
                                 }];
    
    NSDictionary *blockTable = [NSDictionary dictionaryWithObjectsAndKeys:
                                stringBinders,k_sql_type_text,
                                stringBinders,k_sql_type_text_primary_key,
                                intBinders,k_sql_type_int,
                                intBinders,k_sql_type_integer_primary_key,
                                doubleBinders,k_sql_type_real,
                                blobBinders,k_sql_type_blob,
                                nil];
    
    return blockTable;

}

static BindBlock BindToKey(NSDictionary *table,NSString *key){
    return table[k_sql_column_blocks][key][0];
}
static ColumnBlock ColumnFromKey(NSDictionary *table,NSString *key){
    return table[k_sql_column_blocks][key][1];
}

-(void)lock{
//    pthread_mutex_lock(mutex);
}
-(void)unlock{
//    pthread_mutex_unlock(mutex);
}
-(void)rebuildSchema{
    NSArray *tablenames = [self fetchTableNames];
    for(NSString *table in tablenames){
        NSDictionary *mutKeysMutTypes = @{k_sql_column_keys:[[NSMutableArray alloc]init],
                                          k_sql_column_type:[[NSMutableArray alloc]init]};
        
        NSString *query = [NSString stringWithFormat:@"PRAGMA table_info(%@);",table];
        char *error = NULL;
        sqlite3_exec(self.database, query.UTF8String, add_key_types_to_arrays, (__bridge void *)mutKeysMutTypes, &error);
        [self addTableToSchema:table withKeys:mutKeysMutTypes[k_sql_column_keys] andTypes:mutKeysMutTypes[k_sql_column_type]];
    }
}
int add_key_types_to_arrays(void *user_data, int argc, char **argv,
                            char **azColName) {
    NSDictionary *mutKeysMutTypes = (__bridge NSDictionary *)user_data;
    NSMutableArray *keys = mutKeysMutTypes[k_sql_column_keys];
    NSMutableArray *types = mutKeysMutTypes[k_sql_column_type];
    [keys addObject:[NSString stringWithUTF8String:argv[1]]];
    if (!strcmp("1",argv[5]) && !strcmp(argv[2], "integer")) {
        [types addObject:k_sql_type_integer_primary_key];
    }
    else{
        [types addObject:[NSString stringWithUTF8String:argv[2]]];
    }
//    for (int i = 0; i < argc; i++) {
//        printf("argv[%i] = %s\n",i,argv[i]);
//    }
    return 0;
}
-(BOOL)tableExists:(NSString *)table{
    NSString *tableExistsString = [NSString stringWithFormat:@"SELECT name FROM sqlite_master WHERE type='table' AND name='%@';",table];
    sqlite3_stmt *stmt = NULL;
    sqlite3_prepare_v2(self.database, tableExistsString.UTF8String, -1, &stmt, NULL);
    sqlite3_step(stmt);
    const unsigned char *table_name = sqlite3_column_text(stmt, 0);
    BOOL tableExists = table_name != NULL;
    sqlite3_finalize(stmt);
    return tableExists;
}
-(void)addTableToSchema:(NSString *)table withKeys:(NSArray *)keys andTypes:(NSArray *)types{
    
    NSMutableDictionary *blocks = [[NSMutableDictionary alloc]initWithCapacity:keys.count];
    for (int i = 0; i < keys.count; i ++){
        [blocks setObject:_blockTable[types[i]] forKey:keys[i]];
    }
    
    NSDictionary *tableDict =   [NSDictionary dictionaryWithObjectsAndKeys:
                                 [NSArray arrayWithArray:keys],                       k_sql_column_keys,
                                 [NSArray arrayWithArray:types],                      k_sql_column_type,
                                 [NSDictionary dictionaryWithDictionary:blocks],      k_sql_column_blocks,
                                 nil];
    
    [self.schema setObject:tableDict forKey:table];
}
-(void)reset{
    
}
-(void)dealloc{
    pthread_mutex_destroy(mutex);
    free(mutex);
    int err = sqlite3_close(_database);
    if (err) printf("sqlite dealloc %s\n",sqlite3_errstr(err));
    printf("dealloc----------------    SQLiteWrapper dealloc    -------------- ------------ - - - -- \n");
}
-(int)beginTransaction{
    int error = sqlite3_exec(self.database, "BEGIN TRANSACTION;", NULL, NULL, NULL);
    if (error) {
        const char *ermsg = sqlite3_errmsg(self.database);
        printf("BEGIN TRANSACTION error %s\n",ermsg);
    }
    return error;
}
-(int)endTransaction{

    int error = sqlite3_exec(self.database, "END TRANSACTION;", NULL, NULL, NULL);
    if (error) {
        const char *ermsg = sqlite3_errmsg(self.database);
        printf("END TRANSACTION error %s\n",ermsg);
    }
    return error;
    
}
-(void)printAll{
    NSArray *tables = [self tables];
    for (NSString *table in tables){
        NSLog(@"\n------------- %@ -------------\n",table);
        NSArray *results = [[self select:NULL from:table]results];
        for (NSDictionary *result in results){
            NSLog(@"%@",result);
        }
    }
}

@end














@implementation Query{
    NSMutableDictionary    *_queryData;
}
-(id)init{
    self = [super init];
    if (self) {
        _queryData = [[NSMutableDictionary alloc]init];
    }
    return self;
}
-(NSMutableDictionary *)queryData{
    return _queryData;
}
#pragma mark
#pragma mark Create

-(void)executeCreate{

    if (self.table && self.keys && self.keys.count) {
        char *error = NULL;
        int status = sqlite3_exec(self.sqliteWrapper.database, self.statementString.UTF8String, NULL, NULL, &error);
        if (status != SQLITE_OK) {
            self.error = [NSString stringWithUTF8String:error ?: sqlite3_errstr(status)];
            return;
        }
        [self.sqliteWrapper addTableToSchema:self.table withKeys:self.keys andTypes:self.types];
    }
    else{
        printf("not creating\n");
    }
}
#pragma mark
#pragma mark Insert

-(NSString *)buildInsertString{

    NSMutableString *stmtString = [[NSMutableString alloc]initWithFormat:@"insert into %@ (",self.table];
    for (NSString *key in self.keys) {
        [stmtString appendFormat:@" %@,",key];
    }
    [stmtString deleteCharactersInRange:NSMakeRange(stmtString.length - 1, 1)];
    [stmtString appendString:@") values (?"];
    for (int i = 1; i < self.keys.count; i++) {
        [stmtString appendString:@",?"];
    }
    [stmtString appendString:@")"];
    
    return stmtString;
}
-(void)executeInsert{

    NSDictionary *tableDict = self.sqliteWrapper.schema[self.table];
    if (!tableDict) {
        return;
    }
    sqlite3_stmt *stmt = [self statement];
    if (self.error) {
        return;
    }
    int binder = 1;
    for (int i = 0; i < self.values.count; i++){
        
        BindBlock bindBlock = BindToKey(tableDict, self.keys[i]);
        if (!bindBlock) {
            self.error = [NSString stringWithFormat:@"wrong table or key on insert couldn't bind %@.%@",self.table,self.keys[i]];
            sqlite3_finalize(stmt);
            return;
        }
        int status = bindBlock(stmt ,self.values[i],binder);
        if (status) {
            self.error = [NSString stringWithUTF8String:sqlite3_errmsg(self.sqliteWrapper.database)];
            sqlite3_finalize(stmt);
            return;
        }
        binder++;
    }
    if ([tableDict[k_sql_column_type]containsString:k_sql_type_integer_primary_key]) {
        [self step:stmt];
        int64_t rowID = sqlite3_last_insert_rowid(self.sqliteWrapper.database);
        self.insertID = [NSNumber numberWithInt:(int)rowID];
    }
    else{
        [self step:stmt];
    }
    sqlite3_finalize(stmt);
    return;
}
#pragma mark
#pragma mark Select

-(NSString *)buildSelectString{
    
    NSMutableString *stmtString = [[NSMutableString alloc]initWithString:@"select "];
    
    if (self.keys) {
        [stmtString appendString:self.keys.firstObject];
        for (int i = 1; i < self.keys.count; i++){
//            [stmtString appendFormat:@", %@",self.keys[i]];
            [stmtString appendFormat:@", %@",[NSString stringWithFormat:@"%@.%@",self.table,self.keys[i]]];
        }
    }
    
    [stmtString appendFormat:@" from %@ ",self.table];
    
    if (self.hasWhereClauses && self.whereClauses.count) {
        [self addWhereClauses:self.whereClauses ToStatmentString:stmtString];
    }
    
    if (self.hasOrderBys && self.orderBys.count) {
        [stmtString appendFormat:@" order by %@",self.orderBys.firstObject];
        for (int i = 1; i < self.orderBys.count;i++){
            [stmtString appendFormat:@", %@",self.orderBys[i]];
        }
    }
    
    return [NSString stringWithString:stmtString];
}
-(int)bindWhereClauses:(sqlite3_stmt *)stmt bindStart:(int)bindStart{
    int binder = bindStart;
    if (self.hasWhereClauses) {
        NSDictionary *tableDict = self.sqliteWrapper.schema[self.table];
        for (NSDictionary *clause in self.whereClauses){
            for (id value in [clause objectForKey:k_sql_where_values]){
                BindBlock bindBlock = BindToKey(tableDict, clause[k_sql_column_keys]);
                if (!bindBlock) {
                    self.error = [NSString stringWithFormat:@"wrong table or key couldn't bind %@.%@ to where clause",self.table,clause[k_sql_column_keys]];
                    return binder;
                }
                int status = bindBlock(stmt,value,binder);
                if (status != SQLITE_OK) {
                    self.error = [NSString stringWithUTF8String:sqlite3_errmsg(self.sqliteWrapper.database)];
                    return binder;
                }
                binder++;
            }
        }
    }
    return binder;
}

-(void)executeSelect{
    NSDictionary *tableDict = self.sqliteWrapper.schema[self.table];
    if (!self.keys) {
        self.keys = tableDict[k_sql_column_keys];
    }
    sqlite3_stmt *stmt = [self statement];
    if (self.error) {
        return;
    }
    [self bindWhereClauses:stmt bindStart:1];
    if (self.error) {
        return;
    }
    NSMutableArray *rows = [[NSMutableArray alloc]init];
    int status = 0;
    while ((status = sqlite3_step(stmt)) == SQLITE_ROW) {
        NSMutableDictionary *rowInfo = [NSMutableDictionary dictionaryWithCapacity:self.keys.count];
        int column = 0;
        for (NSString *key in self.keys){
            ColumnBlock columnBlock = ColumnFromKey(tableDict, key);
            [rowInfo setValue:[columnBlock(stmt,column) copy] forKey:key];
            column++;
        }
//        [rowInfo setObject:[[Canary alloc]init] forKey:@"canary"];
        [rows addObject:[NSDictionary dictionaryWithDictionary:rowInfo]];
    }
    if (status != SQLITE_DONE) {
        const char *error = sqlite3_errmsg(self.sqliteWrapper.database);
        printf("error %s\n",error);
    }
    sqlite3_finalize(stmt);
    self.results = [NSArray arrayWithArray:rows];
}
#pragma mark
#pragma mark Update

-(NSString *)buildUpdateString{
    NSMutableString *stmtString = [[NSMutableString alloc]initWithFormat:@"update %@ set %@ = ?",self.table,self.keys[0]];
    for (int i = 1; i < self.keys.count;i++) {
        [stmtString appendString:[NSString stringWithFormat:@", %@ = ?",self.keys[i]]];
    }
    if (self.hasWhereClauses && self.whereClauses.count) {
        [self addWhereClauses:self.whereClauses ToStatmentString:stmtString];
    }
    return stmtString;
}
-(void)addWhereClauses:(NSArray *)whereClauses ToStatmentString:(NSMutableString *)stmtString{
    NSString *whereAnd = @"where";
    for (NSDictionary *whereClause in whereClauses){
        NSString *tableKey = [NSString stringWithFormat:@"%@.%@",self.table,whereClause[k_sql_column_keys]];
        [stmtString appendFormat:@" %@ %@ %@ (?",whereAnd,tableKey,whereClause[k_comparator_key]];
        int valueCount = (int)[whereClause[k_sql_where_values]count];
        for (int i = 1; i < valueCount; i++) {
            [stmtString appendString:@",?"];
        }
        [stmtString appendString:@")"];
        whereAnd = @"and";
    }
}
-(void)executeUpdate{
    NSDictionary *tableDict = self.sqliteWrapper.schema[self.table];
    sqlite3_stmt *stmt = [self statement];
    if (self.error) {
        return;
    }
    int binder = 1;
    for (int i = 0; i < self.values.count; i++){
        BindBlock bindBlock = BindToKey(tableDict, self.keys[i]);
        if (!bindBlock) {
            self.error = [NSString stringWithFormat:@"wrong table or key on update couldn't bind %@.%@",self.table,self.keys[i]];
            return;
        }
        int status = bindBlock(stmt ,self.values[i],binder);
        if (status) {
            self.error = [NSString stringWithUTF8String:sqlite3_errmsg(self.sqliteWrapper.database)];
            return;
        }
        binder++;
    }
    [self bindWhereClauses:stmt bindStart:binder];
    if (self.error) {
        return;
    }
    [self step:stmt];
    sqlite3_finalize(stmt);
}
-(sqlite3_stmt *)statement{
    sqlite3_stmt *stmt = NULL;
    int status = sqlite3_prepare_v2(self.sqliteWrapper.database, self.statementString.UTF8String, -1, &stmt, NULL);
    if (status != SQLITE_OK) {
        const char *error = sqlite3_errmsg(self.sqliteWrapper.database);
        self.error = [NSString stringWithUTF8String:error];
    }
    return stmt;
}

#pragma mark
#pragma mark Delete

-(NSString *)buildDeleteString{
    NSMutableString *delString = [[NSMutableString alloc]initWithFormat:@"delete from %@",self.table];
    if (self.hasWhereClauses && self.whereClauses.count) {
        [self addWhereClauses:self.whereClauses ToStatmentString:delString];
    }
    return [NSString stringWithString:delString];
}
-(void)executeDelete{
    sqlite3_stmt *stmt = [self statement];
    if (self.error) {
        return;
    }
    [self bindWhereClauses:stmt bindStart:1];
    if (self.error) {
        return;
    }
    sqlite3_step(stmt);
    sqlite3_finalize(stmt);
}

#pragma mark
#pragma mark Join

//-(Query *)join:(Query *)query{
//    NSMutableArray *joins = self.queryData[k_sql_joins];
//    if (!joins) {
//        joins = [[NSMutableArray alloc]init];
//        self.queryData[k_sql_joins] = joins;
//    }
//    if (self.queryData != QueryTypeSelect) {
//        self.error = @"error, sqlite only joins select statements";
//    }
//    
//    return self;
//}

#pragma mark


-(Query *)where:(NSString *)key is:(Comparator)compare value_s:(id)value_s{
    if (self.error) {
        return self;
    }
    [self.whereClauses addObject:@{k_sql_column_keys:    key,
                                   k_comparator_key:     comparatorStringForType(compare),
                                   k_sql_where_values:       forceArray(value_s)}];
    _hasWhereClauses = 1;
    return self;
}
NSString *desc(NSString *orderBy){
    return [orderBy stringByAppendingString:@" DESC"];
}
-(Query *)orderBy:(id)orderBy_s{
    if (self.error) {
        return self;
    }
    [self.orderBys addObjectsFromArray:forceArray(orderBy_s)];
    _hasOrderBys = 1;
    return self;
}
-(NSString *)statementString{
    
    if (self.queryType == QueryTypeSelect) {
        return [self buildSelectString];
    }
    else if (self.queryType == QueryTypeUpdate){
        return [self buildUpdateString];
    }
    else if (self.queryType == QueryTypeDelete){
        return [self buildDeleteString];
    }
    return self.queryData[@"statementString"];
}



static NSString *comparatorStringForType(Comparator comparator){
    int val = comparator;
    switch (val) {
        case 0:
            return @"not in";
        case 1:
            return @"in";
        case 2:
            return @">";
        case 3:
            return @">=";
        case 4:
            return @"<";
        case 5:
            return @"<=";
        case 8:
            return @"LIKE";
        default:
            return @"in";
    }
}
-(void)setTable:(NSString *)table{
    [self.queryData setValue:table forKey:k_sql_table_name];
}
-(NSString *)table{
    return self.queryData[k_sql_table_name];
}

-(void)setKeys:(NSArray *)keys{
    [self.queryData setValue:keys forKey:k_sql_column_keys];
}
-(NSArray *)keys{
    return self.queryData[k_sql_column_keys];
}
-(void)setTypes:(NSArray *)types{
    [self.queryData setValue:types forKey:k_sql_column_type];
}
-(NSArray *)types{
    return self.queryData[k_sql_column_type];
}

-(NSMutableArray *)whereClauses{
    NSMutableArray *whereClauses = self.queryData[@"where_clauses"];
    if (!whereClauses) {
        whereClauses = [[NSMutableArray alloc]init];
        [self.queryData setObject:whereClauses forKey:@"where_clauses"];
    }
    return whereClauses;
}
-(NSMutableArray *)orderBys{
    NSMutableArray *orderBys = self.queryData[@"order_bys"];
    if (!orderBys) {
        orderBys = [[NSMutableArray alloc]init];
        [self.queryData setObject:orderBys forKey:@"order_bys"];
    }
    return orderBys;
}
-(void)setResults:(NSArray *)results{
    [self.queryData setObject:results forKey:@"results"];
}
-(NSArray <NSDictionary *> *)results{
    if (!self.queryData[@"results"]) {
        if (!self.queryData[@"executed"]) {
            [self execute];
        }
    }
//    NSArray *results = self.queryData[@"results"];
//    for (NSDictionary *result in results){
////        if([result.allValues containsObject:[NSNull null]]){
////            whoCalled(6);
////        }
//        for (NSString *key in result.allKeys){
//            if (result[key] == [NSNull null]) {
//                NSLog(@"%@->%@ ",self.table,key);
//            }
//        }
//    }
    return self.queryData[@"results"];
}
-(Query *)execute{
    //    [self results];
    
    if (self.error) {
        [self checkError:@"implicitCheck"];
        return self;
    }
    
    switch (self.queryType) {
        case QueryTypeSelect:
            [self executeSelect];
            break;
            
        case QueryTypeInsert:
            [self executeInsert];
            break;
            
        case QueryTypeUpdate:
            [self executeUpdate];
            break;
            
        case QueryTypeDelete:
            [self executeDelete];
            break;
            
        case QueryTypeCreateTable:
            [self executeCreate];
            break;
            
        default:
            break;
    }
    
    [self.queryData setObject:@1 forKey:@"executed"];
    [self checkError:@"implicitCheck"];
    return self;
}

-(void)setInsertID:(NSNumber *)insertID{
    [self.queryData setObject:insertID forKey:@"insertID"];
}
-(NSNumber *)insertID{
    return [self.queryData objectForKey:@"insertID"];
}
-(NSString *)error{
    return [self.queryData objectForKey:@"error"];
}
-(void)setError:(NSString *)errorMessage{
    [self.queryData setObject:errorMessage forKey:@"error"];
}
-(int)step:(sqlite3_stmt *)stmt{
    int status = sqlite3_step(stmt);
    if (status == SQLITE_ERROR || status == SQLITE_MISUSE) {
        const char *error = sqlite3_errmsg(self.sqliteWrapper.database);
        self.error = [NSString stringWithUTF8String:error];
        return 1;
    }
    return 0;
}
-(BOOL)checkError:(NSString *)msg{
    if (self.error) {
        NSLog(@"%@ %@",msg ? msg : @"",self.error);
        return 1;
    }
    return 0;
}

@end
















