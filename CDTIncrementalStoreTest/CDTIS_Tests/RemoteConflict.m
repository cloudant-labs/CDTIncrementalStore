//
//  RemoteConflict.m
//  CDTIncrementalStoreTest
//
//  Created by Jimi Xenidis on 5/20/15.
//
//

#import <XCTest/XCTest.h>
#import <Foundation/Foundation.h>

#import "Remote.h"

@interface RemoteConflict : RemoteTestCase

@end


@implementation RemoteConflict

- (NSArray *)doConflictWithReplicator:(CDTISReplicator *)replicator
                              context:(NSManagedObjectContext *)moc
                                error:(NSError **)error
{
    return [replicator processConflictsWithContext:moc error:error];
}

- (NSManagedObjectContext *)newStoreFromURL:(NSURL *)url expectedCount:(int)docs
{
    /**
     *  kill local
     */
    [self removeLocalDatabase];

    /**
     *  New local
     */
    NSManagedObjectContext *moc = self.managedObjectContext;
    XCTAssertNotNil(moc, @"could not create Context");

    /**
     *  Pull in from the original Database
     */
    CDTISReplicator *puller = [self pullFromURL:url];
    NSUInteger count = puller.replicator.changesTotal;
    XCTAssertTrue(count == docs, @"pull original: unexpected processed objects: %@ != %d", @(count),
                  docs);

    /**
     * Check for conflicts
     */
    NSError *err = nil;
    NSArray *conflicts = [self doConflictWithReplicator:puller context:moc error:&err];
    XCTAssertNil(err, @"processConflicts failed with error: %@", err);
    count = [conflicts count];
    XCTAssertTrue(count == 0, @"Unexpected number of conflicts: %@ != 0", @(count));

    return moc;
}

/**
 *  This sets up two remotes:
 *  1. Primary: The test default which we will use to create conflicts
 *  2. Original: This remote will be pulled in to create a clean base
 *
 *  @param max number of entries
 */
- (NSURL *)setupConflictBaseWithEntries:(int)max
{
    NSError *err = nil;

    // Make an original set
    NSManagedObjectContext *moc = [self createNumbersAndSave:max];

    int docs = max + 1;

    // Push it to the primary remote DB
    CDTISReplicator *pusher = [self pushMe];
    NSInteger count = pusher.replicator.changesTotal;
    XCTAssertTrue(count == docs, @"push primary: unexpected processed objects: %@ != %d", @(count),
                  docs);

    // Push it to a secondary remote DB, we will treat this as an "original" copy
    NSURL *originalURL = [self createSecondaryDatabase:@"-original"];
    pusher = [self pushToURL:originalURL];
    count = pusher.replicator.changesTotal;
    XCTAssertTrue(count == docs, @"push original: unexpected processed objects: %@ != %d", @(count),
                  docs);

    NSFetchRequest *fr = [NSFetchRequest fetchRequestWithEntityName:@"REntry"];
    fr.shouldRefreshRefetchedObjects = YES;

    /**
     *  fetch original content
     */
    NSArray *results = [moc executeFetchRequest:fr error:&err];
    XCTAssertNotNil(results, @"Expected results: %@", err);
    count = [results count];
    XCTAssertTrue(count == max, @"fetch: unexpected processed objects: %@ != %d", @(count), max);

    /**
     *  Modify the content by updating the creation date as well the conlict field
     */
    setConflicts(results, 1);

    XCTAssertTrue([moc save:&err], @"MOC save failed");
    XCTAssertNil(err, @"MOC save failed with error: %@", err);

    /**
     *  Push updated data to primary DB so it will conflict with original
     */
    pusher = [self pushMe];
    count = pusher.replicator.changesTotal;
    XCTAssertTrue(count == max, @"push primary: unexpected processed objects: %@ != %d", @(count),
                  max);

    [self removeLocalDatabase];
    return originalURL;
}

/**
 *  Detect conflicts from store
 */
- (void)testConflictsFromDataStore
{
    int max = 10;
    NSError *err = nil;

    NSURL *originalURL = [self setupConflictBaseWithEntries:max];

    // there is actually `max` docs plus the metadata document
    int docs = max + 1;

    // New Local DB
    NSManagedObjectContext *moc = self.managedObjectContext;
    XCTAssertNotNil(moc, @"could not create Context");

    // Pull the original content
    CDTISReplicator *puller = [self pullFromURL:originalURL];
    NSInteger count = puller.replicator.changesTotal;
    XCTAssertTrue(count == docs, @"pull original: unexpected processed objects: %@ != %d", @(count),
                  docs);

    NSArray *results;
    NSArray *conflicts;

    /**
     * Check for conflicts
     */
    err = nil;
    conflicts = [self doConflictWithReplicator:puller context:moc error:&err];
    XCTAssertNil(err, @"processConflicts failed with error: %@", err);
    count = [conflicts count];
    XCTAssertTrue(count == 0, @"Unexpected number of conflicts: %@ != 0", @(count));

    moc = [self newStoreFromURL:originalURL expectedCount:docs];

    NSFetchRequest *fr = [NSFetchRequest fetchRequestWithEntityName:@"REntry"];
    fr.shouldRefreshRefetchedObjects = YES;

    /**
     *  fetch original context
     */
    results = [moc executeFetchRequest:fr error:&err];
    XCTAssertNotNil(results, @"Expected results: %@", err);
    count = [results count];
    XCTAssertTrue(count == max, @"fetch: unexpected processed objects: %@ != %d", @(count), max);

    /**
     *  modify again, this time make the conflict val 2
     */
    setConflicts(results, 2);

    XCTAssertTrue([moc save:&err], @"MOC save failed");
    XCTAssertNil(err, @"MOC save failed with error: %@", err);

    /**
     *  pull in the primary that is full of conflict=1 into our conflict=2 data
     */
    puller = [self pullMe];
    count = puller.replicator.changesTotal;
    XCTAssertTrue(count == max, @"pull primary: unexpected processed objects: %@ != %d", @(count),
                  max);
    /**
     *  Check for the right number of conflicts
     */
    err = nil;
    conflicts = [self doConflictWithReplicator:puller context:moc error:&err];
    XCTAssertNil(err, @"processConflicts failed with error: %@", err);
    count = [conflicts count];
    XCTAssertTrue(count == max, @"Unexpected number of conflicts: %@ != %d", @(count), max);

    NSMergePolicy *mp =
    [[NSMergePolicy alloc] initWithMergeType:NSMergeByPropertyStoreTrumpMergePolicyType];
    XCTAssertTrue([mp resolveConflicts:conflicts error:&err], @"resolveConflict Failed");
    XCTAssertNil(err, @"resolveConflicts failed with error: %@", err);

    results = [moc executeFetchRequest:fr error:&err];
    XCTAssertNotNil(results, @"Expected results: %@", err);
    count = [results count];
    XCTAssertTrue(count == max, @"fetch: unexpected processed objects: %@ != %d", @(count), max);

    /**
     *  we should revert back to the conflict=1 entries
     */
    for (REntry *e in results) {
        int n = [e.conflict intValue];
        XCTAssertTrue(n == 1, @"unexpected result: %d != 1\n", n);
    }

    XCTAssertTrue([moc save:&err], @"MOC save failed");
    XCTAssertNil(err, @"MOC save failed with error: %@", err);
}

/**
 *  Detect Conflicts from save
 */
- (void)testConflictsFromSave
{
    int max = 10;
    NSError *err = nil;

    NSURL *originalURL = [self setupConflictBaseWithEntries:max];

    // there is actually `max` docs plus the metadata document
    int docs = max + 1;

    // New Local DB
    NSManagedObjectContext *moc = self.managedObjectContext;
    XCTAssertNotNil(moc, @"could not create Context");

    NSArray *results;
    NSArray *conflicts;
    NSInteger count;

    NSFetchRequest *fr = [NSFetchRequest fetchRequestWithEntityName:@"REntry"];
    fr.shouldRefreshRefetchedObjects = YES;

    /**
     *  detect conflict on save
     */
    moc = [self newStoreFromURL:originalURL expectedCount:docs];
    results = [moc executeFetchRequest:fr error:&err];
    XCTAssertNotNil(results, @"Expected results: %@", err);
    count = [results count];
    XCTAssertTrue(count == max, @"fetch: unexpected processed objects: %@ != %d", @(count), max);

    /**
     *  modify again, to 3
     */
    setConflicts(results, 3);

    /**
     *  Do not save yet, first pull in the primary
     */
    CDTISReplicator *puller = [self pullMe];
    count = puller.replicator.changesTotal;
    XCTAssertTrue(count == max, @"pull primary: unexpected processed objects: %@ != %d", @(count),
                  max);

    /**
     *  Now save
     */
    BOOL rc = [moc save:&err];
    XCTAssertFalse(rc, @"MOC save should have failed");
    XCTAssertNotNil(err, @"MOC save should have failed with error: %@", err);
    if (rc) {
        XCTFail(@"Aborting remainder of test");
        return;
    }

    // we should probably copy since we destroy or resue the error pretty soon
    conflicts = [err.userInfo[NSPersistentStoreSaveConflictsErrorKey] copy];
    XCTAssertNotNil(conflicts, @"no mergeConflicts");
    count = [conflicts count];
    XCTAssertTrue(count == max, @"Unexpected number of conflicts: %@ != %d", @(count), max);
    err = nil;

    NSMergePolicy *mp =
    [[NSMergePolicy alloc] initWithMergeType:NSMergeByPropertyObjectTrumpMergePolicyType];
    rc = [mp resolveConflicts:conflicts error:&err];
    XCTAssertTrue(rc, @"resolveConflict Failed");
    XCTAssertNil(err, @"resolveConflicts failed with error: %@", err);

    rc = [moc save:&err];
    XCTAssertTrue(rc, @"MOC save should have passed");

    results = [moc executeFetchRequest:fr error:&err];
    XCTAssertNotNil(results, @"Expected results: %@", err);
    count = [results count];
    XCTAssertTrue(count == max, @"fetch: unexpected processed objects: %@ != %d", @(count), max);

    /**
     *  we should revert now have 3
     */
    for (REntry *e in results) {
        int n = [e.conflict intValue];
        XCTAssertTrue(n = 3, @"unexpected result: %d != 3\n", n);
    }
}

@end
