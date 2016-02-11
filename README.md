# CDTIncrementalStore

[![Version](http://cocoapod-badges.herokuapp.com/v/CDTIncrementalStore/badge.png)](http://cocoadocs.org/docsets/CDTIncrementalStore)
[![Platform](http://cocoapod-badges.herokuapp.com/p/CDTIncrementalStore/badge.png)](http://cocoadocs.org/docsets/CDTIncrementalStore)
[![Build Status](https://travis-ci.org/jimix/CDTIncrementalStore.png?branch=master)](https://travis-ci.org/jimix/CDTIncremetalStore)

**An application can use `CDTIncrementalStore` to target
[Cloudant Sync] as a [persistent store] for a [Core Data] application.**

This document assumes you are familiar with [Core Data].
From the [Apple documents][core data]:
>  The Core Data framework provides generalized and automated
>  solutions to common tasks associated with object life-cycle and
>  object graph management, including persistence.

It is this *"persistence"*, which is provided by the
[Persistent Store], that we wish to add `CDTDatastore` as a backing
store. The [Incremental Store] provides the hooks necessary to do
this.

Thankfully, the user does not need to know these details to exploit
`CDTIncrementalStore` from an application that uses [Core Data].

**Attention:** CDTIncrementalStore is an experimental framework and might be unstable or change frequently, and might be discontinued at short notice.  IBM does not guarantee or imply reliability, serviceability, or function of this framework. This framework is provided "AS IS", without warranty of any kind. IBM shall not be liable for any damages arising out of your use of this framework.

## Getting started

`CDTIncrementalStore` is available through [CocoaPods], to install it
add the following line to your `Podfile`:

```ruby
pod "CDTIncrementalStore"
```

### Using in a Swift app

`CDTIncremetalStore` uses `CDTDatastore` and both are usable from
Swift out of the box with a few small quirks. Install as per the
instructions above, and import `CDTIncrementalStore.h` into your
[bridging header].

> ***Note***: There may be additional Swift considerations when using
> the CDTDatastore directly, please see [cloudant sync] documentation.

## Core Data

If your application is not already using Core Data, see the
[Core Data] documentation for the proper setup for a persistent store.
This generally involves the initialization of a persistent store
coordinator followed by a request to add a persistent store of a
specific type to the persistent store coordinator.

This setup is commonly done in the application delegate, but could be
done elsewhere.  The common persistent store implementation is the
`NSSQLiteStoreType`, which uses [SQLite] for persistent storage.  To use
`CDTDatastore` for [Core Data] persistent storage, specify
`[CDTIncrementalStore type]` as the persistent store type, as follows:

```objc
#import <CDTIncrementalStore.h>

NSURL *storeURL = [docsDir URLByAppendingPathComponent:@"mystore"];
NSPersistentStoreCoordinator *psc = ...
[psc addPersistentStoreWithType:[CDTIncrementalStore type]
                  configuration:nil
                            URL:storeURL
                        options:nil
                          error:&error])];
```

The pathname of the storeURL may specify a suffix, e.g. `".cdtis"`,
but none is required and no significance is given to the suffix.
However, to avoid confusion, you should probably either change or remove
the standard `".sqlite"` suffix when converting from a sqlite store to
a `CDTIncrementalStore`.

At this point you can use [Core Data] normally and your changes will
be saved in the local `CDTDatastore` image.


## Supported Features

The [Cloudant Sync] persistent store for [Core Data] supports the following features:

- Save, fetch, update, and delete of Managed Objects to the on-device CDTDatastore.
- Batch update requests
- Asynchronous fetch operations
- Schema migration

## Unsupported Features

The following features of [Core Data] are currently not supported by
the `CDTIncrementalStore`:

* Predicates on string attributes using BEGINSWITH, ENDSWITH, LIKE, or MATCHES
* Compound predicates using the NOT operator
* Predicates on relationship attributes.

## Example Application

An example application with detailed instructions on how to convert
a CoreData application to use CDTIncrementalStore can be found in this
[GitHub repo][gitrecipe].
The application is based on [Apple's iPhoneCoreDataRecipes][recipe] and
illustrates standard CoreData interactions with CDTIncrementalStore as
well as replication to a remote Cloudant datastore.

## Contributing to the project

See [CONTRIBUTING](CONTRIBUTING.md).

## License

See [LICENSE](LICENSE)

## Other Documents
These can be found in the [docs](docs) directory.

1. [Replication](docs/replication.md)
1. [Portability](docs/portability.md)
1. [Internals](docs/internals.md)

<!-- refs -->

[cloudant sync]: https://github.com/cloudant/CDTDatastore "Cloudant Sync iOS datastore library"

[cocoapods]: http://cocoapods.org "CocoaPods"

[bridging header]: https://developer.apple.com/library/ios/documentation/swift/conceptual/buildingcocoaapps/MixandMatch.html "Bridging Headers"

[core data]: https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/CoreData/cdProgrammingGuide.html "Introduction to Core Data Programming Guide"

[persistent store]: https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/CoreData/Articles/cdPersistentStores.html "Persistent Store Features"

[incremental store]: https://developer.apple.com/library/mac/documentation/DataManagement/Conceptual/IncrementalStorePG/Introduction/Introduction.html "About Incremental Stores"

[recipe]: https://developer.apple.com/library/ios/samplecode/iPhoneCoreDataRecipes/Introduction/Intro.html "iPhoneCoreDataRecipes"

[gitrecipe]: https://github.com/mkistler/CDTIS_iPhoneCoreDataRecipes "GitHub Repo of CDTIS_iPhoneCoreDataRecipes"


<!--  LocalWords:  CDTIncrementalStore Cloudant CDTDatastore Podfile
 -->
<!--  LocalWords:  CocoaPods CDTQueryResult SequenceType func SQLite
 -->
<!--  LocalWords:  NSFastGenerator NSSQLiteStoreType objc NSURL psc
 -->
<!--  LocalWords:  storeURL docsDir URLByAppendingPathComponent iOS
 -->
<!--  LocalWords:  mystore NSString myType addPersistentStoreWithType
 -->
<!--  LocalWords:  NSPersistentStoreCoordinator cloudant sqlite
 -->
<!--  LocalWords:  BEGINSWITH ENDSWITH iPhoneCoreDataRecipes
 -->
<!--  LocalWords:  gitrecipe datastore cocoapods
 -->
