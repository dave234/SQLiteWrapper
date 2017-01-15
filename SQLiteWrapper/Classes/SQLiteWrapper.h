//
//  SQLiteWrapper.h
//  MidiBeatBoxFFT
//
//  Created by david oneill on 4/16/15.
//  Copyright (c) 2015 David O'Neill.
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

//#import <sqlite3.h>
#import <sqlite3/sqlite3.h>
#import <Foundation/Foundation.h>
#import <pthread.h>


FOUNDATION_EXPORT NSString *const k_sql_type_int;
FOUNDATION_EXPORT NSString *const k_sql_type_real;
FOUNDATION_EXPORT NSString *const k_sql_type_text;
FOUNDATION_EXPORT NSString *const k_sql_type_blob;
FOUNDATION_EXPORT NSString *const k_sql_type_text_primary_key;
FOUNDATION_EXPORT NSString *const k_sql_type_integer_primary_key;

typedef enum{
    not_equal_to    = 0x00,
    equal_to        = 0x01,
    greater_than    = 0x02,
    less_than       = 0x04,
    like_string     = 0x08,
}Comparator;

@interface NSArray(ArrayToCSV)
-(NSString *)toCSV;
@end

@interface NSString(ArrayToCSV)
-(NSArray *)intsFromCSV;
-(NSArray *)floatsFromCSV;
@end

@interface Query : NSObject
@property (readonly)    NSString                *statementString;
@property (readonly)    NSNumber                *insertID;
@property (readonly)    NSArray <NSDictionary *>*results;               //NSArray of NSDictionaries
@property (readonly)    NSString                *error;



-(Query *)where:(NSString *)key is:(Comparator)compare value_s:(id)value_s;
-(Query *)orderBy:(id)orderBy_s;
-(Query *)execute;
-(BOOL)checkError:(NSString *)msg;
@end


@interface SQLiteWrapper : NSObject
@property  NSMutableDictionary     *schema;
@property (readonly) sqlite3 *sqlite;

-(id)initWithPath:(NSString *)dbPath;
-(Query *)create:(NSString *)table withKeyTypes:(NSArray *)keyTypeArray withConstraints:(NSString *)constraints;
-(Query *)insertInto:(NSString *)table keysAndValues:(NSDictionary *)keysAndValues;
//-(Query *)replaceInto:(NSString *)table keysAndValues:(NSDictionary *)keysAndValues;
-(Query *)select:(id)key_s from:(NSString *)table;
-(Query *)update:(NSString *)table keysAndValues:(NSDictionary *)keysAndValues;
-(Query *)deleteFrom:(NSString *)table;
//-(Query *)join:(Query *)query;
-(NSArray *)keysForTable:(NSString *)table;
-(NSArray *)tables;
-(int)beginTransaction;
-(int)endTransaction;
-(void)lock;
-(void)unlock;
-(void)printAll;
-(void)alter:(NSString *)table addColumn:(NSString*)columnName ofType:(NSString *)type;
-(void)rebuildSchema;
NSString *desc(NSString *orderBy);
-(NSData *)dataBaseData;
@end


//Here is the format for creating database with tables











