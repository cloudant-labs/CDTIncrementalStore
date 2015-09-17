//
//  CDTIncrementalStore.h
//  CDTIncrementalStore
//
//  Created by Jimi Xenidis on 11/18/14.
//
//  Copyright (c) 2015 IBM. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//  http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.
//

#import <CoreData/CoreData.h>
#import <CloudantSync.h>

#include <Availability.h>

#import "CDTISReplicator.h"

/**
 * Feature Tests
 */

#if (__MAC_OS_X_VERSION_MAX_ALLOWED >= 101000) || (__IPHONE_OS_VERSION_MAX_ALLOWED >= 80100)

#define HAS_NSAsynchronousFetchRequest 1
#define HAS_NSBatchUpdateRequest 1

#endif

/** The domain for IBMData errors. */
extern NSString *const CDTISErrorDomain;

/** Name of an exception that occurs when CDTIncrementalStore encounters an unexpected condition. */
extern NSString *const CDTISException;

/**
 * CDTIncrementalStore errors
 */
typedef NS_ENUM(NSInteger, CDTIncrementalStoreErrors) {
	/** CDTIncrementalStore encountered an unexpected error. */
	CDTISErrorInternalError = 1,
	/** Cannot create the local datastore at the specified path */
	CDTISErrorBadPath,
	/** Data model contains attribute with undefined type */
	CDTISErrorUndefinedAttributeType,
	/** PersistentStoreRequest has unrecognized request type */
	CDTISErrorRequestTypeUnknown,
	/** PersistentStoreRequest has unrecognized result type */
	CDTISErrorResultTypeUnknown,
	/** PersistentStoreRequest contains unsupported features or operators */
	CDTISErrorRequestNotSupported,
	/** Could not create replication factory for datastore */
	CDTISErrorReplicationFactory,
};

/**
 CDTIncrementalStore is a concrete class that allows an application to use
 CDTDatastore as a Core Data persistent store.

 If your application is not already using Core Data, see the Core Data documentation for the
 proper setup for a persistent store. This generally involves the initialization of a persistent
 store coordinator followed by a request to add a persistent store of a specific type to the
 persistent store coordinator.

 This setup is commonly done in the application delegate, but could be done elsewhere.
 The common persistent store implementation is the NSSQLiteStoreType, which uses SQLite for
 persistent storage. To use CDTDatastore for Core Data persistent storage, specify
 `[CDTIncrementalStore type]` as the persistent store type, as follows:

     #import <CDTIncrementalStore.h>

     NSURL *storeURL = [docsDir URLByAppendingPathComponent:@"mystore"];
     NSPersistentStoreCoordinator *psc = ...
     [psc addPersistentStoreWithType:[CDTIncrementalStore type]
                       configuration:nil
                                 URL:storeURL
                             options:nil
                               error:&error])];

 The pathname of the storeURL may specify a suffix, e.g. ".cdtis", but none is required and
 no significance is given to the suffix. However, to avoid confusion, you should avoid using the
 ".sqlite" suffix since this typically indicates a sqllite datastore.

 At this point you can use Core Data normally and your changes will be saved in the
 local CDTDatastore image.

 ### Replicating to remote Cloudant datastores

 CDTIncrementalStore provides methods to access the replication features of the underlying
 CloudantSync datastore.  The CDTISReplicator class wraps a CDTReplicator of the underlying
 CloudantSync datastore.  Use the `replicatorThatPullsFromURL:withError:` or
 `replicatorThatPushesToURL:withError:` methods to obtain a CDTISReplicator.

 ### Related documentation

 * [Apple Core Data Framework Reference](https://developer.apple.com/library/ios/documentation/Cocoa/Reference/CoreData_ObjC/)
 * [CloudantSync](https://cloudant.com/product/cloudant-features/sync/)
 * [CDTDatastore GitHub repo](https://github.com/cloudant/CDTDatastore)

 */
@interface CDTIncrementalStore : NSIncrementalStore

/** @name Using a CloudantSync IncrementalStore */

/**
 *  Returns a string constant that specifies the store type for a CDTIncrementalStore.
 *
 *  Use this method to obtain the persistent store type for the
 *  addPersistentStoreWithType:configuration:URL:options:error: method of
 *  [NSPersistentStoreCoordinator](https://developer.apple.com/library/ios/documentation/Cocoa/Reference/CoreDataFramework/Classes/NSPersistentStoreCoordinator_Class/).
 *
 *  @return NSString
 */
+ (NSString *)type;

/**
 *  Returns an array of CDTIncrementalStore objects associated with a
 *  [NSPersistentStoreCoordinator](https://developer.apple.com/library/ios/documentation/Cocoa/Reference/CoreDataFramework/Classes/NSPersistentStoreCoordinator_Class/).
 *
 *  @param coordinator The coordinator
 *
 *  @return the array
 */
+ (NSArray *)storesFromCoordinator:(NSPersistentStoreCoordinator *)coordinator;

/**
 *  The name of the database associated with this CDTIncrementalStore.
 */
@property (nonatomic, strong) NSString *databaseName;

/** @name Replicating with a remote Cloudant datastore */

/**
 * Create a CDTReplicator object set up to replicate changes from the
 * local datastore to a remote database.
 *
 *  @param remoteURL the remote server URL to which the data is replicated.
 *  @param error     report error information
 *
 *  @return a CDTReplicator instance which can be used to start and
 *  stop the replication itself, or `nil` on error.
 */
- (CDTISReplicator *)replicatorThatPushesToURL:(NSURL *)remoteURL withError:(NSError **)error;

/**
 * Create a CDTReplicator object set up from replicate changes from a remote database to the
 * local datastore.
 *
 *  @param remoteURL the remote server URL to which the data is replicated.
 *  @param error     report error information
 *
 *  @return a CDTReplicator instance which can be used to start and
 *  stop the replication itself, or `nil` on error.
 */
- (CDTISReplicator *)replicatorThatPullsFromURL:(NSURL *)remoteURL withError:(NSError **)error;

/* Internal methods */

- (NSDictionary *)valuesFromDocumentBody:(NSDictionary *)body
                           withBlobStore:(NSDictionary *)blobStore
                             withContext:(NSManagedObjectContext *)context
                              versionPtr:(uint64_t *)version;

- (NSManagedObject *)managedObjectForEntityName:(NSString *)name
                                referenceObject:(NSString *)ref
                                        context:(NSManagedObjectContext *)context;

@end
