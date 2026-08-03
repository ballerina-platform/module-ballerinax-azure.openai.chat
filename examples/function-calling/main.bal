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

    // Define a function tool for the model to use
    chat:OpenAIChatCompletionTool weatherTool = {
        'type: "function",
        'function: {
            name: "get_current_weather",
            description: "Get the current weather in a given location",
            parameters: {
                "type": "object",
                "properties": {
                    "location": {
                        "type": "string",
                        "description": "The city or town to get the weather for"
                    },
                    "unit": {
                        "type": "string",
                        "enum": ["celsius", "fahrenheit"]
                    }
                },
                "required": ["location"]
            }
        }
    };

    // Create a chat completion request with tools
    chat:ChatCompletionsBody request = {
        model: "gpt-4o-mini",
        messages: [
            {role: "user", "content": "What is the weather in Seattle?"}
        ],
        tools: [weatherTool]
    };

    chat:InlineResponse200 response = check azureOpenAIChat->/chat/completions.post(request);

    record {string id; chat:OpenAICreateChatCompletionResponseChoices[] choices; int created; string model; string system_fingerprint?; "chat.completion" 'object; chat:OpenAICompletionUsage usage?; chat:InlineResponse200PromptFilterResults[] prompt_filter_results?;} chatResponse = check response.ensureType();

    if chatResponse.choices.length() > 0 {
        chat:OpenAICreateChatCompletionResponseChoices choice = chatResponse.choices[0];
        io:println("Finish reason: " + choice.finish_reason);

        // Check if the model wants to call a tool
        chat:OpenAIChatCompletionMessageToolCallsItem? toolCalls = choice.message.tool_calls;
        if toolCalls is chat:OpenAIChatCompletionMessageToolCallsItem {
            foreach var toolCall in toolCalls {
                if toolCall is chat:OpenAIChatCompletionMessageToolCall {
                    io:println("Tool call - Function: " + toolCall.'function.name);
                    io:println("Arguments: " + toolCall.'function.arguments);
                }
            }
        }
    }
}
