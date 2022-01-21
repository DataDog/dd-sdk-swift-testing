# Datadog SDK for Swift testing

This SDK is part of Datadog's [CI Visibility](https://docs.datadoghq.com/continuous_integration/) product.
A more comprehensive and updated documentation can be found at [CI Visibility - Swift Tests](https://docs.datadoghq.com/continuous_integration/setup_tests/swift) 

## Getting Started

Link your test targets with the framework (you can use SPM or direct linking )

Set the following environment variables to the Test Action:

```sh
DD_TEST_RUNNER=1
DATADOG_CLIENT_TOKEN=<your current client token>
SRCROOT=$(SRCROOT)
```

You my want to set other environment variables to

```shell
DD_ENV=<The environment you want to report>
DD_SERVICE=<The name of the service you want to report>
DD_SITE=<The Datadog site to upload results to>
```

Depending on your CI service, you must also set the environment variables to be read from the test executions. See [CI Providers Environment Variables](https://docs.datadoghq.com/continuous_integration/setup_tests/swift/?tab=swiftpackagemanager#ci-provider-environment-variables) `DDEnvironmentValues.swift` for details of your specific CI.


## UITests

For UITests, both the test target and the application running from the UITests must link with the framework, environment variables only need to be set in the test target, since the framework automatically injects these values to the application.

## Auto Instrumentation


>Boolean variables can use any of: "1","0","true","false", "YES", "NO"
>String List variables accepts a list of elements separated by "," or ";"

### Enabling Auto Instrumentation

```shell
DD_ENABLE_STDOUT_INSTRUMENTATION # Captures messages written to `stdout` (e.g `print()` ) and reports them as Logs. (Implies charges for Logs product) (Boolean)
DD_ENABLE_STDERR_INSTRUMENTATION #  Captures messages written to `stderr` (e.g `NSLog()`, UITest steps ) and reports them as Logs. (Implies charges for Logs product) (Boolean)
```

### Configuring Network Auto Instrumentation

For Network autoinstrumentation there are other settings that you can configure

```shell
DD_DISABLE_NETWORK_INSTRUMENTATION # Disables all network instrumentation (Boolean)
DD_DISABLE_HEADERS_INJECTION # Disables all injection of tracing headers (Boolean)
DD_INSTRUMENTATION_EXTRA_HEADERS # Specific extra headers that you want the tool to log (String List)
DD_EXCLUDED_URLS # Urls that you dont want to log or inject headers into(String List)
DD_ENABLE_RECORD_PAYLOAD # It enables reporting a subset of the payloads in requests and responses (Boolean)
DD_MAX_PAYLOAD_SIZE # It sets the maximum size that will be reported from the payload, 1024 by default (Integer)
```

You can also disable or enable specific autoinstrumentation in some of the tests from Swift or Objective-C by importing the module `DatadogSDKTesting` and using the class: `DDInstrumentationControl`.

### Disable crash handling

You should never need to do it, but in some ***very specific cases*** you may want to disable crash reporting for tests (e.g. you want to test your own crash handler, ... ):
```shell
DD_DISABLE_CRASH_HANDLER # Disables crash handling and reporting. (Boolean) WARNING, read note below
```
> You must know that if you disable crash reporting, crashing tests wont be reported to the backend and wont appear as a failure. If you really, really need to do this for any of your tests, run it as a totally separated target, so you dont disable it for the rest of the tests


## Custom tags

### Environment variables

You can use `DD_TAGS` environment variable. It must contain pairs of `key:tag` separated by spaces. For example:

```shell
DDTAGS=tag-key-0:tag-value-0 tag-key-1:tag-value-1
```

If one of your values starts with the `$` character, it will be replaced with the environment variable with the same name if it exists, example:

```shell
DDTAGS=home:$HOME
```
It also supports replacing a environment variable at the beggining of the value if contains non env variables supported characters (`a-z`,  `A-Z` or `_`):

```shell
FOO = BAR
DD_TAGS=key1:$FOO-v1 // expected: key1:BAR-v1
```

### Using OpenTelemetry (only for Swift)

Datadog swift testing framework uses [OpenTelemetry](https://github.com/open-telemetry/opentelemetry-swift) as the tracing technology under the hood. You can access the OpenTelemetry tracer using `DDInstrumentationControl.openTelemetryTracer` and can use any OpenTelemetry api. For example, for adding a tag/attribute

```swift
import DatadogSDKTesting
import OpenTelemetryApi

let tracer = DDInstrumentationControl.openTelemetryTracer as? Tracer
let span = tracer?.spanBuilder(spanName: "ChildSpan").startSpan()
span?.setAttribute(key: "OTTag2", value: "OTValue2")
span?.end()
```

The test target needs to link explicitly with `opentelemetry-swift`.

## Using Info.plist for configuration

Alternatively to setting environment variables, all configuration values can be provided by adding them to the `Info.plist` file of the Test bundle (not the App bundle). If the same setting is set both in an environment variable and in the `Info.plist` file, the environment variable takes precedence.

## Manual testing API

If you use XCTests with your Swift projects, the `DatadogSDKTesting` framework automatically instruments them and sends the results to the Datadog backend. If you don't use XCTest, you can instead use the Swift/Objective-C manual testing API, which also reports test results to the backend.

The API is based around three concepts: *test sessions*, *test suites*, and *tests*.

### Test sessions

A test session includes the whole process of running the tests, from when the user launches the testing process until the last test ends and results are reported. The test session also includes starting the environment and the process where the tests run.

To start a test session, call `DDTestSession.start()` and pass the name of the module or bundle to test.

When all your tests have finished, call `session.end()`, which forces the library to send all remaining test results to the backend.

### Test Suites

A test suite comprises a set of tests that share common functionality. They can share a common initialization and teardown, and can also share some variables.

Create test suites in the test session by calling `session.suiteStart()` and passing the name of the test suite.

Call `suite.end()` when all the related tests in the suite have finished their execution.

### Tests

Each test runs inside a suite and must end in one of these three statuses: `pass`, `fail`, or `skip`. A test can optionally have additional information like attributes or error information.

Create tests in a suite by calling `suite.testStart()` and passing the name of the test. When a test ends, one of the predefined statuses must be set.

### API interface

```swift
class DDTestSession {
    // Starts the session.
    // - Parameters:
    //   - bundleName: Name of the module or bundle to test.
    //   - startTime: Optional. The time the session started.
    static func start(bundleName: String, startTime: Date? = nil) -> DDTestSession
    //
    // Ends the session.
    // - Parameters:
    //   - endTime: Optional. The time the session ended.
    func end(endTime: Date? = nil)
    // Adds a tag/attribute to the test session. Any number of tags can be added.
    // - Parameters:
    //   - key: The name of the tag. If a tag with the same name already exists,
    //     its value will be replaced by the new value.
    //   - value: The value of the tag. Can be a number or a string.
    func setTag(key: String, value: Any)
    //
    // Starts a suite in this session.
    // - Parameters:
    //   - name: Name of the suite.
    //   - startTime: Optional. The time the suite started.
    func suiteStart(name: String, startTime: Date: Date? = nil) -> DDTestSuite
}
    //
public class DDTestSuite : NSObject {
    // Ends the test suite.
    // - Parameters:
    //   - endTime: Optional. The time the suite ended.
    func end(endTime: Date? = nil)
    // Adds a tag/attribute to the test suite. Any number of tags can be added.
    // - Parameters:
    //   - key: The name of the tag. If a tag with the same name already exists,
    //     its value will be replaced by the new value.
    //   - value: The value of the tag. Can be a number or a string.
    func setTag(key: String, value: Any)
    //
    // Starts a test in this suite.
    // - Parameters:
    //   - name: Name of the test.
    //   - startTime: Optional. The time the test started.
    func testStart(name: String, startTime: Date: Date? = nil) -> DDTest
}
    //
public class DDTest : NSObject {
    // Adds a tag/attribute to the test. Any number of tags can be added.
    // - Parameters:
    //   - key: The name of the tag. If a tag with the same name already exists,
    //     its value will be replaced by the new value.
    //   - value: The value of the tag. Can be a number or a string.
    func setTag(key: String, value: Any)
    //
    // Adds error information to the test. Only one errorInfo can be reported by a test.
    // - Parameters:
    //   - type: The type of error to be reported.
    //   - message: The message associated with the error.
    //   - callstack: Optional. The callstack associated with the error.
    func setErrorInfo(type: String, message: String, callstack: String? = nil)
    //
    // Ends the test.
    // - Parameters:
    //   - status: The status reported for this test.
    //   - endTime: Optional. The time the test ended.
    func end(status: DDTestStatus, endTime: Date: Date? = nil)
}
    //
// Possible statuses reported by a test:
enum DDTestStatus {
  // The test passed.
  case pass
  //
  //Test test failed.
  case fail
  //
  //The test was skipped.
  case skip
}
```

### Code example

The following code represents a simple usage of the API:

```swift
import DatadogSDKTesting
let session = DDTestSession.start(bundleName: "ManualSession")
let suite1 = session.suiteStart(name: "ManualSuite 1")
let test1 = suite1.testStart(name: "Test 1")
test1.setTag(key: "key", value: "value")
test1.end(status: .pass)
let test2 = suite1.testStart(name: "Test 2")
test2.SetErrorInfo(type: "Error Type", message: "Error message", callstack: "Optional callstack")
test2.end(test: test2, status: .fail)
suite1.end()
let suite2 = session.suiteStart(name: "ManualSuite 2")
..
..
session.end()
```

Always call `session.end()` at the end so that all the test info is flushed to Datadog.

## Contributing

Pull requests are welcome. First, open an issue to discuss what you would like to change. For more information, read the [Contributing Guide](CONTRIBUTING.md).

## License

[Apache License, v2.0](LICENSE)

