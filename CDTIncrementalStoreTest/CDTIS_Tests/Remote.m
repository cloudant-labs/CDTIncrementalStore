//
//  Remote.m
//  CDTIncrementalStoreTest
//
//  Created by Jimi Xenidis on 5/20/15.
//
//


#import "Remote.h"

@implementation REntry
@dynamic number, string, created, stuff, conflict, image;
@end

REntry *MakeREntry(NSManagedObjectContext *moc)
{
    return
    [NSEntityDescription insertNewObjectForEntityForName:@"REntry" inManagedObjectContext:moc];
}

@implementation Stuff
@dynamic size, data, rentry;
@end

@implementation ImageToDataTransformer
+ (BOOL)allowsReverseTransformation { return YES; }
+ (Class)transformedValueClass { return [NSData class]; }
- (id)transformedValue:(id)value {
#if TARGET_OS_IPHONE
	NSData *data = UIImageJPEGRepresentation(value, 1 /* least */);
#else
	NSData *data = [value representationUsingType:NSJPEGFileType
										   properties:@{ NSImageCompressionFactor : @(1) /* least */ }];
#endif
	return data;
}
- (id)reverseTransformedValue:(id)value {
#if TARGET_OS_IPHONE
	UIImage *image = [[UIImage alloc] initWithData:value];
#else
	NSImage *image = [[NSImage alloc] initWithData:value];
#endif
	return image;
}
@end

NSString *generateRandomString(int num) {
    NSMutableString* string = [NSMutableString stringWithCapacity:num];
    for (int i = 0; i < num; i++) {
        [string appendFormat:@"%C", (unichar)('a' + arc4random_uniform(25))];
    }
    return string;
}

@implementation RemoteTestCase

-(void)createRemoteDatabase:(NSString*)name
                 instanceURL:(NSURL*)instanceURL
{
    NSURL *remoteDatabaseURL = [instanceURL URLByAppendingPathComponent:name];

    NSDictionary *headers = @{@"accept": @"application/json"};
    UNIHTTPJsonResponse *response = [[UNIRest putEntity:^(UNIBodyRequest *request) {
        [request setUrl:[remoteDatabaseURL absoluteString]];
        [request setHeaders:headers];
        [request setBody:[NSData data]];
    }] asJson];
    XCTAssertNotNil([response.body.object objectForKey:@"ok"], @"Remote db create failed");
}

-(void)deleteRemoteDatabase:(NSString*)name
                 instanceURL:(NSURL*)instanceURL
{
    NSURL *remoteDatabaseURL = [instanceURL URLByAppendingPathComponent:name];

    NSDictionary *headers = @{@"accept": @"application/json"};
    UNIHTTPJsonResponse *response = [[UNIRest delete:^(UNISimpleRequest *request) {
        [request setUrl:[remoteDatabaseURL absoluteString]];
        [request setHeaders:headers];
    }] asJson];
    XCTAssertNotNil([response.body.object objectForKey:@"ok"], @"Remote db delete failed");
}


- (NSManagedObjectModel *)managedObjectModel
{
    if (_managedObjectModel != nil) {
        return _managedObjectModel;
    }

    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSURL *dir = [bundle URLForResource:@"Remote" withExtension:@"momd"];
    XCTAssertNotNil(dir, @"could not find CoreDataEntry resource directory");

    NSURL *toURL;
    if (self.toCDE) {
        toURL = [NSURL URLWithString:self.toCDE relativeToURL:dir];
    } else {
        // take the default defined by the directory
        toURL = dir;
    }
    XCTAssertNotNil(toURL, @"could not find CoreDataEntry model file");

    _managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:toURL];
    XCTAssertTrue(([[_managedObjectModel entities] count] > 0), @"no entities");

    if (self.fromCDE) {
        NSURL *fromURL = [NSURL URLWithString:self.fromCDE relativeToURL:dir];
        self.fromMom = [[NSManagedObjectModel alloc] initWithContentsOfURL:fromURL];
        XCTAssertNotNil(self.fromMom, @"Could not create from model");
    } else {
        self.fromMom = nil;
    }

    return _managedObjectModel;
}

- (NSManagedObjectContext *)managedObjectContext
{
    if (_managedObjectContext != nil) {
        return _managedObjectContext;
    }

    NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
    if (coordinator != nil) {
        _managedObjectContext = [NSManagedObjectContext new];
        [_managedObjectContext setPersistentStoreCoordinator:coordinator];
    }
    return _managedObjectContext;
}

- (NSURL *)createSecondaryDatabase:(NSString *)append
{
    XCTAssertTrue(([append length] > 0), @"append must no be empty");
    if (!self.secondaryRemoteDatabaseNames) {
        self.secondaryRemoteDatabaseNames = [NSMutableArray array];
    }

    NSString *sec = [self.primaryRemoteDatabaseName stringByAppendingString:append];
    NSURL *secURL = [NSURL URLWithString:sec relativeToURL:self.remoteRootURL];
    XCTAssertNotNil(secURL, "Secondary URL evaluated to nil?");

    [self createRemoteDatabase:sec instanceURL:self.remoteRootURL];

    [self.secondaryRemoteDatabaseNames addObject:sec];

    return secURL;
}

- (NSURL *)localDir
{
    if (_localDir) {
        return _localDir;
    }
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *docDir =
    [[fileManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];

    NSURL *localDir = [docDir URLByAppendingPathComponent:@"cdtis_test_databases"];
    NSError *err = nil;
    XCTAssertTrue([fileManager createDirectoryAtURL:localDir
                        withIntermediateDirectories:YES
                                         attributes:nil
                                              error:&err],
                  @"Can't create datastore directory: %@", localDir);
    XCTAssertNil(err, @"Error: %@", err);

    _localDir = localDir;
    return _localDir;
}

- (NSPersistentStoreCoordinator *)persistentStoreCoordinator
{
    if (_persistentStoreCoordinator != nil) {
        return _persistentStoreCoordinator;
    }

    NSManagedObjectModel *toMom = self.managedObjectModel;

    NSString *storeType;
    NSURL *rootURL;

    // quick hack to enable a known store type for testing
    const BOOL sql = NO;
    if (sql) {
        storeType = NSSQLiteStoreType;
        rootURL = self.localDir;
    } else {
        storeType = [CDTIncrementalStore type];
        rootURL = self.remoteRootURL;
    }

    NSError *err = nil;
    NSURL *storeURL;
    NSURL *localURL;
    NSPersistentStore *theStore;

    if (self.fromMom) {
        NSError *err = nil;
        NSMappingModel *mapMom = [NSMappingModel inferredMappingModelForSourceModel:self.fromMom
                                                                   destinationModel:toMom
                                                                              error:&err];
        XCTAssertNotNil(mapMom, @"Failed to create mapping model");
        XCTAssertNil(err, @"Error: %@", err);

        NSURL *fromRemoteURL =
        [NSURL URLWithString:self.primaryRemoteDatabaseName relativeToURL:rootURL];
        NSURL *fromURL = [self.localDir URLByAppendingPathComponent:[fromRemoteURL lastPathComponent]];

        storeURL = [self createSecondaryDatabase:@"-migrate"];

        err = nil;
        NSMigrationManager *mm =
        [[NSMigrationManager alloc] initWithSourceModel:self.fromMom destinationModel:toMom];
        XCTAssertNotNil(mm, @"Failed to create migration manager");

        localURL = [self.localDir URLByAppendingPathComponent:[storeURL lastPathComponent]];

        XCTAssertTrue([mm migrateStoreFromURL:fromURL
                                         type:storeType
                                      options:nil
                             withMappingModel:mapMom
                             toDestinationURL:localURL
                              destinationType:storeType
                           destinationOptions:nil
                                        error:&err],
                      @"migration failed");
        XCTAssertNil(err, @"error: %@", err);
    } else {
        storeURL = [NSURL URLWithString:self.primaryRemoteDatabaseName relativeToURL:rootURL];
        localURL = [self.localDir URLByAppendingPathComponent:[storeURL lastPathComponent]];
    }

    _persistentStoreCoordinator =
    [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:toMom];

    XCTAssertNotNil(_persistentStoreCoordinator, @"Failed to create PSC");

    // Since we perform all versioning manually...
    NSDictionary *options = @{ NSIgnorePersistentStoreVersioningOption : @(YES) };

    theStore = [_persistentStoreCoordinator addPersistentStoreWithType:storeType
                                                         configuration:nil
                                                                   URL:localURL
                                                               options:options
                                                                 error:&err];
    XCTAssertNotNil(theStore, @"could not get theStore: %@", err);

    self.storeURL = storeURL;

    return _persistentStoreCoordinator;
}

- (CDTIncrementalStore *)getIncrementalStore
{
    NSArray *stores = [CDTIncrementalStore storesFromCoordinator:self.persistentStoreCoordinator];
    XCTAssertNotNil(stores, @"could not get stores");
    CDTIncrementalStore *store = [stores firstObject];
    XCTAssertNotNil(store, @"could not get incremental store");

    return store;
}


- (void)setUp
{
    [super setUp];

    self.remoteRootURL = [NSURL URLWithString:@"http://localhost:5984"];
    self.remoteDbPrefix = @"replication-acceptance";

    // Create remote database
    self.primaryRemoteDatabaseName =
    [NSString stringWithFormat:@"%@-test-coredata-database-%@", self.remoteDbPrefix, generateRandomString(5)];

    self.primaryRemoteDatabaseURL =
    [self.remoteRootURL URLByAppendingPathComponent:self.primaryRemoteDatabaseName];

    [self createRemoteDatabase:self.primaryRemoteDatabaseName instanceURL:self.remoteRootURL];
}

- (void)tearDown
{
    self.managedObjectContext = nil;
    self.persistentStoreCoordinator = nil;

    // Delete remote database
    [self deleteRemoteDatabase:self.primaryRemoteDatabaseName instanceURL:self.remoteRootURL];

    for (NSString *dbName in self.secondaryRemoteDatabaseNames) {
        [self deleteRemoteDatabase:dbName instanceURL:self.remoteRootURL];
    }
    [super tearDown];
}

- (NSManagedObjectContext *)createNumbersAndSave:(int)max withConflictID:(int)conflict
{
    NSError *err = nil;
    // This will create the database
    NSManagedObjectContext *moc = self.managedObjectContext;
    XCTAssertNotNil(moc, @"could not create Context");

    // create some entries
    for (int i = 0; i < max; i++) {
        REntry *e = MakeREntry(moc);

        e.number = @(i);
        e.string = [NSString stringWithFormat:@"%u", (max * 10) + i];
        e.created = [NSDate dateWithTimeIntervalSinceNow:0];
        e.conflict = @(conflict);
    }

    // save to backing store
    XCTAssertTrue([moc save:&err], @"MOC save failed");
    XCTAssertNil(err, @"MOC save failed with error: %@", err);

    return moc;
}

- (NSManagedObjectContext *)createNumbersAndSave:(int)max
{
    return [self createNumbersAndSave:max withConflictID:0];
}

- (NSManagedObjectContext *)createNumbersWithImagesAndSave:(int)max
{
	NSError *err = nil;
	// This will create the database
	NSManagedObjectContext *moc = self.managedObjectContext;
	XCTAssertNotNil(moc, @"could not create Context");

	int dataSize = 64 * 1024;

	// create some entries
	for (int i = 0; i < max; i++) {
		REntry *e = MakeREntry(moc);

		e.number = @(i);
		e.string = [NSString stringWithFormat:@"%u", (max * 10) + i];
		e.created = [NSDate dateWithTimeIntervalSinceNow:0];
		e.conflict = @(0);

		// Create an image object for the new image.
		NSManagedObject *imageObj = [NSEntityDescription insertNewObjectForEntityForName:@"Image" inManagedObjectContext:moc];

		NSData *someData = [[NSFileHandle fileHandleForReadingAtPath:@"/dev/random"] readDataOfLength:dataSize];
#if TARGET_OS_IPHONE
		UIImage *anImage = [[UIImage alloc] initWithData:someData];
#else
		NSImage *anImage = [[NSImage alloc] initWithData:someData];
#endif
		[imageObj setValue:anImage forKey:@"image"];
		e.image = imageObj;
	}

	// save to backing store
	XCTAssertTrue([moc save:&err], @"MOC save failed");
	XCTAssertNil(err, @"MOC save failed with error: %@", err);

	return moc;
}

void setConflicts(NSArray *results, int conflictVal)
{
    for (REntry *e in results) {
        e.conflict = @(conflictVal);
        e.created = [NSDate dateWithTimeIntervalSinceNow:0];
    }
}

- (void)removeLocalDatabase
{
    NSError *err = nil;

    /**
     *  blow away the local database
     */
    self.managedObjectContext = nil;
    self.persistentStoreCoordinator = nil;

    NSFileManager *fm = [NSFileManager defaultManager];
    XCTAssertNotNil(fm, @"Could not get File Manager");
    if (![fm removeItemAtURL:self.localDir error:&err]) {
        XCTAssertTrue(err.code != NSFileNoSuchFileError,
                      @"removal of database directory failed: %@", err);
    }
    self.localDir = nil;
}

- (CDTISReplicator *)pushToURL:(NSURL *)url
{
    NSError *err = nil;
    CDTIncrementalStore *myIS = [self getIncrementalStore];
    XCTAssertNotNil(myIS, "Could not get IS Object");
    CDTISReplicator *pusher = [myIS replicatorThatPushesToURL:url withError:&err];

    XCTAssertNotNil(pusher, @"Pusher create faile with: %@", err);

    XCTAssertTrue([pusher.replicator startWithError:&err], @"Push Failed with error: %@", err);
    while (pusher.replicator.isActive) {
        [NSThread sleepForTimeInterval:1.0f];
    }
    return pusher;
}

- (CDTISReplicator *)pushMe { return [self pushToURL:self.primaryRemoteDatabaseURL]; }

- (CDTISReplicator *)pullFromURL:(NSURL *)url
{
    NSError *err = nil;
    CDTIncrementalStore *myIS = [self getIncrementalStore];
    XCTAssertNotNil(myIS, "Could not get IS Object");
    CDTISReplicator *puller = [myIS replicatorThatPullsFromURL:url withError:&err];

    XCTAssertNotNil(puller, @"Puller create failed with: %@", err);

    XCTAssertTrue([puller.replicator startWithError:&err], @"Pull Failed with error: %@", err);
    while (puller.replicator.isActive) {
        [NSThread sleepForTimeInterval:1.0f];
    }
    return puller;
}

- (CDTISReplicator *)pullMe { return [self pullFromURL:self.primaryRemoteDatabaseURL]; }

- (NSArray *)doConflictWithReplicator:(CDTISReplicator *)replicator
                              context:(NSManagedObjectContext *)moc
                                error:(NSError **)error
{
    return [replicator processConflictsWithContext:moc error:error];
}


@end