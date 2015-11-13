//
//  LocalPredicates.m
//  CDTIncrementalStoreTest
//
//  Created by Jimi Xenidis on 5/20/15.
//
//

#import <XCTest/XCTest.h>
#import <Foundation/Foundation.h>

#import "Local.h"

static const BOOL sql = NO;


@interface LocalPredicates: LocalTestCase

@end


@implementation LocalPredicates

- (void)setUp {
    [super setUpForSQL:sql];
}

- (void)testPredicates
{
    int max = 100;

    XCTAssertTrue((max % 4) == 0, @"Test assumes max is mod 4: %d", max);

    NSError *err = nil;
    // This will create the database
    NSManagedObjectContext *moc = self.managedObjectContext;
    XCTAssertNotNil(moc, @"could not create Context");

    NSArray *textvals = @[ @"apple", @"orange", @"banana", @"strawberry" ];

    // A local array for verifying predicate results
    NSMutableArray *entries = [NSMutableArray array];

    for (int i = 0; i < max; i++) {
        Entry *e = MakeEntry(moc);
        // check will indicate if value is an even number
        e.check = (i % 2) ? @NO : @YES;
        e.i64 = @(i);
        e.fpFloat = @(((float)(M_PI)) * (float)i);
        e.text = textvals[i % [textvals count]];
        [entries addObject:e];
    }

    // push it out
    XCTAssertTrue([moc save:&err], @"Save Failed: %@", err);

    NSArray *results, *expected, *check;
    /**
     *  Fetch boolean == value
     */

    NSFetchRequest *fr = [NSFetchRequest fetchRequestWithEntityName:@"Entry"];
    fr.shouldRefreshRefetchedObjects = YES;
    fr.predicate = [NSPredicate predicateWithFormat:@"check == YES"];

    results = [moc executeFetchRequest:fr error:&err];
    XCTAssertNotNil(results, @"Expected results: %@", err);

    expected = [entries filteredArrayUsingPredicate:fr.predicate];

    XCTAssertTrue([results count] == [expected count], @"results count is %ld but should be %ld",
                  (unsigned long)[results count], (unsigned long)[expected count]);

    check = [results filteredArrayUsingPredicate:fr.predicate];

    XCTAssertTrue([check count] == [results count],
                  @"results array contains entries that do not satisfy predicate");

    /**
     *  Fetch boolean == value
     */
    NSPredicate *odd = [NSPredicate predicateWithFormat:@"check == NO"];
    fr.predicate = odd;

    results = [moc executeFetchRequest:fr error:&err];
    XCTAssertNotNil(results, @"Expected results: %@", err);

    XCTAssertTrue([results count] == (max / 2), @"results count should be %d is %@", max / 2,
                  @([results count]));

    for (Entry *e in results) {
        XCTAssertFalse([e.check boolValue], @"not odd?");

        long long val = [e.i64 longLongValue];
        XCTAssertTrue((val % 2) == 1, @"entry.i64 should be odd");
    }

    /**
     *  fetch NSNumber == value
     */
    fr.predicate = [NSPredicate predicateWithFormat:@"i64 == %u", max / 2];

    results = [moc executeFetchRequest:fr error:&err];
    XCTAssertNotNil(results, @"Expected results: %@", err);

    XCTAssertTrue([results count] == 1, @"results count should be %d is %@", 1, @([results count]));

    for (Entry *e in results) {
        long long val = [e.i64 longLongValue];
        XCTAssertTrue(val == (max / 2), @"entry.i64 should be %d is %lld", max / 2, val);
    }

    /**
     *  fetch NSNumber != value
     */
    fr.predicate = [NSPredicate predicateWithFormat:@"i64 != %u", max / 2];

    results = [moc executeFetchRequest:fr error:&err];
    XCTAssertNotNil(results, @"Expected results: %@", err);

    XCTAssertTrue([results count] == (max - 1), @"results count should be %d is %@", max - 1,
                  @([results count]));

    for (Entry *e in results) {
        long long val = [e.i64 longLongValue];
        XCTAssertTrue(val != (max / 2), @"entry.i64 should not be %d is %lld", max / 2, val);
    }

    /**
     *  fetch NSNumber <= value
     */
    fr.predicate = [NSPredicate predicateWithFormat:@"i64 <= %u", max / 2];

    results = [moc executeFetchRequest:fr error:&err];
    XCTAssertNotNil(results, @"Expected results: %@", err);

    XCTAssertTrue([results count] == ((max / 2) + 1), @"results count should be %d is %@",
                  (max / 2) + 1, @([results count]));

    for (Entry *e in results) {
        long long val = [e.i64 longLongValue];
        XCTAssertTrue(val <= (max / 2), @"entry.i64 should be <= %d, is %lld", max / 2, val);
    }

    /**
     *  fetch NSNumber >= value
     */
    fr.predicate = [NSPredicate predicateWithFormat:@"i64 >= %u", max / 2];

    results = [moc executeFetchRequest:fr error:&err];
    XCTAssertNotNil(results, @"Expected results: %@", err);

    XCTAssertTrue([results count] == (max / 2), @"results count should be %d is %@", max / 2,
                  @([results count]));

    for (Entry *e in results) {
        long long val = [e.i64 longLongValue];
        XCTAssertTrue(val >= (max / 2), @"entry.i64 should be >= %d, is %lld", max / 2, val);
    }

    /**
     *  fetch NSNumber < value
     */
    fr.predicate = [NSPredicate predicateWithFormat:@"i64 < %u", max / 2];

    results = [moc executeFetchRequest:fr error:&err];
    XCTAssertNotNil(results, @"Expected results: %@", err);

    XCTAssertTrue([results count] == ((max / 2)), @"results count should be %d is %@", (max / 2),
                  @([results count]));

    for (Entry *e in results) {
        long long val = [e.i64 longLongValue];
        XCTAssertTrue(val < (max / 2), @"entry.i64 should be < %d, is %lld", max / 2, val);
    }

    /**
     *  fetch NSString == value
     */
    fr.predicate = [NSPredicate predicateWithFormat:@"text == %@", textvals[0]];

    results = [moc executeFetchRequest:fr error:&err];
    XCTAssertNotNil(results, @"Expected results: %@", err);

    XCTAssertTrue([results count] == (max / 4), @"results count should be %d is %@", (max / 4),
                  @([results count]));

    for (Entry *e in results) {
        XCTAssertTrue([e.text isEqualToString:textvals[0]], @"entry.text should be %@ is %@",
                      textvals[0], e.text);
    }

    /**
     *  fetch NSString != value
     */
    fr.predicate = [NSPredicate predicateWithFormat:@"text != %@", textvals[1]];

    results = [moc executeFetchRequest:fr error:&err];
    XCTAssertNotNil(results, @"Expected results: %@", err);

    XCTAssertTrue([results count] == 3 * (max / 4), @"results count should be %d is %@",
                  3 * (max / 4), @([results count]));

    for (Entry *e in results) {
        XCTAssertTrue(![e.text isEqualToString:textvals[1]], @"entry.text should not be %@ is %@",
                      textvals[1], e.text);
    }

    /**
     *  fetch a specific object
     */
    fr.predicate =
    [NSPredicate predicateWithFormat:@"(SELF = %@)", ((Entry *)entries[max / 2]).objectID];

    results = [moc executeFetchRequest:fr error:&err];
    XCTAssertNotNil(results, @"Expected results: %@", err);

    XCTAssertTrue([results count] == 1, @"results count is %ld but should be %ld", (unsigned long)[results count],
                  (long)1);

    /**
     *  fetch NSNumber between lower and upper bound
     */
    int start = max / 4;
    int end = (max * 3) / 4;
    fr.predicate = [NSPredicate predicateWithFormat:@"i64 between { %u, %u }", start, end];

    results = [moc executeFetchRequest:fr error:&err];
    XCTAssertNotNil(results, @"Expected results: %@", err);

    XCTAssertTrue([results count] == (max / 2) + 1, @"results count should be %d is %@", max / 2,
                  @([results count]));

    for (Entry *e in results) {
        long long val = [e.i64 longLongValue];
        XCTAssertTrue(val >= start && val <= end, @"entry.i64 should be between [%d, %d] is %lld",
                      start, end, val);
    }

    /**
     *  fetch NSNumber in array
     */
    NSComparisonPredicate *cp;
    NSExpression *lhs;
    NSExpression *rhs;

    // make a set of random numbers in set
    NSMutableSet *nums = [NSMutableSet set];
    for (int i = 0; i < max / 4; i++) {
        uint32_t r = arc4random();
        r %= max;
        [nums addObject:@(r)];
    }
    NSUInteger count = [nums count];
    // add one that is not there for dun
    [nums addObject:@(max)];

    lhs = [NSExpression expressionForKeyPath:@"i64"];
    rhs = [NSExpression expressionForConstantValue:[nums allObjects]];
    cp = [NSComparisonPredicate predicateWithLeftExpression:lhs
                                            rightExpression:rhs
                                                   modifier:NSDirectPredicateModifier
                                                       type:NSInPredicateOperatorType
                                                    options:0];
    fr.predicate = cp;
    results = [moc executeFetchRequest:fr error:&err];
    XCTAssertNotNil(results, @"Expected results: %@", err);

    XCTAssertTrue([results count] == count, @"results count should be %@ is %@", @(count),
                  @([results count]));

    for (Entry *e in results) {
        XCTAssertTrue([nums containsObject:e.i64], @"entry.i64: %@ should be in set", e.i64);
    }

    /**
     *  fetch objects from a list of objects
     */
    // we will borrow the results from the test above
    NSMutableSet *ids = [NSMutableSet set];
    for (Entry *e in results) {
        // NSManagedObjectID *moid = e.objectID;
        // NSURL *uri = [moid URIRepresentation];
        // NSString *s = [uri absoluteString];
        [ids addObject:e.objectID];
    }

    lhs = [NSExpression expressionForEvaluatedObject];
    rhs = [NSExpression expressionForConstantValue:[ids allObjects]];
    cp = [NSComparisonPredicate predicateWithLeftExpression:lhs
                                            rightExpression:rhs
                                                   modifier:NSDirectPredicateModifier
                                                       type:NSInPredicateOperatorType
                                                    options:0];
    fr.predicate = cp;
    results = [moc executeFetchRequest:fr error:&err];
    XCTAssertNotNil(results, @"Expected results: %@", err);

    XCTAssertTrue([results count] == count, @"results count should be %@ is %@", @(count),
                  @([results count]));

    for (Entry *e in results) {
        XCTAssertTrue([nums containsObject:e.i64], @"entry.i64: %@ should be in set", e.i64);
    }

    /**
     *  Predicate for String CONTAINS
     */
    fr.predicate = [NSPredicate predicateWithFormat:@"Any text CONTAINS[cd] %@", @"0"];

    if (sql) {
        results = [moc executeFetchRequest:fr error:&err];
        XCTAssertNotNil(results, @"Expected results: %@", err);
    } else {
        // No support for substring "in" predicate
        XCTAssertThrowsSpecificNamed([moc executeFetchRequest:fr error:&err], NSException,
                                     CDTISException, @"Expected Exception");
    }

    /**
     *  Compound Predicates
     */

    /**
     *  fetch both with or
     */
    fr.predicate = [NSPredicate predicateWithFormat:@"check == NO || check == YES"];

    results = [moc executeFetchRequest:fr error:&err];
    XCTAssertNotNil(results, @"Expected results: %@", err);

    XCTAssertTrue([results count] == max, @"results count should be %d is %@", max,
                  @([results count]));

    /**
     *  Fetch none with AND, yes I know this is nonsense
     */
    fr.predicate = [NSPredicate predicateWithFormat:@"check == NO && check == YES"];

    results = [moc executeFetchRequest:fr error:&err];
    XCTAssertNotNil(results, @"Expected results: %@", err);

    XCTAssertTrue([results count] == 0, @"results count should be %d is %@", 0, @([results count]));

    /**
     *  Fetch with NOT
     */
    fr.predicate = [NSPredicate predicateWithFormat:@"!(text == %@)", textvals[1]];

    if (sql) {
        results = [moc executeFetchRequest:fr error:&err];
        XCTAssertNotNil(results, @"Expected results: %@", err);
    } else {
        XCTAssertThrowsSpecificNamed([moc executeFetchRequest:fr error:&err], NSException,
                                     CDTISException, @"Expected Exception");
    }

    /**
     *  Special cases
     */

    /**
     *  test predicates with Floats see if NaN shows up
     */
    fr.predicate = [NSPredicate predicateWithFormat:@"fpFloat <= %f", M_PI * 2];

    results = [moc executeFetchRequest:fr error:&err];
    XCTAssertNotNil(results, @"Expected results: %@", err);

    XCTAssertTrue([results count] == 3, @"results count should be %d is %@", 3, @([results count]));

    // make one of them NaN
    Entry *nan = [results firstObject];
    nan.fpFloat = @((float)NAN);

    // push it out
    XCTAssertTrue([moc save:&err], @"Save Failed: %@", err);
    results = [moc executeFetchRequest:fr error:&err];
    XCTAssertNotNil(results, @"Expected results: %@", err);

    XCTAssertTrue([results count] == 2, @"results count should be %d is %@", 2, @([results count]));

    /**
     *  test predicateWithaValue style predicates
     */
    fr.predicate = [NSPredicate predicateWithValue:YES];

    results = [moc executeFetchRequest:fr error:&err];
    XCTAssertNotNil(results, @"Expected results: %@", err);

    expected = [entries filteredArrayUsingPredicate:fr.predicate];

    XCTAssertTrue([results count] == [expected count], @"results count is %ld but should be %ld",
                  (unsigned long)[results count], (unsigned long)[expected count]);

    check = [results filteredArrayUsingPredicate:fr.predicate];

    /**
     * test predicate with FALSEPREDICATE
     */
    fr.predicate = [NSCompoundPredicate orPredicateWithSubpredicates:@[
                                                                       [NSPredicate predicateWithValue:NO],
                                                                       [NSPredicate predicateWithFormat:@"i64 < %u", max / 2]
                                                                       ]];

    results = [moc executeFetchRequest:fr error:&err];
    XCTAssertNotNil(results, @"Expected results: %@", err);

    expected = [entries filteredArrayUsingPredicate:fr.predicate];

    XCTAssertTrue([results count] == [expected count], @"results count is %ld but should be %ld",
                  (unsigned long)[results count], (unsigned long)[expected count]);

    check = [results filteredArrayUsingPredicate:fr.predicate];

    XCTAssertTrue([check count] == [results count],
                  @"results array contains entries that do not satisfy predicate");

    /**
     *  Error cases
     */

    fr.predicate = (NSPredicate *)@"foobar";

    XCTAssertThrows([moc executeFetchRequest:fr error:&err], @"Expected Exception");

    /**
     *  predicate names a field not present in the entity
     */
    fr.predicate = [NSPredicate predicateWithFormat:@"foobar <= %f", M_PI * 2];
    
    if (sql) {
        XCTAssertThrowsSpecificNamed([moc executeFetchRequest:fr error:&err], NSException,
                                     NSInvalidArgumentException, @"Expected Exception");
    } else {
        // CDTIS behavior for this case differs from CoreData, because the keys in the predicate
        // are not validated but simply passed into the query
        results = [moc executeFetchRequest:fr error:&err];
        XCTAssertNotNil(results, @"Expected results: %@", err);
    }
}

@end
