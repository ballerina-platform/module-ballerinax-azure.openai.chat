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

import ballerina/test;

// Sends a request that uses every message role Azure supports (developer/system/
// user/assistant/tool/function) along with the full set of optional request
// fields (tools, functions, response format, prediction, modality, audio,
// security context, etc.). This validates that the generated request types model
// real-world payloads correctly. `ChatCompletionRequestMessage` is an open
// record, so role-specific fields (content, tool_calls, name, tool_call_id) are
// supplied as additional fields.
@test:Config {
    groups: ["mock_tests"]
}
isolated function testRequestWithAllMessageAndContentTypes() returns error? {
    OpenAIChatCompletionRequestMessage[] messages = [
        {role: "developer", "content": "Be concise."},
        {role: "system", "content": "You are helpful."},
        {
            role: "user",
            "content": [
                {"type": "text", "text": "Describe this image and audio."},
                {"type": "image_url", "image_url": {"url": "https://example.com/img.png", "detail": "high"}},
                {"type": "input_audio", "input_audio": {"data": "BASE64AUDIO", "format": "wav"}}
            ]
        },
        {
            role: "assistant",
            "content": "I can help with that.",
            "refusal": (),
            "tool_calls": [{"id": "call_1", "type": "function", "function": {"name": "lookup", "arguments": "{}"}}],
            "function_call": {"name": "lookup", "arguments": "{}"}
        },
        {role: "tool", "content": "tool output", "tool_call_id": "call_1"},
        {role: "function", "name": "lookup", "content": "function output"}
    ];

    ChatCompletionsBody request = {
        model: "gpt-4o-mini",
        messages,
        reasoning_effort: "high",
        max_completion_tokens: 1024,
        logprobs: true,
        top_logprobs: 5,
        modalities: ["text", "audio"],
        prediction: {'type: "content", content: "predicted text"},
        audio: {voice: "alloy", format: "mp3"},
        parallel_tool_calls: true,
        response_format: {'type: "json_schema"},
        seed: 42,
        stream_options: {include_usage: true},
        tools: [{'type: "function", 'function: {name: "lookup", description: "Look things up", parameters: {}, strict: false}}],
        tool_choice: {'type: "function", 'function: {name: "lookup"}},
        function_call: {name: "lookup"},
        functions: [{name: "lookup", description: "deprecated", parameters: {}}],
        store: true,
        metadata: {"team": "platform"},
        logit_bias: {"1234": 50},
        user: "end-user-1",
        user_security_context: {application_name: "app", end_user_id: "u"}
    };

    InlineResponse200 response = check azureOpenAIChat->/chat/completions.post(request, api\-version = apiVersion);
    ChatCompletionResponse completion = check response.ensureType();
    test:assertTrue(completion.choices.length() > 0);
}

// Binds a fully populated Azure response so every optional response-side type is
// exercised: prompt/choice content filters, logprobs, tool & function calls, and
// audio output.
@test:Config {
    groups: ["mock_tests"]
}
isolated function testRichResponseBinding() returns error? {
    ChatCompletionsBody request = {
        model: "gpt-4o-mini",
        messages: [{role: "user", "content": "Give me everything"}],
        user: "rich-response"
    };

    InlineResponse200 response = check azureOpenAIChat->/chat/completions.post(request, api\-version = apiVersion);
    ChatCompletionResponse completion = check response.ensureType();

    InlineResponse200PromptFilterResults[]? promptFilters = completion.prompt_filter_results;
    test:assertTrue(promptFilters is InlineResponse200PromptFilterResults[], "Expected prompt filter results");

    OpenAICreateChatCompletionResponseChoices choice = completion.choices[0];
    test:assertEquals(choice.finish_reason, "tool_calls");
    test:assertTrue(choice.content_filter_results is AzureContentFilterResultForChoice, "Expected choice content filters");
    // `logprobs` is nullable; the rich response populates it, so narrow before use.
    OpenAICreateChatCompletionResponseChoicesLogprobs? logprobs = choice.logprobs;
    test:assertTrue(logprobs is OpenAICreateChatCompletionResponseChoicesLogprobs, "Expected logprobs");
    if logprobs is OpenAICreateChatCompletionResponseChoicesLogprobs {
        test:assertTrue(logprobs.content is OpenAIChatCompletionTokenLogprob[], "Expected logprobs content");
    }

    OpenAIChatCompletionResponseMessage message = choice.message;
    test:assertTrue(message.tool_calls is OpenAIChatCompletionMessageToolCallsItem, "Expected tool calls");
    test:assertTrue(message.function_call is OpenAIChatCompletionResponseMessageFunctionCall, "Expected function call");
    test:assertTrue(message.audio is OpenAIChatCompletionResponseMessageAudio, "Expected audio output");

    OpenAICompletionUsage? usage = completion.usage;
    test:assertTrue(usage is OpenAICompletionUsage, "Expected usage");
    if usage is OpenAICompletionUsage {
        test:assertTrue(usage.prompt_tokens_details is OpenAICompletionUsagePromptTokensDetails);
        test:assertTrue(usage.completion_tokens_details is OpenAICompletionUsageCompletionTokensDetails);
        test:assertEquals(usage.total_tokens, 50);
    }
}
