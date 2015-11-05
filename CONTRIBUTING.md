# Contributing to CDTIncrementalStore

<!--
Note: GitHub considers this document to be "the guidelines for contributing to this repository" and links to it at various points in the process flow (e.g. when opening a new issue).
This document can and should contain other types of useful information but the guidelines should be the primary content.
-->

## Coding guidelines

Contributions to CDTIncrementalStore should follow the [project coding guidelines](doc/style-guide.md) contained in the [docs](docs) directory.
The project is set up so that developers can use [ClangFormat](clangformat) automatically format code to conform to these guidelines.
The guidelines describe how to install and use ClangFormat.

[clangformat]: https://github.com/travisjeffery/ClangFormat-Xcode

## Documentation

All code changes should include comments describing the design, assumptions, dependencies, and non-obvious aspects of the implementation.
Hopefully the existing code provides a good example of appropriate code comments.
If necessary, make the appropriate updates in the README.md and other documentation files.

All external interfaces should be fully documented using [appledoc][appledoc] style comments.
Here's a
[good introduction to the format](http://www.cocoanetics.com/2011/11/amazing-apple-like-documentation/).
[Cocoadocs][cocoadocs] automatically generates and publishes [this documentation][CDTIncrementalStoredocs] when an new version of the CocoaPod is published.

[appledoc]: http://gentlebytes.com/appledoc/
[cocoadocs]: http://cocoadocs.org/
[CDTIncrementalStoredocs]: http://cocoadocs.org/docsets/CDTIncrementalStore/0.1.3/

## Contributing your changes

We follow a fairly standard procedure:

* Fork the CDTIncrementalStore repo into your own account, clone to your machine.
* Create a branch with your changes on (`git checkout -b my-new-feature`)
  * Make sure to update the CHANGELOG and CONTRIBUTORS before sending a PR.
  * All contributions must include tests.
  * Try to follow the style of the code around the code you
    are adding -- the project contains source code from a few places with
    slightly differing styles.
* Commit your changes (`git commit -am 'Add some feature'`)
* Push to the branch (`git push origin my-new-feature`)
* Issue a PR for this to our repo.


## Setting up your environment

You have probably got most of these set up already, but starting from scratch
you'll need:

* Xcode
* Xcode command line tools
* Cocoapods
* Homebrew (optional, but useful)
* xcpretty (optional)

First, download Xcode from the app store or [ADC][adc].

When this is installed, install the command line tools. The simplest way is:

```bash
xcode-select --install
```

Install homebrew using the [guide on the homebrew site][homebrew].

Install cocoapods using the [guide on their site][cpinstall].

Finally, if you want to build from the command line, install [xcpretty][xcpretty],
which makes the `xcodebuild` output more readable.

It's a gem:

```bash
sudo gem install xcpretty
```

For documentation, install [appledoc][appledoc].

[adc]: http://developer.apple.com/
[xcpretty]: https://github.com/mneorr/XCPretty
[homebrew]: http://brew.sh
[cpinstall]: http://guides.cocoapods.org/using/index.html

## Getting started with the project

CDTIncrementalStore comes with a suite of tests for both iOS and OSX.
These are located in the CDTIncrementalStoreTest directory.
The recommended approach to development is to build and use a workspace in the
tests directory so that changes can be directly verified with these test suites.

The Cocoapods tool will create the appropriate workspace and set up all the dependencies for the test suite.


```bash
# Close the Xcode workspace before doing this!

cd CDTIncrementalStoreTest
pod install
```

Open up `CDTIncrementalStoreTest.xcworkspace`.

```bash
open CDTIncrementalStoreTest.xcworkspace
```

This workspace is where you should do all your work.
`CDTIncrementalStore.xcworkspace` contains:

* The test project `CDTIncrementalStoreTests`, with targets
	* CDTIS_iOSTests
	* CDTIS_OSXTests
	* CDTIS_iOSAppTests
	* CDTIS_OSXAppTests
* `Pods` where the test and example app dependencies are built (including
  CDTDatastore itself).
* Within `Pods` is `Development Pods`, where you will find the `CDTIncrementalStore`
source code.
Following the conventions of `CDTDatastore`, the source code is within the `Classes\common` folder.

As you edit the source code in the `CDTIncrementalStore` group, the Pods project will
be rebuilt when you run the tests as it references the code in `Classes`.

At this point, run the tests from Tests project to make sure you're setup correctly.

## Running the tests

To run the tests from Xcode, change the Scheme to either `CDTIS_iOSTests` or `CDTIS_OSXTests` using the dropdown in the top left.
Then pick the simulated or real device on which to run the tests.
Once you have selected the test scheme and device, `CMD-u` should run the tests on the specified device.

The remote tests use a local instance of CouchDB to test DB push and pull operations.
You can set up a local CouchDB server with the following commands (assuming you already have homebrew setup):

```
brew install couchdb
launchctl load /usr/local/opt/couchdb/homebrew.mxcl.couchdb.plist
```

You can also run the tests from the command line:

```
xcodebuild -workspace CDTIncrementalStoreTest/CDTIncrementalStoreTest.xcworkspace -scheme CDTIS_iOSTests test | xcpretty -c
xcodebuild -workspace CDTIncrementalStoreTest/CDTIncrementalStoreTest.xcworkspace -scheme CDTIS_OSXTests test | xcpretty -c
```

To test on a specific device you need to specify `-destination`:

```
# iOS
xcodebuild -workspace CDTIncrementalStoreTest/CDTIncrementalStoreTest.xcworkspace -scheme CDTIS_iOSTests -destination 'platform=iOS Simulator,OS=latest,name=iPhone 4S' test | xcpretty -c

# Mac OS X
xcodebuild -workspace CDTIncrementalStoreTest/CDTIncrementalStoreTest.xcworkspace -scheme CDTIS_OSXTests -destination 'platform=OS X' test | xcpretty -c
```
Skip the `| xcpretty` if you didn't install that.

Xcodebuild references:

* [man page](https://developer.apple.com/library/mac/documentation/Darwin/Reference/ManPages/man1/xcodebuild.1.html)


## Testing with a real app

In addition to running the unit tests you may want to test using a real app.
A good choice is [CDTIS_iPhoneCoreDataRecipes app][cdtisrecipe], which is
is based on [Apple's iPhoneCoreDataRecipes][recipe] CoreData sample app but
is converted to use CDTIncrementalStore.

To use this app for testing, you should modify the Podfile to pull the CDTIncrementalStore sources from your development branch in github.
Here's an example Podfile statement to pull the `dev` branch from the CDTIncrementalStore git repo for testing:

```
pod "CDTIncrementalStore", :git => 'https://github.com/cloudant-labs/CDTIncrementalStore.git', :branch => 'dev'

```

[recipe]: https://developer.apple.com/library/ios/samplecode/iPhoneCoreDataRecipes/Introduction/Intro.html "iPhoneCoreDataRecipes"

[cdtisrecipe]: https://github.com/mkistler/CDTIS_iPhoneCoreDataRecipes "GitHub Repo of CDTIS_iPhoneCoreDataRecipes"

## Making the documentation

Use `rake docs` to build the docs and install into Xcode.


