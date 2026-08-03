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

import ballerina/http;
import ballerina/log;

listener http:Listener httpListener = new (9090);

const string API_KEY_HEADER = "api-key";
const string AUTHORIZATION_HEADER = "authorization";

// Values the mock reports in `system_fingerprint` for an `auth-probe` request.
const string AUTH_SCHEME_API_KEY = "auth-scheme-api-key";
const string AUTH_SCHEME_BEARER = "auth-scheme-bearer";

// Model families that reject the sampling parameters older chat models accept.
final readonly & string[] REASONING_MODEL_PREFIXES = ["gpt-5", "o1", "o3", "o4"];

// Parameters Azure rejects outright when the target is a reasoning model.
final readonly & string[] UNSUPPORTED_REASONING_PARAMS = ["temperature", "top_p"];

// A mock of the Azure OpenAI Chat Completions endpoint. The behaviour is shaped
// by the incoming request so the tests can exercise realistic scenarios
// (plain completions, tool calls, multiple choices, content filtering, etc.).
//
// The body is bound as `map<json>` so the mock accepts any valid request shape
// (every message role and content-part variant) without re-implementing the
// union data binding of `ChatCompletionsBody` on the server side. `api-version`
// is an optional query parameter, matching `CreateChatCompletionQueries`.
//
// The mock also enforces Azure's authentication contract: `api-key` and
// `Authorization` are alternative schemes, so exactly one must be present and it
// must carry a non-blank credential.
http:Service mockService = service object {

    resource function post chat/completions(http:Request httpRequest, @http:Payload map<json> payload,
            string? api\-version = ()) returns json|http:BadRequest|http:Unauthorized {

        string|http:Unauthorized authScheme = resolveAuthScheme(httpRequest);
        if authScheme is http:Unauthorized {
            return authScheme;
        }

        // Scenario 0: report which authentication scheme reached the server, so
        // tests can assert that only the header for the configured scheme is sent.
        if payload["user"] == "auth-probe" {
            return authProbeResponse(authScheme);
        }

        // `model` is a required, non-empty string for a valid Azure request.
        json modelField = payload["model"];
        string model = modelField is string ? modelField : "";
        if model.trim() == "" {
            return <http:BadRequest>{body: {"error": {"code": "invalid_request", "message": "model is required"}}};
        }

        // Reasoning models reject the sampling parameters that older chat models
        // accept, and Azure answers with a 400. Mirroring that here is what catches
        // a connector that puts `temperature`/`top_p` on the wire when the caller
        // never set them.
        http:BadRequest? unsupported = checkUnsupportedParams(model, payload);
        if unsupported is http:BadRequest {
            return unsupported;
        }

        json messagesField = payload["messages"];
        json[] messages = messagesField is json[] ? messagesField : [];

        // `messages` is required and must contain at least one message.
        if messages.length() == 0 {
            return <http:BadRequest>{body: {"error": {"code": "invalid_request", "message": "messages must contain at least one message"}}};
        }

        // Scenario 1: the caller provided tools -> respond with a tool call.
        if payload["tools"] is json[] {
            return {
                "id": "chatcmpl-tool-0001",
                "choices": [
                    {
                        "finish_reason": "tool_calls",
                        "index": 0,
                        "message": {
                            "role": "assistant",
                            "content": null,
                            "refusal": null,
                            "tool_calls": [
                                {
                                    "id": "call_abc123",
                                    "type": "function",
                                    "function": {
                                        "name": "get_current_weather",
                                        "arguments": "{\"location\":\"Colombo\"}"
                                    }
                                }
                            ]
                        },
                        "logprobs": null,
                        "content_filter_results": {
                            "hate": {"filtered": false, "severity": "safe"},
                            "protected_material_text": {"filtered": false, "detected": false}
                        }
                    }
                ],
                "created": 1723091495,
                "model": model,
                "system_fingerprint": "fp_mock_tool",
                "object": "chat.completion",
                "usage": {"completion_tokens": 18, "prompt_tokens": 42, "total_tokens": 60}
            };
        }

        // Scenario 2: the caller asked for multiple choices via `n`.
        json nField = payload["n"];
        int choiceCount = nField is int ? nField : 1;
        if choiceCount > 1 {
            json[] choices = [];
            foreach int i in 0 ..< choiceCount {
                choices.push({
                    "finish_reason": "stop",
                    "index": i,
                    "message": {
                        "role": "assistant",
                        "content": "Mock choice " + i.toString(),
                        "refusal": null
                    },
                    "logprobs": null
                });
            }
            return {
                "id": "chatcmpl-multi-0002",
                "choices": choices,
                "created": 1723091496,
                "model": model,
                "system_fingerprint": "fp_mock_multi",
                "object": "chat.completion",
                "usage": {"completion_tokens": 11 * choiceCount, "prompt_tokens": 13, "total_tokens": 13 + 11 * choiceCount}
            };
        }

        // Scenario 3: a fully populated response exercising the optional
        // response-side sections (audio output, legacy function call, choice and
        // prompt content filters, log probabilities). Triggered by
        // `user == "rich-response"`.
        if payload["user"] == "rich-response" {
            return {
                "id": "chatcmpl-rich-0003",
                "prompt_filter_results": [
                    {
                        "prompt_index": 0,
                        "content_filter_results": {
                            "prompt_index": 0,
                            "content_filter_results": {
                                "sexual": {"filtered": false, "severity": "safe"},
                                "jailbreak": {"filtered": false, "detected": false},
                                "indirect_attack": {"filtered": false, "detected": false}
                            }
                        }
                    }
                ],
                "choices": [
                    {
                        "finish_reason": "tool_calls",
                        "index": 0,
                        "message": {
                            "role": "assistant",
                            "content": "Here is the answer.",
                            "refusal": null,
                            "tool_calls": [
                                {
                                    "id": "call_xyz",
                                    "type": "function",
                                    "function": {"name": "lookup", "arguments": "{\"q\":\"x\"}"}
                                }
                            ],
                            "function_call": {"name": "legacy_fn", "arguments": "{}"},
                            "audio": {
                                "id": "audio_1",
                                "expires_at": 1723095000,
                                "data": "BASE64",
                                "transcript": "spoken answer"
                            }
                        },
                        "content_filter_results": {
                            "sexual": {"filtered": false, "severity": "safe"},
                            "protected_material_text": {"filtered": false, "detected": false},
                            "protected_material_code": {
                                "filtered": false,
                                "detected": false,
                                "citation": {"URL": "https://lib", "license": "MIT"}
                            },
                            "ungrounded_material": {
                                "filtered": false,
                                "detected": false,
                                "details": [{"completion_start_offset": 0, "completion_end_offset": 5}]
                            }
                        },
                        "logprobs": {
                            "content": [
                                {
                                    "token": "Hello",
                                    "logprob": -0.1,
                                    "bytes": [72, 101],
                                    "top_logprobs": [{"token": "Hi", "logprob": -0.2, "bytes": [72, 105]}]
                                }
                            ],
                            "refusal": null
                        }
                    }
                ],
                "created": 1723091497,
                "model": model,
                "system_fingerprint": "fp_rich",
                "object": "chat.completion",
                "usage": {
                    "prompt_tokens": 20,
                    "completion_tokens": 30,
                    "total_tokens": 50,
                    "prompt_tokens_details": {"audio_tokens": 2, "cached_tokens": 4},
                    "completion_tokens_details": {"accepted_prediction_tokens": 1, "audio_tokens": 3, "reasoning_tokens": 5, "rejected_prediction_tokens": 2}
                }
            };
        }

        // Scenario 4 (default): a single assistant completion with content
        // filtering results and prompt filter results, mirroring a typical
        // Azure response.
        return {
            "id": "chatcmpl-00000",
            "prompt_filter_results": [
                {
                    "prompt_index": 0,
                    "content_filter_results": {
                        "prompt_index": 0,
                        "content_filter_results": {
                            "hate": {"filtered": false, "severity": "safe"},
                            "self_harm": {"filtered": false, "severity": "safe"},
                            "sexual": {"filtered": false, "severity": "safe"},
                            "violence": {"filtered": false, "severity": "safe"},
                            "jailbreak": {"filtered": false, "detected": false},
                            "indirect_attack": {"filtered": false, "detected": false}
                        }
                    }
                }
            ],
            "choices": [
                {
                    "finish_reason": "stop",
                    "index": 0,
                    "message": {
                        "role": "assistant",
                        "content": "Test message received! How can I assist you today?",
                        "refusal": null
                    },
                    "content_filter_results": {
                        "hate": {"filtered": false, "severity": "safe"},
                        "self_harm": {"filtered": false, "severity": "safe"},
                        "sexual": {"filtered": false, "severity": "safe"},
                        "violence": {"filtered": false, "severity": "safe"}
                    },
                    "logprobs": null
                }
            ],
            "created": 1723091495,
            "model": model,
            "system_fingerprint": "fp_48196bc67a",
            "object": "chat.completion",
            "usage": {"completion_tokens": 11, "prompt_tokens": 13, "total_tokens": 24}
        };
    }
};

// Returns a `BadRequest` mirroring Azure's response when a reasoning model is
// sent a parameter it does not support, or `()` when the payload is acceptable.
isolated function checkUnsupportedParams(string model, map<json> payload) returns http:BadRequest? {
    if !isReasoningModel(model) {
        return ();
    }
    foreach string param in UNSUPPORTED_REASONING_PARAMS {
        if payload.hasKey(param) {
            return <http:BadRequest>{
                body: {
                    "error": {
                        "code": "unsupported_parameter",
                        "message": string `Unsupported parameter: '${param}' is not supported with this model.`,
                        "param": param,
                        "type": "invalid_request_error"
                    }
                }
            };
        }
    }
    return ();
}

// The gpt-5 family and the o-series are reasoning models.
isolated function isReasoningModel(string model) returns boolean {
    foreach string prefix in REASONING_MODEL_PREFIXES {
        if model.startsWith(prefix) {
            return true;
        }
    }
    return false;
}

// Azure accepts either an `api-key` header or an `Authorization: Bearer ...`
// header, never both. Returns the scheme that was used, or an `Unauthorized`
// response when the combination of headers is not one Azure would accept.
isolated function resolveAuthScheme(http:Request request) returns string|http:Unauthorized {
    string? apiKeyHeader = optionalHeader(request, API_KEY_HEADER);
    string? authorizationHeader = optionalHeader(request, AUTHORIZATION_HEADER);

    if apiKeyHeader is string && authorizationHeader is string {
        return <http:Unauthorized>{
            body: {
                "error": {
                    "code": "conflicting_authentication",
                    "message": string `only one of '${API_KEY_HEADER}' or '${AUTHORIZATION_HEADER}' may be sent`
                }
            }
        };
    }

    if apiKeyHeader is string {
        if apiKeyHeader.trim() == "" {
            return unauthorized(string `'${API_KEY_HEADER}' header must not be blank`);
        }
        return AUTH_SCHEME_API_KEY;
    }

    if authorizationHeader is string {
        if !authorizationHeader.startsWith("Bearer ") || authorizationHeader.substring(7).trim() == "" {
            return unauthorized(string `'${AUTHORIZATION_HEADER}' header must carry a non-blank bearer token`);
        }
        return AUTH_SCHEME_BEARER;
    }

    return unauthorized("a credential is required");
}

isolated function optionalHeader(http:Request request, string name) returns string? {
    string|http:HeaderNotFoundError value = request.getHeader(name);
    return value is string ? value : ();
}

isolated function unauthorized(string message) returns http:Unauthorized => {
    body: {"error": {"code": "unauthorized", "message": message}}
};

// A minimal valid completion whose `system_fingerprint` names the authentication
// scheme the server observed.
isolated function authProbeResponse(string authScheme) returns json => {
    "id": "chatcmpl-auth-0004",
    "choices": [
        {
            "finish_reason": "stop",
            "index": 0,
            "message": {"role": "assistant", "content": "Authenticated.", "refusal": null},
            "logprobs": null
        }
    ],
    "created": 1723091498,
    "model": "gpt-4o-mini",
    "system_fingerprint": authScheme,
    "object": "chat.completion",
    "usage": {"completion_tokens": 2, "prompt_tokens": 3, "total_tokens": 5}
};

function init() returns error? {
    if isLiveServer {
        log:printInfo("Skipping mock server initialization as the tests are running against a live server");
        return;
    }

    log:printInfo("Initiating mock server...");
    check httpListener.attach(mockService, "/");
    check httpListener.'start();
}
