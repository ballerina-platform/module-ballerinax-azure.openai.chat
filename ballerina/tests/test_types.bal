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

// `InlineResponse200` is a union of the non-streaming and streaming response
// shapes. These helper records mirror each member so tests can bind the response
// to a concrete, field-addressable type via `ensureType`.
type ChatCompletionResponse record {
    string id;
    OpenAICreateChatCompletionResponseChoices[] choices;
    int created;
    string model;
    string system_fingerprint?;
    "chat.completion" 'object;
    OpenAICompletionUsage usage?;
    InlineResponse200PromptFilterResults[] prompt_filter_results?;
};

type StreamingChatCompletionResponse record {
    string id;
    OpenAICreateChatCompletionStreamResponseChoices[] choices;
    int created;
    string model;
    string system_fingerprint?;
    "chat.completion.chunk" 'object;
    OpenAICompletionUsage usage?;
    OpenAIChatCompletionStreamResponseDelta delta?;
    AzureContentFilterResultForChoice content_filter_results?;
};

// Builds a representative value of every response-side generated type. Azure
// populates these only in specific situations (content filtering, log
// probabilities, audio output, tool/function calls), so constructing them here
// verifies the generated record shapes are usable and keeps them covered.
@test:Config {
    groups: ["mock_tests"]
}
isolated function testResponseModelTypesAreConstructable() {
    // Content filtering result hierarchy.
    AzureContentFilterSeverityResult severity = {filtered: false, severity: "safe"};
    AzureContentFilterDetectionResult detected = {filtered: false, detected: false};
    AzureContentFilterBlocklistResultDetails blocklistDetail = {filtered: false, id: "blocklist-1"};
    AzureContentFilterBlocklistResult blocklist = {filtered: false, details: [blocklistDetail]};
    AzureContentFilterCustomTopicResultDetails topicDetail = {detected: false, id: "topic-1"};
    AzureContentFilterCustomTopicResult topics = {filtered: false, details: [topicDetail]};
    AzureContentFilterResultForChoiceProtectedMaterialCodeCitation citationInfo = {URL: "https://lib", license: "MIT"};
    AzureContentFilterResultForChoiceProtectedMaterialCode withCitation =
        {filtered: false, detected: false, citation: citationInfo};
    AzureContentFilterCompletionTextSpan span = {completion_start_offset: 0, completion_end_offset: 5};
    AzureContentFilterCompletionTextSpanDetectionResult withSpans =
        {filtered: false, detected: false, details: [span]};
    AzureContentFilterResultForChoice choiceResults = {
        sexual: severity,
        profanity: detected,
        custom_blocklists: blocklist,
        custom_topics: topics,
        protected_material_text: detected,
        protected_material_code: withCitation,
        ungrounded_material: withSpans
    };

    test:assertEquals(severity.severity, "safe");
    test:assertEquals(blocklistDetail.id, "blocklist-1");
    test:assertEquals(topics.details, [topicDetail]);
    test:assertEquals(withCitation.citation?.license, "MIT");
    test:assertEquals(withSpans.details[0].completion_end_offset, 5);
    test:assertTrue(choiceResults.sexual is AzureContentFilterSeverityResult);
    test:assertTrue(choiceResults.ungrounded_material is AzureContentFilterCompletionTextSpanDetectionResult);

    // Prompt filter result hierarchy.
    AzureContentFilterResultForPromptContentFilterResults promptFilterCategories =
        {sexual: severity, jailbreak: detected, indirect_attack: detected};
    AzureContentFilterResultForPrompt promptResults =
        {prompt_index: 0, content_filter_results: promptFilterCategories};
    InlineResponse200PromptFilterResults promptFilter =
        {prompt_index: 0, content_filter_results: promptResults};
    test:assertEquals(promptFilter.prompt_index, 0);

    // Token log-probability types.
    OpenAIChatCompletionTokenLogprobTopLogprobs topLogprob = {token: "Hi", logprob: -0.2d, bytes: [72, 105]};
    OpenAIChatCompletionTokenLogprob tokenLogprob =
        {token: "Hello", logprob: -0.1d, bytes: [72, 101], top_logprobs: [topLogprob]};
    OpenAICreateChatCompletionResponseChoicesLogprobs logprobs = {content: [tokenLogprob], refusal: ()};
    test:assertEquals(logprobs.content, [tokenLogprob]);

    // Usage breakdown types.
    OpenAICompletionUsagePromptTokensDetails promptDetails = {audio_tokens: 2, cached_tokens: 4};
    OpenAICompletionUsageCompletionTokensDetails completionDetails =
        {accepted_prediction_tokens: 1, audio_tokens: 3, reasoning_tokens: 5, rejected_prediction_tokens: 2};
    OpenAICompletionUsage usage = {
        prompt_tokens: 20,
        completion_tokens: 30,
        total_tokens: 50,
        prompt_tokens_details: promptDetails,
        completion_tokens_details: completionDetails
    };
    test:assertEquals(usage.total_tokens, 50);

    // Response message types.
    OpenAIChatCompletionResponseMessageFunctionCall functionCall = {name: "legacy_fn", arguments: "{}"};
    OpenAIChatCompletionResponseMessageAudio audio =
        {id: "audio_1", expires_at: 1723095000, data: "BASE64", transcript: "spoken"};
    OpenAIChatCompletionMessageToolCall toolCall =
        {id: "call_1", 'type: "function", 'function: {name: "lookup", arguments: "{}"}};
    OpenAIChatCompletionMessageCustomToolCall customToolCall =
        {id: "call_2", 'type: "custom", custom: {name: "run", input: "echo"}};
    OpenAIChatCompletionResponseMessageAnnotations urlAnnotation =
        {'type: "url_citation", url_citation: {end_index: 5, start_index: 0, url: "https://x", title: "Doc"}};
    OpenAIChatCompletionResponseMessage message = {
        role: "assistant",
        refusal: (),
        content: "answer",
        tool_calls: [toolCall, customToolCall],
        annotations: [urlAnnotation],
        function_call: functionCall,
        audio: audio
    };
    OpenAICreateChatCompletionResponseChoices choice =
        {finish_reason: "stop", index: 0, message: message, logprobs: logprobs, content_filter_results: choiceResults};
    test:assertEquals(choice.message.role, "assistant");
    test:assertEquals(choice.message.tool_calls, [toolCall, customToolCall]);

    // Azure user security context (request-side helper type).
    AzureUserSecurityContext securityContext =
        {application_name: "app", end_user_id: "u", end_user_tenant_id: "t", source_ip: "1.2.3.4"};
    test:assertEquals(securityContext.application_name, "app");
}

// Constructs the streaming response types that are not produced through the
// single non-streaming mock path, keeping those generated types compiled and
// verified. Also confirms `InlineResponse200` accepts the streaming member.
@test:Config {
    groups: ["mock_tests"]
}
isolated function testStreamingResponseTypes() {
    OpenAIChatCompletionMessageToolCallChunk toolCallChunk =
        {index: 0, id: "call_1", 'type: "function", 'function: {name: "lookup", arguments: "{}"}};
    OpenAIChatCompletionStreamResponseDelta delta = {
        role: "assistant",
        content: "partial",
        refusal: (),
        tool_calls: [toolCallChunk],
        function_call: {name: "lookup", arguments: "{}"}
    };
    OpenAICreateChatCompletionStreamResponseChoices streamChoice =
        {index: 0, finish_reason: (), delta: delta};

    StreamingChatCompletionResponse streamChunk = {
        id: "chatcmpl-stream-1",
        choices: [streamChoice],
        created: 1723091498,
        model: "gpt-4o-mini",
        system_fingerprint: "fp_stream",
        'object: "chat.completion.chunk"
    };
    test:assertEquals(streamChunk.choices[0].delta.role, "assistant");

    // `InlineResponse200` is a union that also accepts the streaming shape.
    InlineResponse200 streamResponse = streamChunk;
    test:assertTrue(streamResponse is StreamingChatCompletionResponse);
}
