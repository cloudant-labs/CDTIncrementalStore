//
//  CDTISReplicator.m
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

#import "CDTISReplicator.h"
#import "CDTIncrementalStore.h"
#import "CDTISObjectModel.h"

#import "CDTDatastore+Conflicts.h"

@interface CDTISReplicator ()

@property (nonatomic, strong) CDTIncrementalStore *incrementalStore;
@property (nonatomic, strong) CDTDatastore *datastore;
@property (nonatomic, strong) NSMutableDictionary *conflicts;
@end

@implementation CDTISReplicator

- (instancetype)initWithDatastore:(CDTDatastore *)datastore
                 incrementalStore:(CDTIncrementalStore *)incrementalStore
                       replicator:(CDTReplicator *)replicator
{
    self = [super init];
    if (!self) {
        return nil;
    }
    _conflicts = [NSMutableDictionary dictionary];
    if (!_conflicts) {
        return nil;
    }

    _datastore = datastore;
    _incrementalStore = incrementalStore;
    _replicator = replicator;

    return self;
}

- (CDTDocumentRevision *)resolve:(NSString *)docId conflicts:(NSArray *)conflicts
{
    NSArray *bySeq = [conflicts sortedArrayUsingComparator:^(id obj1, id obj2) {
      return TDSequenceCompare([obj1 sequence], [obj2 sequence]);
    }];

    // Store is away if no metadata
    if (![docId isEqualToString:CDTISMetaDataDocID]) {
        self.conflicts[docId] = bySeq;
    }

    // Resolve to the local one for now to keep things consistant
    return [bySeq lastObject];
}

- (NSArray *)mergeConflicts:(NSManagedObjectContext *)context
{
    NSMutableArray *mergeConflicts = [NSMutableArray array];

    // lets do the conflicts
    for (NSString *docID in self.conflicts) {
        NSArray *conflicts = self.conflicts[docID];

        if (conflicts.count != 2) oops(@"not expecting count [%@] > 2", @(conflicts.count));

        NSNumber *vNum;

        CDTDocumentRevision *local = [conflicts objectAtIndex:0];
        vNum = local.body[CDTISObjectVersionKey];
        uint64_t localVersion = [vNum longLongValue];
        NSDictionary *localValues = [self.incrementalStore valuesFromDocumentBody:local.body
                                                                    withBlobStore:local.attachments
                                                                      withContext:context
                                                                       versionPtr:&localVersion];
        if (!localValues) {
            oops(@"bad localValues") return nil;
        }

        CDTDocumentRevision *remote = [conflicts objectAtIndex:1];
        uint64_t remoteVersion = 0;
        NSDictionary *remoteValues = nil;
        if (!remote.deleted) {
            vNum = remote.body[CDTISObjectVersionKey];
            remoteVersion = [vNum longLongValue];
            remoteValues = [self.incrementalStore valuesFromDocumentBody:remote.body
                                                           withBlobStore:remote.attachments
                                                             withContext:context
                                                              versionPtr:&remoteVersion];
            if (!remoteValues) {
                oops(@"bad remoteValues") return nil;
            }
        }

        NSString *name = remote.body[CDTISEntityNameKey];
        NSString *ref = remote.docId;

        NSManagedObject *mo = [self.incrementalStore managedObjectForEntityName:name
                                                                referenceObject:ref
                                                                        context:context];

        NSMergeConflict *mc = [[NSMergeConflict alloc] initWithSource:mo
                                                           newVersion:(NSUInteger)remoteVersion
                                                           oldVersion:(NSUInteger)localVersion
                                                       cachedSnapshot:localValues
                                                    persistedSnapshot:remoteValues];

        [mergeConflicts addObject:mc];
    }

    return [NSArray arrayWithArray:mergeConflicts];
}

- (NSArray *)processConflictsWithContext:(NSManagedObjectContext *)context error:(NSError **)error
{
    NSError *err;
    NSArray *conflicted = [self.datastore getConflictedDocumentIds];

    // need to deal with meta first
    NSUInteger metaIndex = [conflicted indexOfObject:CDTISMetaDataDocID];
    if (metaIndex != NSNotFound) {
        if (![self.datastore resolveConflictsForDocument:CDTISMetaDataDocID
                                                resolver:self
                                                   error:&err]) {
            if (error) {
                // does this qualify for a special error?
                *error = err;
                return nil;
            }
        }

        // I could refetch here, but this is, likely to be, more efficient
        NSMutableArray *prune = [NSMutableArray arrayWithArray:conflicted];
        [prune removeObjectAtIndex:metaIndex];
        conflicted = [NSArray arrayWithArray:prune];
    }

    NSUInteger count = 0;

    for (NSString *docID in conflicted) {
        if (![self.datastore resolveConflictsForDocument:docID resolver:self error:&err]) {
            if (error) {
                *error = err;
                // should probably return a list of errors
            }
        }
        ++count;
    }
    return [self mergeConflicts:context];
}

@end