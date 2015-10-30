//
//  RemotePushPull.m
//  CDTIncrementalStoreTest
//
//  Created by Jimi Xenidis on 5/20/15.
//
//

#import <XCTest/XCTest.h>
#import <Foundation/Foundation.h>

#import "Remote.h"

@interface RemotePushPull : RemoteTestCase

@end


@implementation RemotePushPull

- (void)testPushPull
{
    int max = 100;
    NSError *err = nil;

    NSManagedObjectContext *moc = [self createNumbersAndSave:max];

    // there is actually `max` docs plus the metadata document
    int docs = max + 1;

    /**
     *  Push
     */
    CDTISReplicator *pusher = [self pushMe];
    NSInteger count = pusher.replicator.changesTotal;
    XCTAssertTrue(count == docs, @"push: unexpected processed objects: %@ != %d", @(count), docs);

    [self removeLocalDatabase];

    /**
     *  Out of band tally of the number of documents in the remote replicant
     */
    NSString *all_docs =
    [NSString stringWithFormat:@"%@/_all_docs?limit=0", [self.storeURL absoluteString]];
    UNIHTTPRequest *req = [UNIRest get:^(UNISimpleRequest *request) {
        [request setUrl:all_docs];
    }];
    UNIHTTPJsonResponse *json = [req asJson];
    UNIJsonNode *body = json.body;
    NSDictionary *dic = body.object;
    NSNumber *total_rows = dic[@"total_rows"];
    count = [total_rows integerValue];
    XCTAssertTrue(count == docs, @"oob: unexpected number of objects: %@ != %d", @(count), docs);

    /**
     *  New context for pull
     */
    moc = self.managedObjectContext;
    XCTAssertNotNil(moc, @"could not create Context");

    CDTISReplicator *puller = [self pullMe];
    count = puller.replicator.changesTotal;
    XCTAssertTrue(count == docs, @"pull: unexpected processed objects: %@ != %d", @(count), docs);

    /**
     *  Read it back
     */
    NSArray *results;
    NSSortDescriptor *sd = [NSSortDescriptor sortDescriptorWithKey:@"number" ascending:YES];

    NSFetchRequest *fr = [NSFetchRequest fetchRequestWithEntityName:@"REntry"];
    fr.shouldRefreshRefetchedObjects = YES;
    fr.sortDescriptors = @[ sd ];

    results = [moc executeFetchRequest:fr error:&err];
    XCTAssertNotNil(results, @"Expected results: %@", err);
    count = [results count];
    XCTAssertTrue(count == max, @"fetch: unexpected processed objects: %@ != %d", @(count), max);

    long long last = -1;
    for (REntry *e in results) {
        long long val = [e.number longLongValue];
        XCTAssertTrue(val < max, @"entry is out of range [0, %d): %lld", max, val);
        XCTAssertTrue(val == last + 1, @"unexpected entry %@: %@", @(val), e);
        ++last;
    }
}

- (void)testDuplication
{
    int max = 100;
    NSError *err = nil;

    NSManagedObjectContext *moc = [self createNumbersAndSave:max];

    // there is actually `max` docs plus the metadata document
    int docs = max + 1;

    // push
    CDTISReplicator *pusher = [self pushMe];
    NSInteger count = pusher.replicator.changesTotal;
    XCTAssertTrue(count == docs, @"push: unexpected processed objects: %@ != %d", @(count), docs);

    [self removeLocalDatabase];

    // make another core data set with the exact same series
    moc = [self createNumbersAndSave:max];

    // now pull
    CDTISReplicator *puller = [self pullMe];
    count = puller.replicator.changesTotal;
    XCTAssertTrue(count == docs, @"pull: unexpected processed objects: %@ != %d", @(count), docs);

    // Read it back
    NSArray *results;
    NSSortDescriptor *sd = [NSSortDescriptor sortDescriptorWithKey:@"number" ascending:YES];

    NSFetchRequest *fr = [NSFetchRequest fetchRequestWithEntityName:@"REntry"];
    fr.shouldRefreshRefetchedObjects = YES;
    fr.sortDescriptors = @[ sd ];

    results = [moc executeFetchRequest:fr error:&err];
    XCTAssertNotNil(results, @"Expected results: %@", err);
    count = [results count];
    XCTAssertTrue(count == max * 2, @"fetch: unexpected processed objects: %@ != %d", @(count),
                  max * 2);

    // Find dupes
    // see:
    // https://developer.apple.com/library/ios/documentation/DataManagement/Conceptual/UsingCoreDataWithiCloudPG/UsingSQLiteStoragewithiCloud/UsingSQLiteStoragewithiCloud.html#//apple_ref/doc/uid/TP40013491-CH3-SW8

    /**
     *  1. Choose a property or a hash of multiple properties to use as a
     *     unique ID for each record.
     */
    NSString *uniquePropertyKey = @"number";
    NSExpression *countExpression =
    [NSExpression expressionWithFormat:@"count:(%@)", uniquePropertyKey];
    NSExpressionDescription *countExpressionDescription = [[NSExpressionDescription alloc] init];
    [countExpressionDescription setName:@"count"];
    [countExpressionDescription setExpression:countExpression];
    [countExpressionDescription setExpressionResultType:NSInteger64AttributeType];
    NSManagedObjectContext *context = moc;
    NSEntityDescription *entity =
    [NSEntityDescription entityForName:@"REntry" inManagedObjectContext:context];
    NSAttributeDescription *uniqueAttribute =
    [[entity attributesByName] objectForKey:uniquePropertyKey];

    /**
     *  2. Fetch the number of times each unique value appears in the store.
     *     The context returns an array of dictionaries, each containing
     *     a unique value and the number of times that value appeared in
     *     the store.
     */
    NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"REntry"];
    [fetchRequest setPropertiesToFetch:@[ uniqueAttribute, countExpressionDescription ]];
    [fetchRequest setPropertiesToGroupBy:@[ uniqueAttribute ]];
    [fetchRequest setResultType:NSDictionaryResultType];
    NSArray *fetchedDictionaries = [moc executeFetchRequest:fetchRequest error:&err];

    // check
    XCTAssertNotNil(fetchedDictionaries, @"fetch request failed: %@", err);
    count = [fetchedDictionaries count];
    XCTAssertTrue(count == max, @"fetch: unexpected processed objects: %@ != %d", @(count), max);

    /**
     *  3. Filter out unique values that have no duplicates.
     */
    NSMutableArray *valuesWithDupes = [NSMutableArray array];
    for (NSDictionary *dict in fetchedDictionaries) {
        NSNumber *count = dict[@"count"];
        if ([count integerValue] > 1) {
            [valuesWithDupes addObject:dict[@"number"]];
        }
    }

    /**
     *  4. Use a predicate to fetch all of the records with duplicates.
     *     Use a sort descriptor to properly order the results for the
     *     winner algorithm in the next step.
     */
    NSFetchRequest *dupeFetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"REntry"];
    [dupeFetchRequest setIncludesPendingChanges:NO];
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"number IN (%@)", valuesWithDupes];
    [dupeFetchRequest setPredicate:predicate];

    sd = [NSSortDescriptor sortDescriptorWithKey:@"number" ascending:YES];
    [dupeFetchRequest setSortDescriptors:@[ sd ]];
    NSArray *dupes = [moc executeFetchRequest:dupeFetchRequest error:&err];

    // check
    XCTAssertNotNil(dupes, @"fetch request failed: %@", err);
    count = [dupes count];
    XCTAssertTrue(count == max * 2, @"fetch: unexpected processed objects: %@ != %d", @(count),
                  max * 2);

    /**
     *  5. Choose the winner.
     *     After retrieving all of the duplicates, your app decides which
     *     ones to keep. This decision must be deterministic, meaning that
     *     every peer should always choose the same winner. Among other
     *     methods, your app could store a created or last-changed timestamp
     *     for each record and then decide based on that.
     */
    NSUInteger dels = 0;
    NSUInteger nots = 0;
    REntry *prevObject;
    for (REntry *duplicate in dupes) {
        if (prevObject) {
            if ([duplicate.number isEqualToNumber:prevObject.number]) {
                if ([duplicate.created compare:prevObject.created] == NSOrderedAscending) {
                    [moc deleteObject:duplicate];
                    ++dels;
                } else {
                    [moc deleteObject:prevObject];
                    prevObject = duplicate;
                    ++dels;
                }
            } else {
                prevObject = duplicate;
                ++nots;
            }
        } else {
            prevObject = duplicate;
        }
    }
    /**
     *  Remember to set a batch size on the fetch and whenever you reach
     *  the end of a batch, save the context.
     */
    XCTAssertTrue([moc save:&err], @"MOC save failed");
    XCTAssertNil(err, @"MOC save failed with error: %@", err);

    // read it back with a new object model
    moc = self.managedObjectContext;

    results = [moc executeFetchRequest:fr error:&err];
    XCTAssertNotNil(results, @"Expected results: %@", err);
    count = [results count];
    XCTAssertTrue(count == max, @"fetch: unexpected processed objects: %@ != %d", @(count), max);

    pusher = [self pushMe];
    count = pusher.replicator.changesTotal;
    XCTAssertTrue(count == docs + max, @"push: unexpected processed objects: %@ != %d", @(count),
                  docs + max);
}

- (void)testMigration
{
    int max = 10;
    NSError *err = nil;

    // force v1.0
    self.fromCDE = nil;
    self.toCDE = @"RemoteV1.0.mom";

    NSManagedObjectContext *moc = [self createNumbersAndSave:max];

    // save it
    XCTAssertTrue([moc save:&err], @"MOC save failed");
    XCTAssertNil(err, @"MOC save failed with error: %@", err);

    /**
     *  Read it back
     */
    NSArray *results;

    NSFetchRequest *fr = [NSFetchRequest fetchRequestWithEntityName:@"REntry"];
    fr.shouldRefreshRefetchedObjects = YES;

    results = [moc executeFetchRequest:fr error:&err];
    XCTAssertNotNil(results, @"Expected results: %@", err);
    NSInteger count = [results count];
    XCTAssertTrue(count == max, @"fetch: unexpected processed objects: %@ != %d", @(count), max);

    NSManagedObject *mo = [results firstObject];
    XCTAssertNotNil([mo valueForKey:@"number"]);
    XCTAssertThrows([mo valueForKey:@"checkit"]);

    // drop the store, I think I'm leaking here
    moc = nil;
    self.managedObjectModel = nil;
    self.managedObjectContext = nil;
    self.persistentStoreCoordinator = nil;

    // force v1.1
    self.fromCDE = self.toCDE;
    self.toCDE = @"RemoteV1.1.mom";

    // bring it back with this object model
    moc = self.managedObjectContext;

    // Reload the fetch request becauses it caches info from the old model
    fr = [NSFetchRequest fetchRequestWithEntityName:@"REntry"];
    fr.shouldRefreshRefetchedObjects = YES;

    results = [moc executeFetchRequest:fr error:&err];
    XCTAssertNotNil(results, @"Expected results: %@", err);
    count = [results count];
    XCTAssertTrue(count == max, @"fetch: unexpected processed objects: %@ != %d", @(count), max);

    mo = [results firstObject];
    XCTAssertNotNil([mo valueForKey:@"number"]);
    XCTAssertNoThrow([mo valueForKey:@"checkit"]);
}

- (void)testPushPullAttachments
{
	int max = 10;
	NSError *err = nil;

	NSManagedObjectContext *moc = [self createNumbersWithImagesAndSave:max];

	// there is actually `max` docs plus the metadata document
	int docs = 2*max + 1;

	/**
	 *  Push
	 */
	CDTISReplicator *pusher = [self pushMe];
	NSInteger count = pusher.replicator.changesTotal;
	XCTAssertTrue(count == docs, @"push: unexpected processed objects: %@ != %d", @(count), docs);

	[self removeLocalDatabase];

	/**
	 *  Out of band tally of the number of documents in the remote replicant
	 */
	NSString *all_docs =
	[NSString stringWithFormat:@"%@/_all_docs?limit=0", [self.storeURL absoluteString]];
	UNIHTTPRequest *req = [UNIRest get:^(UNISimpleRequest *request) {
		[request setUrl:all_docs];
	}];
	UNIHTTPJsonResponse *json = [req asJson];
	UNIJsonNode *body = json.body;
	NSDictionary *dic = body.object;
	NSNumber *total_rows = dic[@"total_rows"];
	count = [total_rows integerValue];
	XCTAssertTrue(count == docs, @"oob: unexpected number of objects: %@ != %d", @(count), docs);

	/**
	 *  New context for pull
	 */
	moc = self.managedObjectContext;
	XCTAssertNotNil(moc, @"could not create Context");

	CDTISReplicator *puller = [self pullMe];
	count = puller.replicator.changesTotal;
	XCTAssertTrue(count == docs, @"pull: unexpected processed objects: %@ != %d", @(count), docs);

	/**
	 *  Read it back
	 */
	NSArray *results;
	NSSortDescriptor *sd = [NSSortDescriptor sortDescriptorWithKey:@"number" ascending:YES];

	NSFetchRequest *fr = [NSFetchRequest fetchRequestWithEntityName:@"REntry"];
	fr.shouldRefreshRefetchedObjects = YES;
	fr.sortDescriptors = @[ sd ];

	results = [moc executeFetchRequest:fr error:&err];
	XCTAssertNotNil(results, @"Expected results: %@", err);
	count = [results count];
	XCTAssertTrue(count == max, @"fetch: unexpected processed objects: %@ != %d", @(count), max);

	long long last = -1;
	for (REntry *e in results) {
		long long val = [e.number longLongValue];
		XCTAssertTrue(val < max, @"entry is out of range [0, %d): %lld", max, val);
		XCTAssertTrue(val == last + 1, @"unexpected entry %@: %@", @(val), e);
		++last;
	}
}


@end
