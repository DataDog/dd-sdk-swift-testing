# Release management

These are the necessary steps to release a version of the framework:

1. Go to release Github Action and run it on the `main` branch with the version number you want to release [Release Action](https://github.com/DataDog/dd-sdk-swift-testing/actions/workflows/createRelease.yml)
2. Wait till action will do a build and a new **draft** release.
3. Validate Performance:
   1. Go to https://github.com/DataDog/test-environment/actions/workflows/dd-sdk-swift-testing-tests.yml and manually trigger the GitHub Action.
   2. Wait for the workflow to finish and make sure it passes.
   3. Go to this [dashboard](https://app.datadoghq.com/dashboard/dyh-bqt-twa/tracers-performance-overhead-and-correctness-on-oss-projects?tpl_var_tracer_repository=dd-sdk-swift-testing) and check the `Max performance overhead (%)` graph. Max performance overhead shouldn’t have increased *significantly* on the latest data point. Keep in mind that values are noisy, so use your own judgement to decide whether an increase is something to worry about. 
4. Go to the release page, and un-check **This is a pre-release**.
