# Running Tests

## Prerequisites

To run the tests against the live Azure OpenAI Chat Completions API you need:

- An Azure OpenAI resource with a deployed chat model.
- The endpoint URL of the resource (e.g. `https://<resource-name>.openai.azure.com/openai/v1`).
- Either a bearer token or an API key.

To obtain these, refer to the [Ballerina Azure OpenAI Chat Connector](https://github.com/ballerina-platform/module-ballerinax-azure.openai.chat/blob/main/ballerina/Module.md).

## Test Environments

There are two test environments for running the `azure.openai.chat` connector tests. The default environment uses a mock server for the Azure OpenAI Chat Completions API. The other environment is the actual Azure OpenAI API.

You can run the tests in either of these environments, and each has its own compatible set of tests.

| Test Groups | Environment                                              |
|-------------|----------------------------------------------------------|
| mock_tests  | Mock server for Azure OpenAI API (Default Environment)   |
| live_tests  | Azure OpenAI API                                         |

> The `utils_tests` group contains pure unit tests for the generated query/URI
> serialization helpers and runs in both environments.

## Running Tests in the Mock Server

To execute the tests on the mock server, ensure that the `isLiveServer` environment variable is either set to `false` or left unset before initiating the tests.

This environment variable can be configured within the `Config.toml` file located in the `tests` directory or specified as an environment variable.

### Using a `Config.toml` File

Create a `Config.toml` file in the `tests` directory with the following content:

```toml
isLiveServer = false
```

### Using Environment Variables

Alternatively, you can set the environment variable directly.

For Linux or macOS:

```bash
export IS_LIVE_SERVER=false
```

For Windows:

```bash
setx IS_LIVE_SERVER false
```

Then, run the following command to execute the tests:

```bash
./gradlew clean test
```

## Running Tests Against the Azure OpenAI Live API

### Using a `Config.toml` File

Create a `Config.toml` file in the `tests` directory and add your authentication credentials:

```toml
isLiveServer = true
token = "<your-azure-openai-api-token>"
serviceUrl = "<your-azure-openai-endpoint-url>"
```

Alternatively, to test the API key authentication path against a live server, provide `apiKey` instead of (or in addition to) `token`.

### Using Environment Variables

Alternatively, you can set your authentication credentials as environment variables.

For Linux or macOS:

```bash
export IS_LIVE_SERVER=true
export AZURE_OPENAI_TOKEN="<your-azure-openai-api-token>"
export AZURE_OPENAI_SERVICE_URL="<your-azure-openai-endpoint-url>"
# Optional: to exercise the API key authentication path.
export AZURE_OPENAI_API_KEY="<your-azure-openai-api-key>"
```

For Windows:

```bash
setx IS_LIVE_SERVER true
setx AZURE_OPENAI_TOKEN <your-azure-openai-api-token>
setx AZURE_OPENAI_SERVICE_URL <your-azure-openai-endpoint-url>
setx AZURE_OPENAI_API_KEY <your-azure-openai-api-key>
```

Then, run the following command to execute the tests:

```bash
./gradlew clean test
```
