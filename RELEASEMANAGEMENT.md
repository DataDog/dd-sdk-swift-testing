# Release management

These are the necessary steps to release a version of the framework:

1. In a terminal window, move to the root folder of `dd-sdk-swift-testing` project
2. Confirm you are in `main` branch
3. Run `make bump` and write the version number you want to release
4. Commit and push the change to the repository
5. In Github create a new release: [https://github.com/DataDog/dd-sdk-swift-testing/releases/new](https://github.com/DataDog/dd-sdk-swift-testing/releases/new) and select `main` branch
6. Be sure to check box for **This is a pre-release**.
7. Validate that frameworks builds correctly, passes the tests, and generates `DatadogSDKTesting.zip` in the release assets.
8. Validate Performance:
   1. Go to https://github.com/DataDog/test-environment/actions/workflows/dd-sdk-swift-testing-tests.yml and manually trigger the GitHub Action.
   2. Wait for the workflow to finish and make sure it passes.
   3. Go to this [dashboard](https://app.datadoghq.com/dashboard/dyh-bqt-twa/tracers-performance-overhead-and-correctness-on-oss-projects?tpl_var_tracer_repository=dd-sdk-swift-testing) and check the `Max performance overhead (%)` graph. Max performance overhead shouldn’t have increased *significantly* on the latest data point. Keep in mind that values are noisy, so use your own judgement to decide whether an increase is something to worry about. 
9. Go to the release page, and un-check **This is a pre-release**.
10. Upload Cocoapods version: `pod trunk push DatadogSDKTesting.podspec`
