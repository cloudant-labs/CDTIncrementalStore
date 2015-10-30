//
//  Remote.h
//  CDTIncrementalStoreTest
//
//  Created by Jimi Xenidis on 5/20/15.
//
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import <XCTest/XCTest.h>

#import <CDTIncrementalStore.h>

#import <UNIRest.h>


@class Stuff;

@interface RemoteTestCase : XCTestCase

@property (nonatomic, strong) NSManagedObjectModel *managedObjectModel;
@property (nonatomic, strong) NSManagedObjectModel *fromMom;
@property (nonatomic, strong) NSManagedObjectContext *managedObjectContext;
@property (nonatomic, strong) NSPersistentStoreCoordinator *persistentStoreCoordinator;
@property (nonatomic, strong) NSURL *storeURL;
@property (nonatomic, strong) NSURL *localDir;
@property (nonatomic, strong) NSURL *fromURL;
@property (nonatomic, strong) NSString *primaryRemoteDatabaseName;
@property (nonatomic, strong) NSMutableArray *secondaryRemoteDatabaseNames;
@property (nonatomic, strong) NSString *fromCDE;
@property (nonatomic, strong) NSString *toCDE;
@property (nonatomic, strong) NSMappingModel *mapper;
@property (nonatomic, strong) NSURL *primaryRemoteDatabaseURL;
@property (nonatomic, strong) NSURL *remoteRootURL;
@property (nonatomic, strong) NSString *remoteDbPrefix;


- (void)createRemoteDatabase:(NSString*)name instanceURL:(NSURL*)instanceURL;
- (void)deleteRemoteDatabase:(NSString*)name instanceURL:(NSURL*)instanceURL;
- (NSURL *)createSecondaryDatabase:(NSString *)append;

- (void)removeLocalDatabase;

- (NSManagedObjectContext *)createNumbersAndSave:(int)max withConflictID:(int)conflict;
- (NSManagedObjectContext *)createNumbersAndSave:(int)max;
- (NSManagedObjectContext *)createNumbersWithImagesAndSave:(int)max;

- (CDTISReplicator *)pushToURL:(NSURL *)url;
- (CDTISReplicator *)pushMe;
- (CDTISReplicator *)pullFromURL:(NSURL *)url;
- (CDTISReplicator *)pullMe;


void setConflicts(NSArray *results, int conflictVal);

@end

@interface REntry : NSManagedObject
@property (nonatomic, strong) NSNumber *number;
@property (nonatomic, strong) NSString *string;
@property (nonatomic, strong) NSDate *created;
@property (nonatomic, strong) NSSet *stuff;
@property (nonatomic, strong) NSNumber *conflict;
@property (nonatomic, strong) NSManagedObject *image;
@end

@interface REntry (CoreDataGeneratedAccessors)

- (void)addStuffObject:(Stuff *)value;
- (void)removeStuffObject:(Stuff *)value;
- (void)addStuff:(NSSet *)values;
- (void)removeStuff:(NSSet *)values;

@end

REntry *MakeREntry(NSManagedObjectContext *moc);

@interface Stuff : NSManagedObject
@property (nonatomic, retain) NSNumber *size;
@property (nonatomic, retain) NSString *data;
@property (nonatomic, retain) REntry *rentry;
@end

@interface ImageToDataTransformer : NSValueTransformer
@end
