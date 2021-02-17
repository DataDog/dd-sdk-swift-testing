# Datadog SDK for Swift testing
> Datadog Test Instrumentation framework for Swift / ObjC

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


## Contributing

Pull requests are welcome. First, open an issue to discuss what you would like to change. For more information, read the [Contributing Guide](CONTRIBUTING.md).

## License

[Apache License, v2.0](LICENSE)

