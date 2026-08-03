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

import ballerina/io;
import ballerinax/azure.openai.chat;

configurable string token = ?;
configurable string serviceUrl = ?;

public function main() returns error? {
    final chat:Client azureOpenAIChat = check new ({
        auth: {
            token
        }
    }, serviceUrl);

    // Create a chat completion request
    chat:ChatCompletionsBody request = {
        model: "gpt-4o-mini",
        messages: [
            {role: "system", "content": "You are a helpful assistant."},
            {role: "user", "content": "Explain what the Ballerina programming language is in one sentence."}
        ]
    };

    chat:InlineResponse200 response = check azureOpenAIChat->/chat/completions.post(request);

    // Extract the response content
    record {string id; chat:OpenAICreateChatCompletionResponseChoices[] choices; int created; string model; string system_fingerprint?; "chat.completion" 'object; chat:OpenAICompletionUsage usage?; chat:InlineResponse200PromptFilterResults[] prompt_filter_results?;} chatResponse = check response.ensureType();

    if chatResponse.choices.length() > 0 {
        string? content = chatResponse.choices[0].message.content;
        if content is string {
            io:println("Response: " + content);
        }
    }

    // Print usage information
    chat:OpenAICompletionUsage? usage = chatResponse.usage;
    if usage is chat:OpenAICompletionUsage {
        io:println("Tokens used - Prompt: " + usage.prompt_tokens.toString() +
            ", Completion: " + usage.completion_tokens.toString() +
            ", Total: " + usage.total_tokens.toString());
    }
}
