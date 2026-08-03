# Examples

The `ballerinax/azure.openai.chat` connector provides practical examples illustrating usage in various scenarios. Explore these [examples](https://github.com/ballerina-platform/module-ballerinax-azure.openai.chat/tree/main/examples), covering use cases for the Azure OpenAI Chat Completions API.

1. [Chat completion](https://github.com/ballerina-platform/module-ballerinax-azure.openai.chat/tree/main/examples/chat-completion) - Create a basic chat completion with a system prompt and user message.
2. [Function calling](https://github.com/ballerina-platform/module-ballerinax-azure.openai.chat/tree/main/examples/function-calling) - Use function/tool calling to extend the model's capabilities with custom functions.

## Prerequisites

1. Generate an API key as described in the [setup guide](https://central.ballerina.io/ballerinax/azure.openai.chat/latest#setup-guide).

2. For each example, create a `Config.toml` file in the related directory. Here's an example of how your `Config.toml` file should look:

    ```toml
    token = "<Azure OpenAI Access Token>"
    serviceUrl = "https://<resource-name>.openai.azure.com/openai/v1"
    ```

    `serviceUrl` must include the `/openai/v1` base path; the endpoint shown in the Azure portal is the resource
    root and returns `404` on its own.

## Running an example

Execute the following commands to build an example from the source:

* To build an example:

    ```bash
    bal build
    ```

* To run an example:

    ```bash
    bal run
    ```

## Building the examples with the local module

**Warning**: Due to the absence of support for reading local repositories for single Ballerina files, the Bala of the module is manually written to the central repository as a workaround. Consequently, the bash script may modify your local Ballerina repositories.

Execute the following commands to build all the examples against the changes you have made to the module locally:

* To build all the examples:

    ```bash
    ./build.sh build
    ```

* To run all the examples:

    ```bash
    ./build.sh run
    ```
