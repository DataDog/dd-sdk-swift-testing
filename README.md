# Datadog SDK for Swift Test Optimization

This SDK is part of Datadog's [Test Optimization](https://docs.datadoghq.com/tests/) product.
A more comprehensive and updated documentation can be found at [Test Optimization - Swift](https://docs.datadoghq.com/tests/setup/swift/).

## Getting Started

Link your test targets with the framework (you can use SPM or direct linking )

Set the following environment variables to the Test Action:

```sh
DD_TEST_RUNNER=1
DD_API_KEY=<your current api key>
SRCROOT=$(SRCROOT)
```

You my want to set other environment variables to

```shell
DD_ENV=<The environment you want to report>
DD_SERVICE=<The name of the service you want to report>
DD_SITE=<The Datadog site to upload results to>
```

Depending on your CI service, you must also set the environment variables to be read from the test executions. See [CI Providers Environment Variables](https://docs.datadoghq.com/tests/setup/swift/#ci-provider-environment-variables) for details of your specific CI.

## UI Tests

For UI Tests, this SDK will automatically integrate with the RUM SDK in your application. Environment variables only need to be set in the test target, since the framework automatically injects these values to the application.

If your don't use RUM SDK, this SDK can be linked with the Application too. Don't ship your app with this SDK, it should be linked only to the test builds.

## Auto Instrumentation

>Boolean variables can use any of: "1","0","true","false", "YES", "NO"
>String List variables accepts a list of elements separated by "," or ";"

### Enabling Logs Auto Instrumentation

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
DD_TAGS="tag-key-0:tag-value-0 tag-key-1:tag-value-1"
```

If one of your values starts with the `$` character, it will be replaced with the environment variable with the same name if it exists, example:

```shell
DD_TAGS="home:$HOME"
```
It also supports replacing a environment variable at the beggining of the value if contains non env variables supported characters (`a-z`,  `A-Z` or `_`):

```shell
FOO = BAR
DD_TAGS="key1:$FOO-v1" # expected: key1:BAR-v1
```

### Inside test code

You can add custom tags inside your test methods. The static property `DDTest.current` will return the current test instance if called inside the test method scope.

```swift
// Somewhere inside the test method
DDTest.current!.setTag(key: "key1", value: "value1")
```

## Using OpenTelemetry (only for Swift)

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

## Contributing

Pull requests are welcome. First, open an issue to discuss what you would like to change. For more information, read the [Contributing Guide](CONTRIBUTING.md).

## License

[Apache License, v2.0](LICENSE)

