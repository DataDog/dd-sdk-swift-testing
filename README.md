# Datadog SDK for Swift testing

This SDK is part of Datadog's [CI Visibility](https://docs.datadoghq.com/continuous_integration/) product, currently in beta.

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
```

Depending on your CI service, you must also set the environment variables to be read from the test executions. See `DDEnvironmentValues.swift` for details of your specific CI.

For example for Bitrise, they should be:

```shell
BITRISE_SOURCE_DIR=$(BITRISE_SOURCE_DIR)
BITRISE_APP_TITLE=$(BITRISE_APP_TITLE)
BITRISE_BUILD_SLUG=$(BITRISE_BUILD_SLUG)
BITRISE_BUILD_NUMBER=$(BITRISE_BUILD_NUMBER)
BITRISE_BUILD_URL=$(BITRISE_BUILD_URL)
```

A more comprehensive and updated documentation can be found at [CI Visibility - Swift Tests](https://docs.datadoghq.com/continuous_integration/setup_tests/swift) 


## UITests

For UITests, both the test target and the application running from the UITests must link with the framework, environment variables only need to be set in the test target, since the framework automatically injects these values to the application.

## Disabling Auto Instrumentation

The framework automatically tries to capture the maximum information, but for some situations or tests it can be counter-productive. You can disable some of the autoinstrumentation for all the tests, by setting the following environment variables. 

>Boolean variables can use any of: "1","0","true","false", "YES", "NO"
>String List variables accepts a list of elements separated by "," or ";"


```shell
DD_DISABLE_NETWORK_INSTRUMENTATION # Disables all network instrumentation (Boolean)
DD_DISABLE_STDOUT_INSTRUMENTATION # Disables all stdout instrumentation (Boolean)
DD_DISABLE_STDERR_INSTRUMENTATION # Disables all stderr instrumentation (Boolean)
```

### Network Auto Instrumentation

For Network autoinstrumentation there are other settings that you can configure

```shell
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


## Adding custom tags

### Using environment variables

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
let tracer = DDInstrumentationControl.openTelemetryTracer
tracer?.activeSpan?.setAttribute(key: "OTelTag", value: "OTelValue")
```

Test target needs to link explicitly with OpenTelemetry

## Contributing

Pull requests are welcome. First, open an issue to discuss what you would like to change. For more information, read the [Contributing Guide](CONTRIBUTING.md).

## License

[Apache License, v2.0](LICENSE)

