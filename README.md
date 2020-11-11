# Datadog SDK for Swift testing
> Datadog Test Instrumentation framework for Swift / ObjC

## Getting Started

Link your test targets with the framework (you can use SPM or direct linking )

Set the following environment variables to the Test Action:

```sh
DD_TEST_RUNNER=1
DATADOG_CLIENT_TOKEN=<your current client token>
```

You my want to set other environment variables to

```shell
DD_ENV=<The environment you want to report>
DD_SERVICE=<The name of the service you want to report>
```

Depending on your CI service, you must also set the environment variables to be read from the test executions. See `DDEnvironmentValues.swift` for details of your specific CI.

For example for Bitrise, they should be:

```shell
GIT_REPOSITORY_URL=$(GIT_REPOSITORY_URL)
BITRISE_GIT_COMMIT=$(BITRISE_GIT_COMMIT)
BITRISE_SOURCE_DIR=$(BITRISE_SOURCE_DIR)
BITRISE_TRIGGERED_WORKFLOW_ID=$(BITRISE_TRIGGERED_WORKFLOW_ID)
BITRISE_BUILD_NUMBER=$(BITRISE_BUILD_NUMBER)
BITRISE_BUILD_URL=$(BITRISE_BUILD_URL)
BITRISE_APP_URL=$(BITRISE_APP_URL)
BITRISE_GIT_BRANCH=$(BITRISE_GIT_BRANCH)
BITRISEIO_GIT_BRANCH_DEST=$(BITRISEIO_GIT_BRANCH_DEST)
BITRISE_GIT_TAG=$(BITRISE_GIT_TAG)
GIT_CLONE_COMMIT_HASH=$(GIT_CLONE_COMMIT_HASH)
```
## Disabling Auto Instrumentation

The framework automatically tries to capture the maximum information, but for some situations or tests it can be counter-productive. You can disable some of the autoinstrumentation for all the tests, by setting the following environment variables

```shell
DD_DISABLE_NETWORK_INSTRUMENTATION # Disables all network instrumentation
DD_DISABLE_STDOUT_INSTRUMENTATION # Disables all stdout instrumentation
DD_DISABLE_STDERR_INSTRUMENTATION # Disables all stderr instrumentation
```

### Network Auto Instrumentation

For Network autoinstrumentation there are other settings that you can configure

```shell
DD_DISABLE_HEADERS_INJECTION # Disables all injection of tracing headers
DD_INSTRUMENTATION_EXTRA_HEADERS # Specific extra headers that you want the tool to log
DD_EXCLUDED_URLS # Urls that you dont want to log or inject headers into
DD_ENABLE_RECORD_PAYLOAD # It enables reporting a subset (512 bytes) of the payloads in requests and responses
```

You can also disable or enable specific autoinstrumentation in some of the tests from Swift or Objective-C by importing the module `DatadogSDKTesting` and using the class: `DDInstrumentationControl`.


## Contributing

Pull requests are welcome. First, open an issue to discuss what you would like to change. For more information, read the [Contributing Guide](CONTRIBUTING.md).

## License

[Apache License, v2.0](LICENSE)
