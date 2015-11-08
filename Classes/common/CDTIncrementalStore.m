//
//  CDTIncrementalStore.m
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

#import <Foundation/Foundation.h>
#import <libkern/OSAtomic.h>

#import <CDTLogging.h>

#import "CDTDatastore+Query.h"

#import "CDTIncrementalStore.h"
#import "CDTISObjectModel.h"

#ifdef HAS_NSBatchUpdateRequest
/*
 *  Currently NSBatchUpdateResult does not supply setters.
 *  We replicate the definition of the object but make them readwrite.
 *  Later, we cast it back to the original class.. so far it works.
 */
@interface CDTIS_NSBatchUpdateResult : NSPersistentStoreResult {
@private
    id _aggregatedResult;
    NSBatchUpdateRequestResultType _resultType;

}

// Return the result. See NSBatchUpdateRequestResultType for options
@property (strong, readwrite) id result;
@property (readwrite) NSBatchUpdateRequestResultType resultType;

@end

@implementation CDTIS_NSBatchUpdateResult

@end
#endif

#pragma mark - properties
@interface CDTIncrementalStore ()

@property (nonatomic, strong) CDTDatastore *datastore;
@property (nonatomic, strong) CDTDatastoreManager *manager;
@property (nonatomic, strong) NSURL *localURL;
@property (nonatomic, strong) CDTISObjectModel *objectModel;
@property (nonatomic, strong) CDTReplicatorFactory *repFactory;

@end

#pragma mark - string constants
// externed
NSString *const CDTISErrorDomain = @"CDTIncrementalStoreDomain";
NSString *const CDTISException = @"CDTIncrementalStoreException";

static NSString *const CDTISType = @"CDTIncrementalStore";
static NSString *const CDTISDBName = @"cdtisdb";

static NSString *const CDTISIdentifierKey = @"CDTISIdentifier";

#pragma mark - property string type for backing store

static NSString *const CDTISMetaDataKey = @"metaData";
static NSString *const CDTISObjectModelKey = @"objectModel";

#pragma mark - Code selection
// allows selection of different code paths
// Use this instead of #ifdef's so the code are actually gets compiled

/*
 *  If true, will simply delete the database object with no considerations
 */
static BOOL CDTISDeleteAggresively = NO;

/*
 *  The backing store will drop the document body if there is a JSON
 *  serialization error. When this happens there is no failure condition or
 *  error reported.  So we read it back and make sure the body isn't empty.
 */
static BOOL CDTISReadItBack = YES;

/*
 *  Default log level.
 *  Setting it to DDLogLevelOff does not turn it off, but will simply
 *  not adjust it.
 */
static DDLogLevel CDTISEnableLogging = DDLogLevelOff;

/*
 *  Detect if the hashes changed and update the stored object model.
 *  Turn this on if you would like to migrate objects into the same store.
 *
 *  > ***Warning***: Use with care
 */
static BOOL CDTISUpdateStoredObjectModel = NO;

/*
 *  Check entity version mismatches which could cause problems
 */
static BOOL CDTISCheckEntityVersions = NO;

/*
 *  Check for the exisitence of subentities that we may be ignorning
 */
static BOOL CDTISCheckForSubEntities = NO;

/*
 *	Support batch update requests.
 */
static BOOL CDTISSupportBatchUpdates = YES;

@implementation CDTIncrementalStore

#pragma mark - Init
/*
 *  Registers this NSPersistentStore.
 *  You must invoke this method before a custom subclass of NSPersistentStore
 *  can be loaded into a persistent store coordinator.
 */
+ (void)initialize
{
    if (![[self class] isEqual:[CDTIncrementalStore class]]) {
        return;
    }

    [NSPersistentStoreCoordinator registerStoreClass:self forStoreType:[self type]];

    if (!NSClassFromString(@"NSBatchUpdateRequest")) {
        CDTISSupportBatchUpdates = NO;
    }

    /*
     *  We post to:
     *  - CDTDATASTORE_LOG_CONTEXT
     *  - CDTREPLICATION_LOG_CONTEXT
     *
     *  We are interested in:
     *  - CDTTD_REMOTE_REQUEST_CONTEXT
     *  - CDTDOCUMENT_REVISION_LOG_CONTEXT
     */
    if (CDTISEnableLogging != DDLogLevelOff) {
        [DDLog addLogger:[DDTTYLogger sharedInstance]];

        CDTChangeLogLevel(CDTREPLICATION_LOG_CONTEXT, CDTISEnableLogging);
        CDTChangeLogLevel(CDTDATASTORE_LOG_CONTEXT, CDTISEnableLogging);
        CDTChangeLogLevel(CDTDOCUMENT_REVISION_LOG_CONTEXT, CDTISEnableLogging);
        CDTChangeLogLevel(CDTTD_REMOTE_REQUEST_CONTEXT, CDTISEnableLogging);
    }
}

+ (NSString *)type { return CDTISType; }

+ (NSArray *)storesFromCoordinator:(NSPersistentStoreCoordinator *)coordinator
{
    NSArray *stores = [coordinator persistentStores];
    NSMutableArray *ours = [NSMutableArray array];

    for (id ps in stores) {
        if ([ps isKindOfClass:[CDTIncrementalStore class]]) {
            [ours addObject:ps];
        }
    }
    return [NSArray arrayWithArray:ours];
}

#pragma mark - Utils
/*
 *  Generate a unique identifier
 *
 *  @return A unique ID
 */
static NSString *uniqueID(NSString *label)
{
    return [NSString stringWithFormat:@"%@-%@-%@", CDTISPrefix, label, TDCreateUUID()];
}

/*
 * It appears that CoreData will convert an NSString reference object to an
 * NSNumber if it can, so we make sure we always use a string.
 *
 *  @param objectID a CoreData object ID
 *
 *  @return A string that is the docID for the object
 */
- (NSString *)stringReferenceObjectForObjectID:(NSManagedObjectID *)objectID
{
    id ref = [self referenceObjectForObjectID:objectID];
    if ([ref isKindOfClass:[NSNumber class]]) {
        return [ref stringValue];
    }
    return ref;
}

/*
 *  Checks to see if the entity hashes match
 *
 *  @param entity   The entity you want to compare
 *  @param metadata Metadata for the store
 *
 *  @return YES on success, FALSE on failure
 */
static BOOL badEntityVersion(NSEntityDescription *entity, NSDictionary *metadata)
{
    if (!CDTISCheckEntityVersions) return NO;

    NSString *oidName = entity.name;
    NSData *oidHash = entity.versionHash;
    NSDictionary *dic = metadata[NSStoreModelVersionHashesKey];
    NSData *metaHash = dic[oidName];

    if ([oidHash isEqualToData:metaHash]) return NO;
    return YES;
}

/*
 *  Checks to see if an object ID matches the metadata.
 *
 *  @param moid     Object ID
 *  @param metadata Metadata fot he store
 *
 *  @return YES on success, FALSE on failure
 */
static BOOL badObjectVersion(NSManagedObjectID *moid, NSDictionary *metadata)
{
    if (!CDTISCheckEntityVersions) return NO;
    return badEntityVersion(moid.entity, metadata);
}

- (NSInteger)propertyTypeFromDoc:(NSDictionary *)body withName:(NSString *)name
{
    if (!self.objectModel) oops(@"no object model exists yet");

    NSString *entityName = body[CDTISEntityNameKey];
    NSInteger ptype = [self.objectModel propertyTypeWithName:name withEntityName:entityName];
    return ptype;
}

- (NSString *)destinationFromDoc:(NSDictionary *)body withName:(NSString *)name
{
    if (!self.objectModel) oops(@"no object model exists yet");

    NSString *entityName = body[CDTISEntityNameKey];
    NSString *dest = [self.objectModel destinationWithName:name withEntityName:entityName];
    return dest;
}

- (NSString *)xformFromDoc:(NSDictionary *)body withName:(NSString *)name
{
    if (!self.objectModel) oops(@"no object model exists yet");

    NSString *entityName = body[CDTISEntityNameKey];
    NSString *xform = [self.objectModel xformWithName:name withEntityName:entityName];
    return xform;
}

/*
 *  used for logging so we don't leach out the developer keys
 *
 *  @param url URL
 *
 *  @return Clean URL String
 */
- (NSString *)cleanURL:(NSURL *)url
{
    return
        [NSString stringWithFormat:@"%@://%@:****@%@/%@", url.scheme, url.user, url.host, url.path];
}

#pragma mark - property encode

/*
 *  Insert an NSData binary object into the "blob" store
 *
 *  @param blob  nbinary data
 *  @param name  key
 *  @param store blob store
 *  @param mt    Mime Type if known
 *
 *  @return <#return value description#>
 */
- (NSString *)encodeBlob:(NSData *)blob
                withName:(NSString *)name
                 inStore:(NSMutableDictionary *)store
            withMIMEType:(NSString *)mt
{
    CDTUnsavedDataAttachment *at =
        [[CDTUnsavedDataAttachment alloc] initWithData:blob name:name type:mt];
    store[name] = at;
    return name;
}

/*
 *  Create a dictionary (for JSON) that encodes an attribute.
 *  The dictionary contains:
 *    * name : value entry giving the attribute name and (possibly encoded) value
 *    * _optional_ metadata for the attribute in an entry named CDTISMakeMeta(name)
 *
 *  @param attribute The attribute
 *  @param value     The object
 *  @param blobStore The blobStore
 *  @param error     Error
 *
 *  @return Encoded array
 */
- (NSDictionary *)encodeAttribute:(NSAttributeDescription *)attribute
                        withValue:(id)value
                        blobStore:(NSMutableDictionary *)blobStore
                            error:(NSError **)error
{
    NSAttributeType type = attribute.attributeType;
    NSString *name = attribute.name;

    // Keep this
    if (!value) oops(@"no nil allowed");

    switch (type) {
        case NSStringAttributeType: {
            NSString *str = value;
            return @{
                name : str,
            };
        }
        case NSBooleanAttributeType:
        case NSInteger16AttributeType:
        case NSInteger32AttributeType:
        case NSInteger64AttributeType: {
            NSNumber *num = value;
            return @{
                name : num,
            };
        }
        case NSDateAttributeType: {
            NSDate *date = value;
            NSNumber *since = [NSNumber numberWithDouble:[date timeIntervalSince1970]];
            return @{
                name : since,
            };
        }
        case NSBinaryDataAttributeType: {
            NSData *data = value;
            NSString *mimeType = @"application/octet-stream";
            NSString *bytes =
                [self encodeBlob:data withName:name inStore:blobStore withMIMEType:mimeType];
            return @{
                name : bytes,
                CDTISMakeMeta(name) : @{CDTISMIMETypeKey : mimeType}
            };
        }
        case NSTransformableAttributeType: {
            NSString *xname = [attribute valueTransformerName];
            NSString *mimeType = @"application/octet-stream";
            NSData *save;
            if (xname) {
                Class myClass = NSClassFromString(xname);
                // Yes, we could try/catch here.. but why?
                if ([myClass respondsToSelector:@selector(MIMEType)]) {
                    mimeType = [myClass performSelector:@selector(MIMEType)];
                }
                id xform = [[myClass alloc] init];
                // use reverseTransformedValue to come back
                save = [xform transformedValue:value];
            } else {
                save = [NSKeyedArchiver archivedDataWithRootObject:value];
            }
            NSString *bytes =
                [self encodeBlob:save withName:name inStore:blobStore withMIMEType:mimeType];

            return @{ name : bytes, CDTISMakeMeta(name) : @{CDTISMIMETypeKey : mimeType} };
        }
        case NSObjectIDAttributeType: {
            // I don't think converting to a ref is needed, besides we
            // would need the entity id to decode.
            NSManagedObjectID *oid = value;
            NSURL *uri = [oid URIRepresentation];
            return @{
                name : [uri absoluteString],
            };
        }
        case NSDecimalAttributeType: {
            NSDecimalNumber *dec = value;
            NSString *desc = [dec description];
            NSDecimal val = [dec decimalValue];
            NSData *data = [NSData dataWithBytes:&val length:sizeof(val)];
            NSString *b64 = [data base64EncodedStringWithOptions:0];
            NSMutableDictionary *meta = [NSMutableDictionary dictionary];
            meta[CDTISDecimalImageKey] = b64;

            if ([dec isEqual:[NSDecimalNumber notANumber]]) {
                meta[CDTISFPNonFiniteKey] = CDTISFPNaN;
                desc = nil;
            }
            if (desc) {
                return @{
                    name : desc,
                    CDTISMakeMeta(name) : [NSDictionary dictionaryWithDictionary:meta]
                };
            } else {
                return @{
                    name : [NSNull null],
                    CDTISMakeMeta(name) : [NSDictionary dictionaryWithDictionary:meta]
                };
            }
        }
        case NSDoubleAttributeType: {
            NSNumber *num = value;
            double dbl = [num doubleValue];
            uint64_t u64 = *(uint64_t *)&dbl;
            NSNumber *n64 = [NSNumber numberWithUnsignedLongLong:u64];
            NSMutableDictionary *meta = [NSMutableDictionary dictionary];
            meta[CDTISDoubleImageKey] = n64;

            if ([num isEqual:@(INFINITY)]) {
                num = @(DBL_MAX);
                meta[CDTISFPNonFiniteKey] = CDTISFPInfinity;
            }
            if ([num isEqual:@(-INFINITY)]) {
                num = @(-DBL_MAX);
                meta[CDTISFPNonFiniteKey] = CDTISFPNegInfinity;
            }
            // we use null if it is NaN that way it will not get evaluated as a predicate
            if ([num isEqual:@(NAN)]) {
                num = nil;
                meta[CDTISFPNonFiniteKey] = CDTISFPNaN;
            }
            if (num) {
                // NSDecimalNumber "description" is the closest thing we will get
                // to an arbitrary precision number in JSON, so lets use it.
                NSDecimalNumber *dec = (NSDecimalNumber *)[NSDecimalNumber numberWithDouble:dbl];
                NSString *str = [dec description];
                return @{
                    name : str,
                    CDTISMakeMeta(name) : [NSDictionary dictionaryWithDictionary:meta]
                };
            }
            return @{
                name : [NSNull null],
                CDTISMakeMeta(name) : [NSDictionary dictionaryWithDictionary:meta]
            };
        }
        case NSFloatAttributeType: {
            NSNumber *num = value;
            float flt = [num floatValue];
            NSNumber *i32 = @(*(int32_t *)&flt);
            NSMutableDictionary *meta = [NSMutableDictionary dictionary];
            meta[CDTISFloatImageKey] = i32;

            if ([num isEqual:@(INFINITY)]) {
                num = @(FLT_MAX);
                meta[CDTISFPNonFiniteKey] = CDTISFPInfinity;
            }
            if ([num isEqual:@(-INFINITY)]) {
                num = @(-FLT_MAX);
                meta[CDTISFPNonFiniteKey] = CDTISFPNegInfinity;
            }

            // we use null if it is NaN that way it will not get evaluated as a
            // predicate
            if ([num isEqual:@(NAN)]) {
                meta[CDTISFPNonFiniteKey] = CDTISFPNaN;
                num = nil;
            }
            if (num) {
                return @{
                    name : num,
                    CDTISMakeMeta(name) : [NSDictionary dictionaryWithDictionary:meta]
                };
            }
            return @{
                name : [NSNull null],
                CDTISMakeMeta(name) : [NSDictionary dictionaryWithDictionary:meta]
            };
        }
		case NSUndefinedAttributeType:
		default: {
			if (error) {
				NSString *str =
				[NSString localizedStringWithFormat:@"Undefined attribute type: %@", @(type)];
				NSDictionary *ui = @{NSLocalizedDescriptionKey : str};
				*error = [NSError errorWithDomain:CDTISErrorDomain
											 code:CDTISErrorUndefinedAttributeType
										 userInfo:ui];
			}
			return nil;
		}
    }

    return nil;
}

/*
 *  Encode a relation as a dictionary of strings:
 *  * entity name
 *  * ref/docID
 *
 *  > *Note*: the entity name is necessary for decoding
 *
 *  @param mo Managed Object
 *
 *  @return dictionary
 */
- (NSString *)encodeRelationFromManagedObject:(NSManagedObject *)mo
{
    if (!mo) {
        return @"";
    }

    NSManagedObjectID *moid = [mo objectID];

    if (moid.isTemporaryID) oops(@"tmp");

    NSString *ref = [self referenceObjectForObjectID:moid];
    return ref;
}

/*
 *  Encode a complete relation, both "to-one" and "to-many"
 *
 *  @param rel   relation
 *  @param value   object
 *  @param error error
 *
 *  @return the dictionary
 */
- (NSDictionary *)encodeRelation:(NSRelationshipDescription *)rel
                       withValue:(id)value
                           error:(NSError **)error
{
    NSString *name = rel.name;

    if (!rel.isToMany) {
        NSManagedObject *mo = value;
        NSString *enc = [self encodeRelationFromManagedObject:mo];
        return @{
            name : enc,
        };
    }
    NSMutableArray *ids = [NSMutableArray array];
    for (NSManagedObject *mo in value) {
        if (!mo) oops(@"nil mo");

        NSString *enc = [self encodeRelationFromManagedObject:mo];
        [ids addObject:enc];
    }
    return @{
        name : ids,
    };
}

/*
 *  Get all the properties of a managed object and put them in a dictionary
 *
 *  @param mo managed object
 *  @param blobStore The blobStore
 *
 *  @return dictionary
 */
- (NSDictionary *)propertiesFromManagedObject:(NSManagedObject *)mo
                                withBlobStore:(NSMutableDictionary *)blobStore
{
    NSError *err = nil;
    NSEntityDescription *entity = [mo entity];
    NSDictionary *propDic = [entity propertiesByName];
    NSMutableDictionary *props = [NSMutableDictionary dictionary];

    for (NSString *name in propDic) {
        id prop = propDic[name];
        if ([prop isTransient]) {
            continue;
        }
        id value = [mo valueForKey:name];
        NSDictionary *enc = nil;
        if ([prop isKindOfClass:[NSAttributeDescription class]]) {
            NSAttributeDescription *att = prop;
            if (!value) {
                // don't even process nil objects
                continue;
            }
            enc = [self encodeAttribute:att withValue:value blobStore:blobStore error:&err];
        } else if ([prop isKindOfClass:[NSRelationshipDescription class]]) {
            NSRelationshipDescription *rel = prop;
            enc = [self encodeRelation:rel withValue:value error:&err];
        } else if ([prop isKindOfClass:[NSFetchedPropertyDescription class]]) {
            /*
             *  The incremental store should never see this, if it did it would
             * make NoSQL "views" interesting
             */
            [NSException raise:CDTISException format:@"Fetched property?: %@", prop];
        } else {
            [NSException raise:CDTISException format:@"unknown property: %@", prop];
        }

        if (!enc) {
            [NSException raise:CDTISException
                        format:@"There should always be an encoding: %@: %@", prop, err];
        }

        [props addEntriesFromDictionary:enc];
    }

    if (CDTISCheckForSubEntities) {
        NSArray *entitySubs = [[mo entity] subentities];
        if ([entitySubs count] > 0) {
            CDTLogDebug(CDTDATASTORE_LOG_CONTEXT, @"%@: subentities: %@", CDTISType, entitySubs);
        }
    }
    return [NSDictionary dictionaryWithDictionary:props];
}

#pragma mark - property decode
/*
 *  Create an Object ID from the information decoded in
 *  [encodeRelationFromManagedObject](@ref encodeRelationFromManagedObject)
 *
 *  @param entityName entityName
 *  @param ref        ref
 *  @param context    context
 *
 *  @return object ID
 */
- (NSManagedObjectID *)decodeRelationFromEntityName:(NSString *)entityName
                                            withRef:(NSString *)ref
                                        withContext:(NSManagedObjectContext *)context
{
    if (entityName.length == 0 || ref.length == 0) {
        return nil;
    }
    NSEntityDescription *entity =
        [NSEntityDescription entityForName:entityName inManagedObjectContext:context];
    NSManagedObjectID *moid = [self newObjectIDForEntity:entity referenceObject:ref];
    return moid;
}

/*
 *  Extract the binary object for the "blob" store
 *
 *  @param name  Key
 *  @param store blob store
 *
 *  @return Binary data
 */
- (NSData *)decodeBlob:(NSString *)name fromStore:(NSDictionary *)store
{
    CDTSavedAttachment *att = store[name];
    return [att dataFromAttachmentContent];
}

/*
 *  Get the object from the encoded property
 *
 *  @param name    name of object
 *  @param body    Dictionary representing the document
 *  @param blobStore The blobStore
 *  @param context Context for the object
 *
 *  @return object or nil if no object exists
 */
- (id)decodeProperty:(NSString *)name
             fromDoc:(NSDictionary *)body
       withBlobStore:(NSDictionary *)blobStore
         withContext:(NSManagedObjectContext *)context
{
    NSInteger type = [self propertyTypeFromDoc:body withName:name];

    // we defer to newValueForRelationship:forObjectWithID:withContext:error
    if (type == CDTISRelationToManyType) {
        return nil;
    }

    id prop = body[name];
    NSDictionary *meta = body[CDTISMakeMeta(name)];

    id value;

    switch (type) {
        case NSStringAttributeType:
        case NSBooleanAttributeType:
            value = prop;
            break;
        case NSDateAttributeType: {
            NSNumber *since = prop;
            value = [NSDate dateWithTimeIntervalSince1970:[since doubleValue]];
        } break;
        case NSBinaryDataAttributeType: {
            NSString *uname = prop;
            value = [self decodeBlob:uname fromStore:blobStore];
        } break;
        case NSTransformableAttributeType: {
            NSString *xname = [self xformFromDoc:body withName:name];
            NSString *uname = prop;
            NSData *restore = [self decodeBlob:uname fromStore:blobStore];
            if (xname) {
                id xform = [[NSClassFromString(xname) alloc] init];
                // is the xform guaranteed to handle nil?
                value = [xform reverseTransformedValue:restore];
            } else {
                value = [NSKeyedUnarchiver unarchiveObjectWithData:restore];
            }
        } break;
        case NSObjectIDAttributeType: {
            NSString *str = prop;
            NSURL *uri = [NSURL URLWithString:str];
            NSManagedObjectID *moid =
                [self.persistentStoreCoordinator managedObjectIDForURIRepresentation:uri];
            value = moid;
        } break;
        case NSDecimalAttributeType: {
            NSString *b64 = meta[CDTISDecimalImageKey];
            NSData *data = [[NSData alloc] initWithBase64EncodedString:b64 options:0];
            NSDecimal val;
            [data getBytes:&val length:sizeof(val)];
            value = [NSDecimalNumber decimalNumberWithDecimal:val];
        } break;
        case NSDoubleAttributeType: {
            // just get the image
            NSNumber *n64 = meta[CDTISDoubleImageKey];
            // 10.9 [n64 unsignedLongLongValue] has a bug and returns wrong value
            NSString *s64 = [n64 description];
            uint64_t u64 = strtoull([s64 UTF8String], NULL, 0xa);
            double dbl = *(double *)&u64;
            NSNumber *num = [NSNumber numberWithDouble:dbl];
            value = num;
        } break;
        case NSFloatAttributeType: {
            // just get the image
            NSNumber *i32Num = meta[CDTISFloatImageKey];
            int32_t i32 = (int32_t)[i32Num integerValue];
            NSNumber *num = @(*(float *)&i32);
            value = num;
        } break;
        case NSInteger16AttributeType:
        case NSInteger32AttributeType:
        case NSInteger64AttributeType: {
            NSNumber *num = prop;
            value = num;
        } break;
        case CDTISRelationToOneType: {
            NSString *ref = prop;
            NSString *entityName = [self destinationFromDoc:body withName:name];
            if (entityName.length == 0) {
                value = [NSNull null];
            } else {
                NSManagedObjectID *moid =
                    [self decodeRelationFromEntityName:entityName withRef:ref withContext:context];
                if (!moid) {
                    // Our relation desitination object has not been assigned
                    value = [NSNull null];
                } else {
                    value = moid;
                }
            }
        } break;
        case CDTISRelationToManyType:
            // See the check at the top of this function
            oops(@"this is deferred to newValueForRelationship");
            break;
        default:
            oops(@"unknown encoding: %@", @(type));
            break;
    }

    return value;
}

#pragma mark - database methods
/*
 *  Insert a managed object to the database
 *
 *  @param mo    Managed Object
 *  @param error Error
 *
 *  @return YES on success, NO on Failure
 */
- (BOOL)insertManagedObject:(NSManagedObject *)mo error:(NSError **)error
{
    NSError *err = nil;
    NSManagedObjectID *moid = [mo objectID];
    NSString *docID = [self stringReferenceObjectForObjectID:moid];
    NSEntityDescription *entity = [mo entity];

    // I don't think this should never happen
    if (moid.isTemporaryID) oops(@"tmp");

    if (badObjectVersion(moid, self.metadata)) oops(@"hash mismatch?: %@", moid);

    CDTDocumentRevision *newRev = [CDTDocumentRevision revisionWithDocId:docID];
    NSMutableDictionary *blobStore = [NSMutableDictionary dictionary];

    // do the actual attributes first
    newRev.body = [[self propertiesFromManagedObject:mo withBlobStore:blobStore] mutableCopy];
    newRev.body[CDTISObjectVersionKey] = @"1";
    newRev.body[CDTISEntityNameKey] = [entity name];
    newRev.body[CDTISIdentifierKey] = [[[mo objectID] URIRepresentation] absoluteString];
    if ([blobStore count]) {
        newRev.attachments = blobStore;
    }

    CDTDocumentRevision *rev = [self.datastore createDocumentFromRevision:newRev error:&err];
    if (!rev) {
        if (error) *error = err;
        return NO;
    }

    if (CDTISReadItBack) {
        /*
         *  See CDTISReadItBack
         */
        rev = [self.datastore getDocumentWithId:newRev.docId error:&err];
        if (!rev) {
            // Always oops!
            oops(@"ReadItBack: error: %@", err);
        }
        // Always oops
        if ([rev.body count] == 0) oops(@"empty save");
    }

    return YES;
}

/*
 *  Update existing managed object
 *
 *  @param mo    Managed Object
 *  @param error Error
 *
 *  @return YES/NO
 */
- (BOOL)updateManagedObject:(NSManagedObject *)mo error:(NSError **)error
{
    NSManagedObjectID *moid = [mo objectID];
    NSDictionary *changes = [mo changedValues];

    if (badObjectVersion(moid, self.metadata)) oops(@"hash mismatch?: %@", moid);

    NSString *docID = [self stringReferenceObjectForObjectID:moid];

    NSEntityDescription *entity = [mo entity];
    return [self updateDocumentID:docID withChanges:changes entity:entity error:error];
}

/*
 *  Update existing document in the database
 *
 *  @param docID    Document ID
 *  @param changes  Dictionary of [key:NSString, value:id] of changes to make to mo contents
 *  @param entity   Entity description
 *  @param error    Error
 *
 *  @return YES/NO
 */
- (BOOL)updateDocumentID:(NSString *)docID
             withChanges:(NSDictionary *)changes
                  entity:(NSEntityDescription *)entity
                   error:(NSError **)error
{
    NSDictionary *propsByName = [entity propertiesByName];
    NSMutableDictionary *props = [NSMutableDictionary dictionary];
    NSMutableDictionary *blobStore = [NSMutableDictionary dictionary];

    for (NSString *name in changes) {
        NSDictionary *enc = nil;
        id prop = propsByName[name];
        if ([prop isTransient]) {
            continue;
        }
        if ([prop isKindOfClass:[NSAttributeDescription class]]) {
            NSAttributeDescription *att = prop;
            enc =
                [self encodeAttribute:att withValue:changes[name] blobStore:blobStore error:error];
        } else if ([prop isKindOfClass:[NSRelationshipDescription class]]) {
            NSRelationshipDescription *rel = prop;
            enc = [self encodeRelation:rel withValue:changes[name] error:error];
        } else {
            oops(@"bad prop?");
        }
        [props addEntriesFromDictionary:enc];
    }

    return [self updateDocumentID:docID withProperties:props blobStore:blobStore error:error];
}

- (BOOL)updateDocumentID:(NSString *)docID
          withProperties:(NSMutableDictionary *)props
               blobStore:(NSDictionary *)blobStore
                   error:(NSError **)error
{
    NSError *err = nil;

    CDTDocumentRevision *oldRev = [self.datastore getDocumentWithId:docID error:&err];
    if (!oldRev) {
        if (error) *error = err;
        return NO;
    }

    // TODO: version HACK
    NSString *oldVersion = oldRev.body[CDTISObjectVersionKey];
    uint64_t version = [oldVersion longLongValue];
    ++version;
    NSNumber *v = [NSNumber numberWithUnsignedLongLong:version];
    props[CDTISObjectVersionKey] = [v stringValue];

    CDTDocumentRevision *upRev = [oldRev copy];

    // update attachments first
    if ([blobStore count]) {
        [upRev.attachments addEntriesFromDictionary:blobStore];
    }

    /*
     *  > ***Note***:
     *  >
     *  > Since the properties of the entity are being updated/modified, there is
     *  > no need to remove the actual members from the body.
     *  >
     *  > However, care must be taken, since this code adds additional "Meta Properties"
     *  > to the dictionary that may require cleaning up.
     *  >
     *  > Currently, this is not a problem since we collect all "Meta Properties"
     *  > in a single dictionary that is always present if necessary.
     *  > Therefore, there is nothing to clean up.
     */
    [upRev.body addEntriesFromDictionary:props];

    CDTDocumentRevision *upedRev = [self.datastore updateDocumentFromRevision:upRev error:&err];
    if (!upedRev) {
        if (error) *error = err;
        return NO;
    }

    if ([blobStore count]) {
        if (![self.datastore compactWithError:&err]) {
            CDTLogWarn(CDTREPLICATION_LOG_CONTEXT, @"%@: datastore compact failed: %@", CDTISType,
                       err);
        }
    }

    if (CDTISReadItBack) {
        /*
         *  See CDTISReadItBack
         */
        upedRev = [self.datastore getDocumentWithId:upRev.docId error:&err];
        if (!upedRev) {
            // Always oops!
            oops(@"ReadItBack: error: %@", err);
        }
        // Always oops
        if ([upedRev.body count] == 0) oops(@"empty save");
    }

    return YES;
}

/*
 *  Delete a managed object from the database
 *
 *  > ***Warning***: it is assumed that CoreData will handle any cascading
 *  > deletes that are required.
 *
 *  @param mo    Managed Object
 *  @param error Error
 *
 *  @return YES/NO, No with error
 */
- (BOOL)deleteManagedObject:(NSManagedObject *)mo error:(NSError **)error
{
    NSError *err = nil;
    NSManagedObjectID *moid = [mo objectID];
    NSString *docID = [self stringReferenceObjectForObjectID:moid];

    /*
     *  @See CDTISDeleteAggresively
     */
    if (CDTISDeleteAggresively) {
        if (![self.datastore deleteDocumentWithId:docID error:&err]) {
            if (error) *error = err;
            return NO;
        }
        return YES;
    }

    CDTDocumentRevision *oldRev = [self.datastore getDocumentWithId:docID error:&err];
    if (!oldRev) {
        if (error) *error = err;
        return NO;
    }

    if (![self.datastore deleteDocumentFromRevision:oldRev error:&err]) {
        if (error) *error = err;
        return NO;
    }
    return YES;
}

/*
 *  optLock??
 *
 *  @param mo    Managed Object
 *  @param error Error
 *
 *  @return YES/NO
 */
- (BOOL)optLockManagedObject:(NSManagedObject *)mo error:(NSError **)error
{
    oops(@"We don't do this yet");
    return NO;
}

/*
 *  Create a dictionary of values from the Document Body and Blob Store
 *
 *  @param body      body of document
 *  @param blobStore blobStore attachement dictionary
 *  @param context   context from Core Data
 *  @param version   version
 *
 *  @return dictionary
 */
- (NSDictionary *)valuesFromDocumentBody:(NSDictionary *)body
                           withBlobStore:(NSDictionary *)blobStore
                             withContext:(NSManagedObjectContext *)context
                              versionPtr:(uint64_t *)version
{
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    for (NSString *name in body) {
        if ([name isEqualToString:CDTISObjectVersionKey]) {
            *version = [body[name] longLongValue];
            continue;
        }
        if ([name hasPrefix:CDTISPrefix]) {
            continue;
        }

        id value =
            [self decodeProperty:name fromDoc:body withBlobStore:blobStore withContext:context];
        if (!value) {
            // Dictionaries do not take nil, but Values can't have NSNull.
            // Apparently we just skip it and the properties faults take care
            // of it
            continue;
        }
        values[name] = value;
    }

    return [NSDictionary dictionaryWithDictionary:values];
}

/*
 *  Create a dictionary of values for the attributes of a Managed Object from
 *  a docId/ref.
 *
 *  @param docID   docID
 *  @param context context
 *  @param version version
 *  @param error   error
 *
 *  @return dictionary or nil with error
 */
- (NSDictionary *)valuesFromDocID:(NSString *)docID
                      withContext:(NSManagedObjectContext *)context
                       versionPtr:(uint64_t *)version
                            error:(NSError **)error
{
    NSError *err = nil;

    CDTDocumentRevision *rev = [self.datastore getDocumentWithId:docID error:&err];
    if (!rev) {
        if (error) *error = err;
        return nil;
    }

    return [self valuesFromDocumentBody:rev.body
                          withBlobStore:rev.attachments
                            withContext:context
                             versionPtr:version];
}

/*
 *  Initialize database
 *
 *  @param error Error
 *
 *  @return YES/NO
 */
- (BOOL)initializeDatabase:(NSError **)error
{
    NSError *err = nil;
    NSURL *dir = [self URL];
    NSString *path = [dir path];

    /*
     *  check if the directory exists, or needs to be created
     */
    BOOL isDir;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL exists = [fileManager fileExistsAtPath:path isDirectory:&isDir];
    if (exists) {
        if (!isDir) {
            NSString *s =
                [NSString localizedStringWithFormat:@"Can't create datastore directory: %@", dir];
            CDTLogError(CDTDATASTORE_LOG_CONTEXT, @"%@: %@", CDTISType, s);
            if (error) {
                NSDictionary *ui = @{NSLocalizedFailureReasonErrorKey : s};
                *error =
                    [NSError errorWithDomain:CDTISErrorDomain code:CDTISErrorBadPath userInfo:ui];
            }
            return NO;
        }
    } else {
        if (![fileManager createDirectoryAtURL:dir
                   withIntermediateDirectories:YES
                                    attributes:nil
                                         error:&err]) {
            CDTLogError(CDTDATASTORE_LOG_CONTEXT, @"%@: Error creating manager directory: %@",
                        CDTISType, err);
            if (error) {
                *error = err;
            }
            return NO;
        }
    }
    /*
     * The URL we are given is actually a directory.  The backing store is
     * free to create as many files and subdirectories it needs.  So for an
     * actual name we use something constatn and vanilla.
     */
    CDTDatastoreManager *manager = [[CDTDatastoreManager alloc] initWithDirectory:path error:&err];
    if (!manager) {
        CDTLogError(CDTDATASTORE_LOG_CONTEXT, @"%@: %@: Error creating manager: %@", CDTISType, dir,
                    err);
        if (error) *error = err;
        return NO;
    }

    CDTDatastore *datastore = [manager datastoreNamed:CDTISDBName error:&err];
    if (!datastore) {
        CDTLogError(CDTDATASTORE_LOG_CONTEXT, @"%@: %@: Error creating datastore: %@", CDTISType,
                    CDTISDBName, err);
        if (error) *error = err;
        return NO;
    }

    CDTReplicatorFactory *repFactory =
        [[CDTReplicatorFactory alloc] initWithDatastoreManager:manager];
    if (!repFactory) {
        NSString *msg = [NSString
            stringWithFormat:@"%@: Could not create replication factory for datastore", CDTISType];
        CDTLogError(CDTREPLICATION_LOG_CONTEXT, @"%@", msg);
        if (error) {
            NSDictionary *userInfo = @{NSLocalizedFailureReasonErrorKey : msg};
            *error = [NSError errorWithDomain:CDTISErrorDomain
                                         code:CDTISErrorReplicationFactory
                                     userInfo:userInfo];
        }
        return NO;
    }

    // Commit before setting up replication
    self.datastore = datastore;
    self.manager = manager;
    self.repFactory = repFactory;

    return YES;
}

/*
 *  Encode version hashes, which come to us as a dictionary of inline data
 *  objects, so we encode them as a hex string.
 *
 *  @param hashes hashes
 *
 *  @return encoded dictionary
 */
static NSDictionary *encodeVersionHashes(NSDictionary *hashes)
{
    NSMutableDictionary *newHashes = [NSMutableDictionary dictionary];
    for (NSString *hash in hashes) {
        NSData *h = hashes[hash];
        NSString *s = CDTISStringFromData(h);
        newHashes[hash] = s;
    }
    return [NSDictionary dictionaryWithDictionary:newHashes];
}

- (NSDictionary *)updateObjectModel
{
    NSPersistentStoreCoordinator *psc = self.persistentStoreCoordinator;
    NSManagedObjectModel *mom = psc.managedObjectModel;
    self.objectModel = [[CDTISObjectModel alloc] initWithManagedObjectModel:mom];
    NSDictionary *omd = [self.objectModel dictionary];
    return omd;
}

/*
 *  Update the metaData for CoreData in our own database
 *
 *  @param metadata metadata object
 *  @param docID The docID for the metaData object in our database
 *  @param error error
 *
 *  @return YES/NO
 */
- (BOOL)updateMetadata:(NSDictionary *)metadata withDocID:(NSString *)docID error:(NSError **)error
{
    NSError *err = nil;
    CDTDocumentRevision *oldRev = [self.datastore getDocumentWithId:docID error:&err];
    if (!oldRev) {
        if (error) *error = err;
        CDTLogError(CDTDATASTORE_LOG_CONTEXT, @"%@: %@: no metaData?: %@", CDTISType,
                    self.URL, err);
        return NO;
    }
    CDTDocumentRevision *upRev = [oldRev copy];

    NSDictionary *newHashes = metadata[NSStoreModelVersionHashesKey];
    if (newHashes) {
        NSDictionary *upHashes = @{NSStoreModelVersionHashesKey : encodeVersionHashes(newHashes)};
        NSMutableDictionary *upMeta = [upRev.body[CDTISMetaDataKey] mutableCopy];
        [upMeta addEntriesFromDictionary:upHashes];
        upRev.body[CDTISMetaDataKey] = [NSDictionary dictionaryWithDictionary:upMeta];
    }

    if (CDTISUpdateStoredObjectModel) {
        // check if the hashes have changed
        NSDictionary *oldHashes = [self.objectModel versionHashes];

        if (oldHashes && ![oldHashes isEqualToDictionary:newHashes]) {
            // recreate the object model
            NSDictionary *omd = [self updateObjectModel];
            upRev.body[CDTISObjectModelKey] = omd;
        }
    }

    CDTDocumentRevision *upedRev = [self.datastore updateDocumentFromRevision:upRev error:&err];
    if (!upedRev) {
        if (error) *error = err;
        CDTLogError(CDTDATASTORE_LOG_CONTEXT, @"%@: %@: could not update metadata: %@", CDTISType,
                    self.URL, err);
        return NO;
    }

    return YES;
}

/*
 *  Decode version hashes, which come to us as a dictionary of hex strings
 *  that we convert back into NSData objects.
 *
 *  @param hashes hashes
 *
 *  @return encoded dictionary
 */
static NSDictionary *decodeVersionHashes(NSDictionary *hashes)
{
    NSMutableDictionary *newHashes = [NSMutableDictionary dictionary];
    for (NSString *hash in hashes) {
        NSString *s = hashes[hash];
        NSData *h = CDTISDataFromString(s);
        newHashes[hash] = h;
    }
    return [NSDictionary dictionaryWithDictionary:newHashes];
}

/*
 *  We need to swizzle the hashes if they exist
 *
 *  @param storedMetaData <#storedMetaData description#>
 *
 *  @return <#return value description#>
 */
NSDictionary *decodeCoreDataMeta(NSDictionary *storedMetaData)
{
    NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
    NSDictionary *hashes = storedMetaData[NSStoreModelVersionHashesKey];

    metadata[NSStoreUUIDKey] = storedMetaData[NSStoreUUIDKey];
    metadata[NSStoreTypeKey] = storedMetaData[NSStoreTypeKey];

    // hashes are encoded and need to be inline data
    if (hashes) {
        metadata[NSStoreModelVersionHashesKey] = decodeVersionHashes(hashes);
    }
    return [NSDictionary dictionaryWithDictionary:metadata];
}

/*
 *  Retrieve the CoreData metaData, if we do not have a copy then we create
 *  a new one.
 *
 *  > *Note:* not sure how to reconcile this with multiple devices and the
 *  > remote store.
 *
 *  @param docID The docID for the metaData object in our database
 *  @param error error
 *
 *  @return nil on failure with error
 */
- (NSDictionary *)getMetaDataFromDocID:(NSString *)docID error:(NSError **)error
{
    NSError *err = nil;

    CDTDocumentRevision *rev = [self.datastore getDocumentWithId:docID error:&err];
    if (!rev) {
        NSString *uuid = uniqueID(@"NSStore");
        NSDictionary *metaData = @{NSStoreUUIDKey : uuid, NSStoreTypeKey : [self type]};
        NSDictionary *omd = [self updateObjectModel];

        // store it so we can get it back the next time
        CDTDocumentRevision *newRev = [CDTDocumentRevision revisionWithDocId:CDTISMetaDataDocID];
        newRev.body = [@{ CDTISMetaDataKey : metaData, CDTISObjectModelKey : omd } mutableCopy];

        rev = [self.datastore createDocumentFromRevision:newRev error:&err];
        if (!rev) {
            if (error) *error = err;
            CDTLogError(CDTDATASTORE_LOG_CONTEXT, @"%@: %@: unable to store metaData: %@",
                        CDTISType, self.URL, err);
            return nil;
        }

        return metaData;
    }

    NSDictionary *omd = rev.body[CDTISObjectModelKey];
    self.objectModel = [[CDTISObjectModel alloc] initWithDictionary:omd];

    NSDictionary *storedMetaData = rev.body[CDTISMetaDataKey];
    CDTDocumentRevision *upRev = [rev copy];
    CDTDocumentRevision *upedRev = [self.datastore updateDocumentFromRevision:upRev error:&err];
    if (!upedRev) {
        if (error) *error = err;
        CDTLogError(CDTDATASTORE_LOG_CONTEXT, @"%@: %@: upedRev: %@", CDTISType, self.URL,
                    err);
        return nil;
    }

    NSDictionary *metaData = decodeCoreDataMeta(storedMetaData);
    return metaData;
}

/*
 *  Check that the metadata is still sane.
 *
 *  > *Note*: check is trivial right now
 *
 *  @param metaData metaData
 *  @param error    error
 *
 *  @return YES/NO
 */
- (BOOL)checkMetaData:(NSDictionary *)metaData error:(NSError **)error
{
    NSString *s = metaData[NSStoreTypeKey];
    if (![s isEqualToString:CDTISType]) {
        NSString *e = [NSString localizedStringWithFormat:@"Unexpected store type %@", s];
        if (error) {
            NSDictionary *ui = @{NSLocalizedFailureReasonErrorKey : e};
            *error = [NSError errorWithDomain:CDTISErrorDomain code:CDTISErrorBadPath userInfo:ui];
        }
        return NO;
    }
    // TODO: check hashes
    return YES;
}

/*
 *  Our own setter for metadata
 *  Quote the docs:
 *  > Subclasses must override this property to provide storage and
 *  > persistence for the store metadata.
 *
 *  @param metadata metadata object
 */
- (void)setMetadata:(NSDictionary *)metadata
{
    NSError *err = nil;

    if (![self updateMetadata:metadata withDocID:CDTISMetaDataDocID error:&err]) {
        [NSException raise:CDTISException format:@"update metadata error: %@", err];
    }
    [super setMetadata:metadata];
}

#pragma mark - Replication Creators
- (CDTISReplicator *)replicatorThatPushesToURL:(NSURL *)remoteURL withError:(NSError **)error
{
    NSError *err = nil;
    NSString *clean = [self cleanURL:remoteURL];

    CDTPushReplication *pushRep =
        [CDTPushReplication replicationWithSource:self.datastore target:remoteURL];
    if (!pushRep) {
        CDTLogError(CDTREPLICATION_LOG_CONTEXT, @"%@: %@: Could not create push replication object",
                    CDTISType, clean);
        return nil;
    }

    CDTReplicator *pusher = [self.repFactory oneWay:pushRep error:&err];
    if (!pusher) {
        CDTLogError(CDTREPLICATION_LOG_CONTEXT, @"%@: %@: Could not create replicator for push: %@",
                    CDTISType, clean, err);
        if (error) {
            *error = err;
        }
        return nil;
    }

    return [[CDTISReplicator alloc] initWithDatastore:self.datastore
                                     incrementalStore:self
                                           replicator:pusher];
}

- (CDTISReplicator *)replicatorThatPullsFromURL:(NSURL *)remoteURL withError:(NSError **)error
{
    NSError *err = nil;
    NSString *clean = [self cleanURL:remoteURL];

    CDTPullReplication *pullRep =
        [CDTPullReplication replicationWithSource:remoteURL target:self.datastore];
    if (!pullRep) {
        CDTLogError(CDTREPLICATION_LOG_CONTEXT, @"%@: %@: Could not create pull replication object",
                    CDTISType, clean);
        return nil;
    }

    CDTReplicator *puller = [self.repFactory oneWay:pullRep error:&err];
    if (!puller) {
        CDTLogError(CDTREPLICATION_LOG_CONTEXT, @"%@: %@: Could not create replicator for pull: %@",
                    CDTISType, clean, err);
        if (error) {
            *error = err;
        }
        return nil;
    }

    return [[CDTISReplicator alloc] initWithDatastore:self.datastore
                                     incrementalStore:self
                                           replicator:puller];
}

- (NSManagedObject *)managedObjectForEntityName:(NSString *)name
                                referenceObject:(NSString *)ref
                                        context:(NSManagedObjectContext *)context
{
    NSPersistentStoreCoordinator *psc = self.persistentStoreCoordinator;
    NSManagedObjectModel *mom = [psc managedObjectModel];
    NSEntityDescription *entity = [[mom entitiesByName] objectForKey:name];
    NSManagedObjectID *moid = [self newObjectIDForEntity:entity referenceObject:ref];

    NSManagedObject *mo = [context objectWithID:moid];
    return mo;
}

#pragma mark - required methods
- (BOOL)loadMetadata:(NSError **)error
{
    if (![self initializeDatabase:error]) {
        return NO;
    }
    NSDictionary *metaData = [self getMetaDataFromDocID:CDTISMetaDataDocID error:error];
    if (!metaData) {
        return NO;
    }
    if (![self checkMetaData:metaData error:error]) {
        [NSException raise:CDTISException format:@"failed metaData check"];
    }
    // go directly to super
    [super setMetadata:metaData];

    // this class only exists in iOS
    Class frc = NSClassFromString(@"NSFetchedResultsController");
    if (frc) {
// If there is a cache for this, it is likely stale.
// Sadly, we do not know the name of it, so we blow them all away
#pragma clang diagnostic ignored "-Wundeclared-selector"
        [frc performSelector:@selector(deleteCacheWithName:) withObject:nil];
#pragma clang diagnostic pop
    }

    return YES;
}

/*
 *  Create an array of sort descriptors for the fetch request
 *
 *  @param fetchRequest fetchRequest
 *
 *  @return sort descriptor array
 */
- (NSArray *)sortForFetchRequest:(NSFetchRequest *)fetchRequest
{
    NSMutableArray *sds = [NSMutableArray array];
    for (NSSortDescriptor *sd in [fetchRequest sortDescriptors]) {
        NSString *sel = NSStringFromSelector([sd selector]);
        if (![sel isEqualToString:@"compare:"]) {
            [NSException raise:CDTISException format:@"we do not allow custom compares"];
        }
        [sds addObject:@{ [sd key] : [sd ascending] ? @"asc" : @"desc" }];
    }
    return [NSArray arrayWithArray:sds];
}

/*
 *  Ensure appropriate index is created for fetch request
 *
 *  Note: Queries can include unindexed fields.
 *  Because of this, we *could* do nothing here and get correct results, but we should
 *  try to create an index that will help.  Our strategy will be an index with the following
 *  fields:
 *	- CDTISEntityNameKey
 *  - the first field mentioned in the query
 *  - all fields mentioned in the sort (this is apparently required)
 *
 *  @param fetchRequest fetchRequest
 */
- (void)ensureIndexForFetchRequest:(NSFetchRequest *)fetchRequest
{
    // Index should always include entity name
    NSMutableArray *fields = [NSMutableArray arrayWithObject:CDTISEntityNameKey];

    // If there is a predicate, index should include first field from the predicate
    if ([fetchRequest predicate]) {
        NSPredicate *pred = [fetchRequest predicate];
        while ([pred isKindOfClass:[NSCompoundPredicate class]]) {
            pred = [[(NSCompoundPredicate *)pred subpredicates] firstObject];
        }
        if ([pred isKindOfClass:[NSComparisonPredicate class]]) {
            NSExpression *lhs = [(NSComparisonPredicate *)pred leftExpression];
            if ([lhs expressionType] == NSKeyPathExpressionType) {
                NSString *field = [lhs keyPath];
                if (![fields containsObject:field]) {
                    [fields addObject:field];
                }
            } else if ([lhs expressionType] == NSEvaluatedObjectExpressionType) {
                NSString *field = CDTISIdentifierKey;
                if (![fields containsObject:field]) {
                    [fields addObject:field];
                }
            }
        }
    }

    // Include all fields mentioned in the sort (this is apparently required)
    for (NSSortDescriptor *sd in [fetchRequest sortDescriptors]) {
        NSString *field = [sd key];
        if (![fields containsObject:field]) {
            [fields addObject:field];
        }
    }

    NSString *indexName = [fields componentsJoinedByString:@"_"];
    NSString *result = [self.datastore ensureIndexed:fields withName:indexName];
    if (!result) {
        CDTLogError(CDTDATASTORE_LOG_CONTEXT, @"%@: Error creating index: %@", CDTISType,
                    indexName);
    }
}

/*
 *  Process comparison predicates
 *
 *  The queries currently supported by the backing store are described in the query.md
 *  doc in the doc directory.
 *
 *  @param cp a comparison predicate to be converted to a predicate dictionary
 *
 *  @return predicate dictionary
 */
- (NSDictionary *)comparisonPredicate:(NSComparisonPredicate *)cp
{
    NSExpression *lhs = [cp leftExpression];
    NSExpression *rhs = [cp rightExpression];

    NSString *keyStr = @"";
    if ([lhs expressionType] == NSKeyPathExpressionType) {
        keyStr = [lhs keyPath];
    } else if ([lhs expressionType] == NSEvaluatedObjectExpressionType) {
        keyStr = CDTISIdentifierKey;
    }

    id value = [rhs expressionValueWithObject:nil context:nil];
    if (!keyStr || !value) {
        return nil;
    }

    // Need to munge the objectIDs for CDT queries
    if ([keyStr isEqualToString:CDTISIdentifierKey]) {
        if ([value respondsToSelector:@selector(objectEnumerator)]) {
            NSMutableArray *arr = [NSMutableArray array];
            for (NSManagedObjectID *moid in value) {
                [arr addObject:[[moid URIRepresentation] absoluteString]];
            }
            value = arr;
        } else {
            NSManagedObjectID *moid = (NSManagedObjectID *)value;
            value = [[moid URIRepresentation] absoluteString];
        }
    }

    // process the predicate operator and create the key-value string
    NSDictionary *result = nil;

    NSPredicateOperatorType predType = [cp predicateOperatorType];
    switch (predType) {
        case NSLessThanPredicateOperatorType:
            result = @{ keyStr : @{@"$lt" : value} };
            break;
        case NSLessThanOrEqualToPredicateOperatorType:
            result = @{ keyStr : @{@"$lte" : value} };
            break;
        case NSEqualToPredicateOperatorType:
            result = @{ keyStr : @{@"$eq" : value} };
            break;
        case NSNotEqualToPredicateOperatorType:
            result = @{ keyStr : @{@"$ne" : value} };
            break;
        case NSGreaterThanPredicateOperatorType:
            result = @{ keyStr : @{@"$gt" : value} };
            break;
        case NSGreaterThanOrEqualToPredicateOperatorType:
            result = @{ keyStr : @{@"$gte" : value} };
            break;

        case NSInPredicateOperatorType: {
            if ([value isKindOfClass:[NSString class]]) {
                [NSException raise:CDTISException format:@"Can't do substring matches: %@", value];
                break;
            }
            if ([value respondsToSelector:@selector(objectEnumerator)]) {
                NSMutableArray *arr = [NSMutableArray array];
                for (id el in value) {
                    [arr addObject:el];
                }
                result = @{ keyStr : @{@"$in" : [NSArray arrayWithArray:arr]} };
            }
            break;
        }

        case NSBetweenPredicateOperatorType: {
            if (![value isKindOfClass:[NSArray class]]) {
                [NSException raise:CDTISException format:@"unexpected \"between\" args"];
                break;
            }
            NSArray *between = value;
            if ([between count] != 2) {
                [NSException raise:CDTISException format:@"unexpected \"between\" args"];
                break;
            }

            result = @{
                @"$and" :
                    @[ @{keyStr : @{@"$gte" : between[0]}}, @{keyStr : @{@"$lte" : between[1]}} ]
            };
            break;
        }

        case NSMatchesPredicateOperatorType:
        case NSLikePredicateOperatorType:
        case NSBeginsWithPredicateOperatorType:
        case NSEndsWithPredicateOperatorType:
        case NSCustomSelectorPredicateOperatorType:
        case NSContainsPredicateOperatorType:
            [NSException raise:CDTISException
                        format:@"Predicate with unsupported comparison operator: %@", @(predType)];
            break;

        default:
            [NSException raise:CDTISException
                        format:@"Predicate with unrecognized comparison operator: %@", @(predType)];
            break;
    }

    return result;
}

NSString *kAndOperator = @"$and";
NSString *kOrOperator = @"$or";
NSString *kNorOperator = @"$nor";

- (NSDictionary *)processPredicate:(NSPredicate *)p
{
    if ([p isKindOfClass:[NSCompoundPredicate class]]) {
        NSCompoundPredicate *cp = (NSCompoundPredicate *)p;
        NSCompoundPredicateType predType = [cp compoundPredicateType];

        NSString *opStr = nil;
        switch (predType) {
            case NSAndPredicateType:
                opStr = kAndOperator;
                break;
            case NSOrPredicateType:
                opStr = kOrOperator;
                break;
            case NSNotPredicateType:
            // The $nor operator is not yet supported, so fall thru to exception
            // opStr = kNorOperator;
            // break;
            default:
                [NSException
                     raise:CDTISException
                    format:@"Predicate with unrecognized compound operator: %@", @(predType)];
        }

        NSMutableArray *predArray = [NSMutableArray array];
        for (NSPredicate *sub in [cp subpredicates]) {
            [predArray addObject:[self processPredicate:sub]];
        }
        return @{opStr : (predType == NSNotPredicateType) ? predArray[0] : predArray};

    } else if ([p isKindOfClass:[NSComparisonPredicate class]]) {
        NSComparisonPredicate *cp = (NSComparisonPredicate *)p;
        return [self comparisonPredicate:cp];
    } else if ([p isKindOfClass:[[NSPredicate predicateWithValue:YES] class]]) {
        // Here we need a *simple* predicate that we *know* will be true
        return @{ @"_id" : @{@"$exists" : @YES} };
    } else if ([p isKindOfClass:[[NSPredicate predicateWithValue:NO] class]]) {
        // Here we need a *simple* predicate that we *know* will be false
        return @{ @"_id" : @{@"$exists" : @NO} };
    }

    [NSException raise:CDTISException
                format:@"Unsupported predicate of type: %@", NSStringFromClass([p class])];

    return nil;
}

/*
 *  create a query dictionary for the backing store
 *  > *Note*: the predicates are included in this dictionary
 *
 *  @param fetchRequest fetchRequest
 *
 *  @return return value
 */
- (NSDictionary *)queryForFetchRequest:(NSFetchRequest *)fetchRequest
{
    NSEntityDescription *entity = [fetchRequest entity];
    NSString *entityName = [entity name];
    NSPredicate *entityPredicate =
        [NSPredicate predicateWithFormat:@"%K = %@", CDTISEntityNameKey, entityName];

    NSPredicate *fetchPredicate = [fetchRequest predicate];

    NSPredicate *fullPredicate;
    if (fetchPredicate) {
        // Avoid nested ANDs if possible
        if ([fetchPredicate isKindOfClass:[NSCompoundPredicate class]] &&
            [((NSCompoundPredicate *)fetchPredicate)compoundPredicateType] == NSAndPredicateType) {
            fullPredicate = [NSCompoundPredicate andPredicateWithSubpredicates:[@[
                entityPredicate
            ] arrayByAddingObjectsFromArray:[((NSCompoundPredicate *)fetchPredicate)
                                                    subpredicates]]];
        } else {
            fullPredicate = [NSCompoundPredicate
                andPredicateWithSubpredicates:@[ entityPredicate, fetchPredicate ]];
        }
    } else {
        fullPredicate = entityPredicate;
    }

    NSDictionary *query = [self processPredicate:fullPredicate];

    return query;
}

- (NSArray *)fetchDictionaryResult:(NSFetchRequest *)fetchRequest withResult:(CDTQResultSet *)result
{
    // we only support one grouping
    if ([fetchRequest.propertiesToGroupBy count] > 1) {
        [NSException raise:CDTISException format:@"can only group by 1 property"];
    }

    id groupProp = [fetchRequest.propertiesToGroupBy firstObject];

    // we only support grouping by an existing property, no expressions or
    // aggregates
    if (![groupProp isKindOfClass:[NSPropertyDescription class]]) {
        [NSException raise:CDTISException format:@"can only handle properties for groupings"];
    }

    // use a dictionary so we can track repeats
    NSString *groupKey = [groupProp name];
    NSMutableDictionary __block *group = [NSMutableDictionary dictionary];
    [result enumerateObjectsUsingBlock:^(CDTDocumentRevision *rev, NSUInteger idx, BOOL *stop) {
      id value = rev.body[groupKey];
      NSArray *revList = group[value];
      if (revList) {
          group[value] = [revList arrayByAddingObject:rev];
      } else {
          group[value] = @[ rev ];
      }
    }];

    // get the results ready
    NSMutableArray *results = [NSMutableArray array];

    // for every entry in group, build the dictionary of elements
    for (id g in group) {
        NSArray *ga = group[g];
        CDTDocumentRevision *rev = [ga firstObject];
        NSMutableDictionary *dic = [NSMutableDictionary dictionary];
        for (id prop in fetchRequest.propertiesToFetch) {
            if ([prop isKindOfClass:[NSAttributeDescription class]]) {
                NSAttributeDescription *a = prop;
                dic[a.name] = rev.body[a.name];
            } else if ([prop isKindOfClass:[NSExpressionDescription class]]) {
                NSExpressionDescription *ed = prop;
                NSExpression *e = ed.expression;
                if (e.expressionType != NSFunctionExpressionType) {
                    [NSException raise:CDTISException format:@"expression type is not a function"];
                }
                if (![e.function isEqualToString:@"count:"]) {
                    [NSException raise:CDTISException
                                format:@"count: is the only function currently supported"];
                }
                dic[ed.name] = @([ga count]);
            } else {
                [NSException raise:CDTISException format:@"unsupported property descriptor"];
            }
        }
        [results addObject:[NSDictionary dictionaryWithDictionary:dic]];
    }
    return [NSArray arrayWithArray:results];
}

- (id)executeFetchRequest:(NSFetchRequest *)fetchRequest
              withContext:(NSManagedObjectContext *)context
                    error:(NSError **)error
{
    /*
     *  The document, [Responding to Fetch
     * Requests](https://developer.apple.com/library/ios/documentation/DataManagement/Conceptual/IncrementalStorePG/ImplementationStrategy/ImplementationStrategy.html#//apple_ref/doc/uid/TP40010706-CH2-SW6),
     *  suggests that we get the entity from the fetch request.
     *  Turns out this can be stale so we check it and log it.
     */
    NSEntityDescription *entity = [fetchRequest entity];
    if (badEntityVersion(entity, self.metadata)) oops(@"bad entity mismatch: %@", entity);

    NSDictionary *query = [self queryForFetchRequest:fetchRequest];
    if (!query) {
        if (error) {
            NSDictionary *userInfo = @{
                NSLocalizedFailureReasonErrorKey : @"Error processing predicate for fetch request"
            };
            *error = [NSError errorWithDomain:CDTISErrorDomain
                                         code:CDTISErrorRequestNotSupported
                                     userInfo:userInfo];
        }
        return nil;
    }

    // Get sort descriptors for fetch request
    NSArray *sort = [self sortForFetchRequest:fetchRequest];

    // Create(ensure) and index appropriate for this fetch request
    [self ensureIndexForFetchRequest:fetchRequest];

    CDTQResultSet *result = [self.datastore find:query
                                            skip:fetchRequest.fetchOffset
                                           limit:fetchRequest.fetchLimit
                                          fields:nil
                                            sort:sort];

    NSFetchRequestResultType resultType = [fetchRequest resultType];
    switch (resultType) {
        case NSManagedObjectResultType: {
            NSMutableArray *results = [NSMutableArray array];
            [result
                enumerateObjectsUsingBlock:^(CDTDocumentRevision *rev, NSUInteger idx, BOOL *stop) {
                  NSManagedObjectID *moid =
                      [self newObjectIDForEntity:entity referenceObject:rev.docId];
                  NSManagedObject *mo = [context objectWithID:moid];
                  [results addObject:mo];
                }];
            return [NSArray arrayWithArray:results];
        }

        case NSManagedObjectIDResultType: {
            NSMutableArray *results = [NSMutableArray array];
            [result
                enumerateObjectsUsingBlock:^(CDTDocumentRevision *rev, NSUInteger idx, BOOL *stop) {
                  NSManagedObjectID *moid =
                      [self newObjectIDForEntity:entity referenceObject:rev.docId];
                  [results addObject:moid];
                }];
            return [NSArray arrayWithArray:results];
        }

        case NSDictionaryResultType:
            return [self fetchDictionaryResult:fetchRequest withResult:result];

        case NSCountResultType: {
            NSUInteger count = [result.documentIds count];
            return @[ [NSNumber numberWithUnsignedLong:count] ];
        }

        default:
            break;
    }
    NSString *s =
        [NSString localizedStringWithFormat:@"Unknown fetch request result type: %lu", (unsigned long)resultType];
    if (error) {
        *error = [NSError errorWithDomain:CDTISErrorDomain
                                     code:CDTISErrorResultTypeUnknown
                                 userInfo:@{NSLocalizedFailureReasonErrorKey : s}];
    }
    return nil;
}

- (id)executeSaveRequest:(NSSaveChangesRequest *)saveRequest
             withContext:(NSManagedObjectContext *)context
                   error:(NSError **)error
{
    NSError *err = nil;

    NSSet *insertedObjects = [saveRequest insertedObjects];
    for (NSManagedObject *mo in insertedObjects) {
        if (![self insertManagedObject:mo error:&err]) {
            if (error) *error = err;
            return nil;
        }
    }
    // Todo: Not sure how to deal with errors here
    NSSet *updatedObjects = [saveRequest updatedObjects];
    for (NSManagedObject *mo in updatedObjects) {
        if (![self updateManagedObject:mo error:&err]) {
            if (error) *error = err;
            return nil;
        }
    }
    NSSet *deletedObjects = [saveRequest deletedObjects];
    for (NSManagedObject *mo in deletedObjects) {
        if (![self deleteManagedObject:mo error:&err]) {
            if (error) *error = err;
            return nil;
        }
    }
    NSSet *optLockObjects = [saveRequest lockedObjects];
    for (NSManagedObject *mo in optLockObjects) {
        if (![self optLockManagedObject:mo error:&err]) {
            if (error) *error = err;
            return nil;
        }
    }

    /* quote the docs:
     * > If the save request contains nil values for the
     * > inserted/updated/deleted/locked collections;
     * > you should treat it as a request to save the store metadata.
     */
    if (!insertedObjects && !updatedObjects && !deletedObjects && !optLockObjects) {
        if (![self updateMetadata:[self metadata] withDocID:CDTISMetaDataDocID error:&err]) {
            if (error) *error = err;
            return nil;
        }
    }
    // indicates success
    return @[];
}

#ifdef HAS_NSBatchUpdateRequest
- (NSBatchUpdateResult *)executeBatchUpdateRequest:(NSBatchUpdateRequest *)updateRequest
                                             error:(NSError **)error
{
    NSEntityDescription *entity = [updateRequest entity];
    if (badEntityVersion(entity, self.metadata)) oops(@"bad entity mismatch: %@", entity);

    NSFetchRequest *fetchRequest = [NSFetchRequest new];
    fetchRequest.entity = updateRequest.entity;
    fetchRequest.predicate = updateRequest.predicate;

    NSDictionary *query = [self queryForFetchRequest:fetchRequest];
    if (!query) {
        if (error) {
            NSDictionary *userInfo = @{
                NSLocalizedFailureReasonErrorKey :
                    @"Error processing predicate for batch update request"
            };
            *error = [NSError errorWithDomain:CDTISErrorDomain
                                         code:CDTISErrorRequestNotSupported
                                     userInfo:userInfo];
        }
        return nil;
    }

    // Create(ensure) and index appropriate for this fetch request
    [self ensureIndexForFetchRequest:fetchRequest];

    CDTQResultSet *result = [self.datastore find:query skip:0 limit:0 fields:nil sort:nil];

    // Note: This dictionary is *not* the same dictionary specified in the original request.
    // The keys have all been transformed from attribute names into NSAttributeDescriptions
    NSDictionary *updates = updateRequest.propertiesToUpdate;

    NSMutableDictionary *changes = [NSMutableDictionary dictionary];
    for (NSAttributeDescription *attr in updates) {
        id newValue = [updates[attr] constantValue];
        [changes setValue:newValue forKey:attr.name];
    }

    NSMutableArray *results = [NSMutableArray array];
    NSError __block *updateError;
    [result enumerateObjectsUsingBlock:^(CDTDocumentRevision *rev, NSUInteger idx, BOOL *stop) {
      NSManagedObjectID *moid = [self newObjectIDForEntity:entity referenceObject:rev.docId];

      [self updateDocumentID:rev.docId withChanges:changes entity:entity error:&updateError];
      if (updateError) {
          *stop = YES;
      } else {
          [results addObject:moid];
      }
    }];

    if (updateError) {
        if (error) *error = updateError;
        return nil;
    }

    CDTIS_NSBatchUpdateResult *updateResult = [CDTIS_NSBatchUpdateResult new];
    updateResult.resultType = updateRequest.resultType;

    switch (updateRequest.resultType) {
        case NSUpdatedObjectIDsResultType:  // Return the object IDs of the rows that were
                                            // updated
            updateResult.result = results;
            break;

        case NSUpdatedObjectsCountResultType:  // Return the number of rows that were updated
            updateResult.result = @([results count]);
            break;

        case NSStatusOnlyResultType:  // Just return status
            updateResult.result = @(YES);
            break;

        default:
            break;
    }

    return (NSBatchUpdateResult *)updateResult;
}
#endif // HAS_NSBatchUpdateRequest

- (id)executeRequest:(NSPersistentStoreRequest *)request
         withContext:(NSManagedObjectContext *)context
               error:(NSError **)error
{
    NSPersistentStoreRequestType requestType = [request requestType];

    if (requestType == NSFetchRequestType) {
        NSFetchRequest *fetchRequest = (NSFetchRequest *)request;
        return [self executeFetchRequest:fetchRequest withContext:context error:error];
    }

    if (requestType == NSSaveRequestType) {
        NSSaveChangesRequest *saveRequest = (NSSaveChangesRequest *)request;
        return [self executeSaveRequest:saveRequest withContext:context error:error];
    }

#ifdef HAS_NSBatchUpdateRequest
    if (CDTISSupportBatchUpdates && requestType == NSBatchUpdateRequestType) {
        NSBatchUpdateRequest *updateRequest = (NSBatchUpdateRequest *)request;
        return [self executeBatchUpdateRequest:updateRequest error:error];
    }
#endif

    NSString *s = [NSString localizedStringWithFormat:@"Unknown request type: %@", @(requestType)];
    if (error) {
        *error = [NSError errorWithDomain:CDTISErrorDomain
                                     code:CDTISErrorRequestTypeUnknown
                                 userInfo:@{NSLocalizedFailureReasonErrorKey : s}];
    }
    return nil;
}

- (NSIncrementalStoreNode *)newValuesForObjectWithID:(NSManagedObjectID *)objectID
                                         withContext:(NSManagedObjectContext *)context
                                               error:(NSError **)error
{
    NSError *err = nil;
    NSString *docID = [self stringReferenceObjectForObjectID:objectID];
    uint64_t version = 1;

    NSDictionary *values =
        [self valuesFromDocID:docID withContext:context versionPtr:&version error:&err];

    if (!values && err) {
        if (error) *error = err;
        return nil;
    }

    if (badObjectVersion(objectID, self.metadata)) oops(@"hash mismatch?: %@", objectID);

    NSIncrementalStoreNode *node = [[NSIncrementalStoreNode alloc]
        initWithObjectID:objectID
              withValues:[NSDictionary dictionaryWithDictionary:values]
                 version:version];
    return node;
}

- (id)newValueForRelationship:(NSRelationshipDescription *)relationship
              forObjectWithID:(NSManagedObjectID *)objectID
                  withContext:(NSManagedObjectContext *)context
                        error:(NSError **)error
{
    NSError *err = nil;
    NSString *docID = [self stringReferenceObjectForObjectID:objectID];
    CDTDocumentRevision *rev = [self.datastore getDocumentWithId:docID error:&err];
    if (!rev) {
        if (error) *error = err;
        return nil;
    }

    NSString *name = [relationship name];
    NSInteger type = [self propertyTypeFromDoc:rev.body withName:name];
    NSString *entityName = [self destinationFromDoc:rev.body withName:name];

    switch (type) {
        case CDTISRelationToOneType: {
            NSString *ref = rev.body[name];
            NSManagedObjectID *moid =
                [self decodeRelationFromEntityName:entityName withRef:ref withContext:context];
            if (!moid) {
                return [NSNull null];
            }
            return moid;
        } break;
        case CDTISRelationToManyType: {
            NSMutableArray *moids = [NSMutableArray array];
            NSArray *oids = rev.body[name];
            for (NSString *ref in oids) {
                NSManagedObjectID *moid =
                    [self decodeRelationFromEntityName:entityName withRef:ref withContext:context];
                // if we get nil, don't add it, this should get us an empty array
                if (!moid && oids.count > 1) oops(@"got nil in an oid list");
                if (moid) {
                    [moids addObject:moid];
                }
            }
            return [NSArray arrayWithArray:moids];
        } break;
    }
    return nil;
}

- (NSArray *)obtainPermanentIDsForObjects:(NSArray *)array error:(NSError **)error
{
    NSMutableArray *objectIDs = [NSMutableArray arrayWithCapacity:[array count]];
    for (NSManagedObject *mo in array) {
        NSEntityDescription *e = [mo entity];
        NSManagedObjectID *moid = [self newObjectIDForEntity:e referenceObject:uniqueID(e.name)];

        if (badObjectVersion(moid, self.metadata)) oops(@"hash mismatch?: %@", moid);

        [objectIDs addObject:moid];
    }
    return objectIDs;
}

@end
