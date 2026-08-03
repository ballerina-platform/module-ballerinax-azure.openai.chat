// Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/data.jsondata;
import ballerina/http;
import ballerina/os;
import ballerina/test;

configurable boolean isLiveServer = os:getEnv("IS_LIVE_SERVER") == "true";
configurable string token = isLiveServer ? os:getEnv("AZURE_OPENAI_TOKEN") : "test";
configurable string apiKey = isLiveServer ? os:getEnv("AZURE_OPENAI_API_KEY") : "test";
configurable string serviceUrl = isLiveServer ? os:getEnv("AZURE_OPENAI_SERVICE_URL") : "http://localhost:9090";

// Deployment names exercised by the live suite. Defaults to the single deployment
// the mock understands; set this in `Config.toml` (or via `BAL_CONFIG_*`) to run the
// live suite against a wider matrix, for example
// `liveModels = ["gpt-4o", "gpt-4.1", "gpt-35-turbo"]`. Reasoning models such as the
// gpt-5 family can also be listed here: `temperature`/`top_p`/`n` are no longer sent
// unless the caller sets them (see sanitation item 11).
configurable string[] liveModels = ["gpt-4o-mini"];

final string mockServiceUrl = "http://localhost:9090";
const AzureAIFoundryModelsApiVersion apiVersion = "v1";

// Model families the mock recognises. `gpt-5*` are reasoning models and reject
// `temperature`/`top_p`; the rest accept them.
final readonly & string[] reasoningModels = ["gpt-5", "gpt-5-mini", "gpt-5-nano"];
final readonly & string[] samplingModels = ["gpt-4o", "gpt-4o-mini", "gpt-4.1", "gpt-35-turbo"];

// Client authenticated with a bearer token (default for both mock and live runs).
final Client azureOpenAIChat = check initClient();

isolated function initClient() returns Client|error {
    if isLiveServer {
        return new ({auth: {token}}, serviceUrl);
    }
    return new ({auth: {token}}, mockServiceUrl);
}

@test:Config {
    groups: ["live_tests", "mock_tests"]
}
isolated function testSimpleChatCompletion() returns error? {
    ChatCompletionsBody request = {
        model: "gpt-4o-mini",
        messages: [
            {role: "system", "content": "You are a helpful assistant."},
            {role: "user", "content": "This is a test message"}
        ]
    };

    InlineResponse200 response = check azureOpenAIChat->/chat/completions.post(request, api\-version = apiVersion);

    ChatCompletionResponse completion = check response.ensureType();
    test:assertTrue(completion.id.length() > 0, "Expected a chat completion id");
    test:assertTrue(completion.model.length() > 0, "Expected a model in the completion response");
    test:assertEquals(completion.'object, "chat.completion");
    test:assertTrue(completion.choices.length() > 0, "Expected at least one completion choice");

    OpenAICreateChatCompletionResponseChoices choice = completion.choices[0];
    test:assertEquals(choice.finish_reason, "stop");
    test:assertEquals(choice.message.role, "assistant");
    test:assertTrue(choice.message.content is string && (<string>choice.message.content).length() > 0,
            "Expected non-empty assistant content");
}

@test:Config {
    groups: ["mock_tests"]
}
isolated function testClientInitWithApiKeyAuth() returns error? {
    // Exercises the API key authentication branch of the client initialization.
    // `ApiKeysConfig` carries only the `api-key` field, so an API key alone is a
    // complete credential.
    Client apiKeyClient = check new ({auth: {api\-key: apiKey}}, mockServiceUrl);

    ChatCompletionsBody request = {
        model: "gpt-4o-mini",
        messages: [{role: "user", "content": "Ping"}]
    };

    InlineResponse200 response = check apiKeyClient->/chat/completions.post(request, api\-version = apiVersion);

    ChatCompletionResponse completion = check response.ensureType();
    test:assertEquals(completion.choices.length(), 1);
}

@test:Config {
    groups: ["mock_tests"]
}
isolated function testApiKeyAuthSendsOnlyApiKeyHeader() returns error? {
    // The mock rejects a request that carries both `api-key` and `authorization`,
    // and reports the scheme it saw in `system_fingerprint`. Reaching a successful
    // response therefore proves the client sent the `api-key` header alone.
    Client apiKeyClient = check new ({auth: {api\-key: apiKey}}, mockServiceUrl);

    ChatCompletionsBody request = {
        model: "gpt-4o-mini",
        messages: [{role: "user", "content": "Ping"}],
        user: "auth-probe"
    };

    InlineResponse200 response = check apiKeyClient->/chat/completions.post(request, api\-version = apiVersion);

    ChatCompletionResponse completion = check response.ensureType();
    test:assertEquals(completion.system_fingerprint, AUTH_SCHEME_API_KEY,
            "Expected the api-key header to be the only credential sent");
}

@test:Config {
    groups: ["mock_tests"]
}
isolated function testBearerTokenAuthSendsOnlyAuthorizationHeader() returns error? {
    // The bearer token branch must send `Authorization: Bearer ...` and no `api-key`.
    ChatCompletionsBody request = {
        model: "gpt-4o-mini",
        messages: [{role: "user", "content": "Ping"}],
        user: "auth-probe"
    };

    InlineResponse200 response = check azureOpenAIChat->/chat/completions.post(request, api\-version = apiVersion);

    ChatCompletionResponse completion = check response.ensureType();
    test:assertEquals(completion.system_fingerprint, AUTH_SCHEME_BEARER,
            "Expected the Authorization header to be the only credential sent");
}

@test:Config {
    groups: ["mock_tests"]
}
isolated function testBlankApiKeyIsRejected() returns error? {
    // A blank credential must not be accepted silently. This is the shape the
    // connector previously forced on callers that had only one of the two headers.
    Client blankKeyClient = check new ({auth: {api\-key: ""}}, mockServiceUrl);

    ChatCompletionsBody request = {
        model: "gpt-4o-mini",
        messages: [{role: "user", "content": "Ping"}]
    };

    InlineResponse200|error response = blankKeyClient->/chat/completions.post(request, api\-version = apiVersion);

    test:assertTrue(response is error, "Expected a blank api-key to be rejected");
}

@test:Config {
    groups: ["live_tests", "mock_tests"]
}
isolated function testChatCompletionWithOptionalParams() returns error? {
    // Validates the nullable-field handling: temperature, top_p, max_completion_tokens,
    // presence_penalty and frequency_penalty accept concrete values.
    ChatCompletionsBody request = {
        model: "gpt-4o-mini",
        messages: [{role: "user", "content": "Tell me a joke"}],
        temperature: 0.7,
        top_p: 0.9,
        max_completion_tokens: 256,
        presence_penalty: 0.5,
        frequency_penalty: 0.5,
        stop: ["\n"],
        user: "test-user-1234"
    };

    InlineResponse200 response = check azureOpenAIChat->/chat/completions.post(request, api\-version = apiVersion);

    ChatCompletionResponse completion = check response.ensureType();
    test:assertEquals(completion.choices[0].finish_reason, "stop");
}

@test:Config {
    groups: ["mock_tests"]
}
isolated function testChatCompletionWithNullableFieldsAsNil() returns error? {
    // These request fields are typed `T?` and must accept nil.
    ChatCompletionsBody request = {
        model: "gpt-4o-mini",
        messages: [{role: "user", "content": "Hello"}],
        temperature: (),
        top_p: (),
        max_completion_tokens: (),
        presence_penalty: (),
        frequency_penalty: (),
        logit_bias: (),
        seed: ()
    };

    InlineResponse200 response = check azureOpenAIChat->/chat/completions.post(request, api\-version = apiVersion);

    ChatCompletionResponse completion = check response.ensureType();
    test:assertTrue(completion.choices.length() > 0);
    // When log probabilities are not requested, the choice's `logprobs` is null.
    // This exercises the nullable `logprobs` field.
    test:assertTrue(completion.choices[0].logprobs is (), "Expected null logprobs when not requested");
    OpenAICompletionUsage? usage = completion.usage;
    test:assertTrue(usage is OpenAICompletionUsage, "Expected usage statistics");
    if usage is OpenAICompletionUsage {
        test:assertEquals(usage.total_tokens, 24);
    }
}

@test:Config {
    groups: ["mock_tests"]
}
isolated function testChatCompletionWithToolCalls() returns error? {
    ChatCompletionsBody request = {
        model: "gpt-4o-mini",
        messages: [{role: "user", "content": "What is the weather in Colombo?"}],
        tools: [
            {
                'type: "function",
                'function: {
                    name: "get_current_weather",
                    description: "Get the current weather for a location",
                    parameters: {}
                }
            }
        ],
        tool_choice: "auto"
    };

    InlineResponse200 response = check azureOpenAIChat->/chat/completions.post(request, api\-version = apiVersion);

    ChatCompletionResponse completion = check response.ensureType();
    OpenAICreateChatCompletionResponseChoices choice = completion.choices[0];
    test:assertEquals(choice.finish_reason, "tool_calls");

    OpenAIChatCompletionMessageToolCallsItem? toolCalls = choice.message.tool_calls;
    test:assertTrue(toolCalls is OpenAIChatCompletionMessageToolCallsItem, "Expected tool calls in the response");
    if toolCalls is OpenAIChatCompletionMessageToolCallsItem {
        test:assertEquals(toolCalls.length(), 1);
        OpenAIChatCompletionMessageToolCall|OpenAIChatCompletionMessageCustomToolCall toolCall = toolCalls[0];
        test:assertTrue(toolCall is OpenAIChatCompletionMessageToolCall, "Expected a function tool call");
        if toolCall is OpenAIChatCompletionMessageToolCall {
            test:assertEquals(toolCall.'function.name, "get_current_weather");
        }
    }
}

@test:Config {
    groups: ["mock_tests"]
}
isolated function testChatCompletionWithMultipleChoices() returns error? {
    ChatCompletionsBody request = {
        model: "gpt-4o-mini",
        messages: [{role: "user", "content": "Give me three greetings"}],
        n: 3
    };

    InlineResponse200 response = check azureOpenAIChat->/chat/completions.post(request, api\-version = apiVersion);

    ChatCompletionResponse completion = check response.ensureType();
    test:assertEquals(completion.choices.length(), 3);
    test:assertEquals(completion.choices[2].index, 2);
}

@test:Config {
    groups: ["mock_tests"]
}
isolated function testChatCompletionWithPreviewApiVersion() returns error? {
    // `api-version` accepts the `preview` value in addition to `v1`.
    ChatCompletionsBody request = {
        model: "gpt-4o-mini",
        messages: [{role: "user", "content": "Hello preview channel"}]
    };

    InlineResponse200 response = check azureOpenAIChat->/chat/completions.post(request, api\-version = "preview");

    ChatCompletionResponse completion = check response.ensureType();
    test:assertEquals(completion.'object, "chat.completion");
}

@test:Config {
    groups: ["mock_tests"]
}
isolated function testChatCompletionWithEmptyMessagesReturnsError() {
    ChatCompletionsBody request = {
        model: "gpt-4o-mini",
        messages: []
    };

    InlineResponse200|error response = azureOpenAIChat->/chat/completions.post(request, api\-version = apiVersion);

    test:assertTrue(response is error, "Expected an error for an empty messages array");
    if response is http:ClientRequestError {
        test:assertEquals(response.detail().statusCode, 400);
    }
}

// Models that accept the sampling parameters must still work when the caller sets
// them, and reasoning models must reject them.
//
// Note that `temperature` and `top_p` carry `default: 1` in the specification, so
// the tool generates them as required-with-default fields that go on the wire on
// every request. Reasoning models therefore currently fail regardless of what the
// caller sets, which is why the gpt-5 family is not exercised for success here.
@test:Config {
    groups: ["mock_tests"]
}
isolated function testSamplingParametersBehaviourByModelFamily() returns error? {
    foreach string model in samplingModels {
        ChatCompletionsBody request = {
            model,
            messages: [{role: "user", "content": "Ping"}],
            temperature: 0.5,
            top_p: 0.9
        };

        InlineResponse200 response = check azureOpenAIChat->/chat/completions.post(request, api\-version = apiVersion);

        ChatCompletionResponse completion = check response.ensureType();
        test:assertEquals(completion.model, model);
    }

    foreach string model in reasoningModels {
        ChatCompletionsBody request = {
            model,
            messages: [{role: "user", "content": "Ping"}],
            temperature: 0.5
        };

        InlineResponse200|error response = azureOpenAIChat->/chat/completions.post(request, api\-version = apiVersion);

        test:assertTrue(response is error,
                string `Expected '${model}' to reject an explicitly set temperature`);
    }
}

// Runs a completion against every deployment named in `liveModels`, so the live
// suite can cover more than one model without hard-coding deployment names.
@test:Config {
    groups: ["live_tests"]
}
isolated function testChatCompletionAcrossLiveModels() returns error? {
    foreach string model in liveModels {
        ChatCompletionsBody request = {
            model,
            messages: [{role: "user", "content": "Reply with the single word: ok"}]
        };

        InlineResponse200 response = check azureOpenAIChat->/chat/completions.post(request, api\-version = apiVersion);

        ChatCompletionResponse completion = check response.ensureType();
        test:assertTrue(completion.choices.length() > 0,
                string `Expected a completion choice from '${model}'`);
    }
}

// Guards the sanitation that removed `default:` from the request-body sampling
// parameters. A parameter the caller never set must not appear in the serialised
// body: the reasoning models (o-series, gpt-5 family) reject the *presence* of
// these keys, so a defaulted-but-always-present field made those models
// uncallable. `jsondata:toJson` is the exact serialiser used by `client.bal`.
@test:Config {
    groups: ["mock_tests"]
}
isolated function testUnsetRequestParametersAreNotSerialized() returns error? {
    ChatCompletionsBody request = {
        model: "gpt-5",
        messages: [{role: "user", "content": "This is a test message"}]
    };

    map<json> body = check jsondata:toJson(request).ensureType();
    foreach string paramName in ["temperature", "top_p", "n"] {
        test:assertFalse(body.hasKey(paramName),
                msg = string `Expected '${paramName}' to be omitted when the caller does not set it`);
    }

    // An explicitly set parameter must still be serialised.
    request.temperature = 0.2;
    map<json> bodyWithTemperature = check jsondata:toJson(request).ensureType();
    test:assertEquals(bodyWithTemperature["temperature"], 0.2d,
            msg = "Expected an explicitly set temperature to be sent");
}
