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

## Contributing

Pull requests are welcome. First, open an issue to discuss what you would like to change. For more information, read the [Contributing Guide](CONTRIBUTING.md).

## License

[Apache License, v2.0](LICENSE)
