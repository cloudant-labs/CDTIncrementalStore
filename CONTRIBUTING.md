# Contributing to CDTIncrementalStore

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

[adc]: http://developer.apple.com/
[xcpretty]: https://github.com/mneorr/XCPretty
[homebrew]: http://brew.sh
[cpinstall]: http://guides.cocoapods.org/using/index.html

## Coding guidelines

The coding guidelines for CDTIncrementalStore are 
CDTIncrementalStore has 

Contributions to CDTIncrementalStore should follow the [project coding guidelines](doc/style-guide.md) contained in the [docs](docs) directory.
There's information in the guidelines documentation on using [ClangFormat](clangformat) to automatically use the right format.

[clangformat]: https://github.com/travisjeffery/ClangFormat-Xcode

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

At this point, run both the tests from the Tests project and the example app
to make sure you're setup correctly. To run the tests, change the Scheme to
either `CDTIS_iOSTests` or `CDTIS_OSXTests` using the dropdown in the top left. It'll
probably be the `Project` scheme to start with. Once you've changed the
scheme, `CMD-u` should run the tests on your preferred platform.

### Documentation

Install [appledocs][appledocs].

Use `rake docs` to build the docs and install into Xcode.

Here's a
[good introduction to the format](http://www.cocoanetics.com/2011/11/amazing-apple-like-documentation/).

[appledocs]: http://gentlebytes.com/appledoc/

### Running the tests

You can run the tests from Xcode using the standard test launching techniques (e.g. CMD-U to run all tests in the selected scheme).

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

Xcodebuild references:

* [man page](https://developer.apple.com/library/mac/documentation/Darwin/Reference/ManPages/man1/xcodebuild.1.html)

Skip the `| xcpretty` if you didn't install that.

## Contributing your changes

We follow a fairly standard proceedure:

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
