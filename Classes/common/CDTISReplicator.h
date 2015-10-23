//
//  CDTISReplicator.h
//  CDTIncrementalStore
//
//  Created by Jimi Xenidis on 4/24/15.
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

#import "CDTConflictResolver.h"

@class CDTIncrementalStore;

/**
 CDTISReplicator represents a replication job for a CDTIncrementalStore.

 CDTISReplicator wraps a CDTReplicator of the underlying CDTDatastore, which performs
 the mechanics of the replication.  Use the `replicatorThatPullsFromURL:withError:` or
 `replicatorThatPushesToURL:withError:` methods of CDTIncrementalStore to obtain a
 CDTISReplicator.

 CDTISReplicator also provides a method to help resolve merge conflicts
 in a manner that is familiar to Core Data developers.
 Use the `-processConflictsWithContext:error:` to handle conflicts following a
 _pull_ replication.  This method returns an array of merge conflict objects that
 can be used to resolve conflicts using CoreData's standard `NSMergePolicy` class.

 The following example shows how to use `-processConflictsWithContext:error:` and
 NSMergePolicy to resolve conflicts in the local CDTDatastore following a pull
 replication.

	NSError *err;
	CDTISReplicator *puller = [myStore replicatorThatPullsFromURL:remoteURL withError:&err];
	NSManagedObjectContext *moc =  <Any active context>;
	NSArray *mergeConflicts = [puller processConflictsWithContext:moc error:nil];
	NSMergePolicy *mp = [[NSMergePolicy alloc] initWithMergeType:NSMergeByPropertyStoreTrumpMergePolicyType];
	if (![mp resolveConflicts:conflicts error:&err]) {
		// handle conflict resolution failure
	}

 */
@interface CDTISReplicator : NSObject <CDTConflictResolver>

/** @name Replicating with a remote Cloudant datastore */

/** The CloudantSync replicator instance for this CDTISReplicator. */
@property (nonatomic, strong) CDTReplicator *replicator;

/**
 * Returns an array of merge conflicts present in the local CDTDatastore.
 *
 * Use this method to obtain a list of merge conflicts in the local CDTDatastore following a pull
 * replication.  These conflicts should be resolved locally before performing a push replication
 * with a remote datastore.
 *
 * @param context	A managed object context
 * @param error		If an error occurs, upon return contains an NSError object that describes the problem.
 * @return			An array of merge conflicts (instances of NSMergeConflict).
 */
- (NSArray *)processConflictsWithContext:(NSManagedObjectContext *)context error:(NSError **)error;

/* Internal methods */

- (instancetype)initWithDatastore:(CDTDatastore *)datastore
                 incrementalStore:(CDTIncrementalStore *)incrementalStore
                       replicator:(CDTReplicator *)replicator;

@end