_Authors_: @ballerina-platform \
_Created_: 2026/03/11 \
_Updated_: 2026/08/03 \
_Edition_: Swan Lake

# Sanitation for OpenAPI specification

This document records the sanitation done on top of the official OpenAPI specification from Azure AI Foundry Models Service.

The OpenAPI specification is obtained from the [Azure REST API Specs](https://github.com/Azure/azure-rest-api-specs/blob/main/specification/ai/data-plane/OpenAI.v1/azure-v1-v1-generated.yaml).
These changes are done in order to improve the overall usability, and as workarounds for some known language limitations.

1. **Extracted only Chat Completions endpoint from the full specification**:

   - **Original**: Full Azure AI Foundry Models Service spec with all endpoints (batches, responses, files, etc.)
   - **Updated**: Only the `/chat/completions` path and its related schemas are retained
   - **Reason**: This connector module only covers the Chat Completions API. Including unrelated endpoints would generate unnecessary code.

2. **Converted nullable type arrays to `nullable: true`**:

   - **Changed Schemas**: Multiple schemas throughout the specification
   - **Original**: `type: ["string", "null"]` (OpenAPI 3.1.x+ style)
   - **Updated**: `type: string` with `nullable: true`
   - **Reason**: Type arrays are not supported in OpenAPI 3.0.0. The `nullable: true` property is the 3.0.0 equivalent for expressing nullable types.

3. **Removed `default: null` properties**:

   - **Changed Schemas**: Multiple schemas including request and response types
   - **Original**: `default: null`
   - **Updated**: Removed the `default` parameter
   - **Reason**: Temporary workaround until the Ballerina OpenAPI tool supports OpenAPI Specification version v3.1.x+.

4. **Converted `const` to `enum`**:

   - **Changed Schemas**: Multiple schemas with constant values
   - **Original**: `const: "value"`
   - **Updated**: `enum: ["value"]`
   - **Reason**: The `const` keyword is not supported in OpenAPI 3.0.0. Using `enum` with a single value achieves the same effect.

5. **Converted `anyOf`/`oneOf` with null types**:

   - **Changed Schemas**: Multiple schemas using `anyOf`/`oneOf` with `{"type": "null"}`
   - **Original**: `anyOf: [{"type": "string"}, {"type": "null"}]`
   - **Updated**: `type: string` with `nullable: true`
   - **Reason**: The `anyOf`/`oneOf` with `{"type": "null"}` pattern for expressing nullable types is not supported in OpenAPI 3.0.0. The `nullable: true` property is used instead.

6. **Removed OpenAPI 3.2.0-specific features**:

   - Removed `pathItems` from components (not supported in 3.0.0)
   - Removed `propertyNames`, `unevaluatedProperties`, and other JSON Schema draft features
   - **Reason**: These keywords are not part of the OpenAPI 3.0.0 specification.

7. **Fixed `exclusiveMinimum`/`exclusiveMaximum` format**:

   - **Original**: Boolean form (OpenAPI 3.1.x+)
   - **Updated**: Numeric form (OpenAPI 3.0.0)
   - **Reason**: OpenAPI 3.0.0 uses numeric values for exclusive boundaries, not boolean flags.

8. **Renamed schemas to Ballerina-friendly type names**:

   - **Changed Schemas**: Only the schemas whose generated Ballerina type name was not a valid UpperCamelCase identifier (anonymous inline records the tool already emitted without a name were left unchanged).
   - **Original**:
      - Schema keys carrying the `OpenAI.` namespace prefix (e.g. `OpenAI.ChatCompletionTool`), which the tool emitted as escaped-dot type names (`OpenAI\.ChatCompletionTool`).
      - Inline request/response body and nested object schemas the tool named with underscores or a lowercase start (e.g. `chat_completions_body`, `inline_response_200`, `AzureContentFilterResultForChoice_protected_material_code`).
   - **Updated**:
      - Dropped the dot from namespaced keys, keeping the prefix (`OpenAI.ChatCompletionTool` → `OpenAIChatCompletionTool`).
      - Extracted the named inline schemas into components with UpperCamelCase names (`chat_completions_body` → `ChatCompletionsBody`, `inline_response_200` → `InlineResponse200`, `AzureContentFilterResultForChoice_protected_material_code` → `AzureContentFilterResultForChoiceProtectedMaterialCode`) and updated every `$ref`. Structurally identical `error` objects continue to share a single `AzureContentFilterResultForChoiceError` type.
   - **Reason**: Ballerina type names must be valid UpperCamelCase identifiers. Dots, underscores, and lowercase starts force backslash-escaped or non-idiomatic type names, which hurts the connector's usability.

9. **Made the nullable `logprobs` `$ref` property actually nullable via `allOf`**:

   - **Changed Schemas**: `OpenAICreateChatCompletionResponseChoices` — the `logprobs` property.
   - **Original**: A `$ref` with a sibling `nullable: true`:

     ```yaml
     logprobs:
       $ref: '#/components/schemas/OpenAICreateChatCompletionResponseChoicesLogprobs'
       nullable: true
     ```

   - **Updated**: Moved the `$ref` under an `allOf` so the sibling `nullable: true` is honored:

     ```yaml
     logprobs:
       allOf:
       - $ref: '#/components/schemas/OpenAICreateChatCompletionResponseChoicesLogprobs'
       nullable: true
     ```

   - **Reason**: In OpenAPI 3.0.0 a `$ref` overrides any sibling keywords, so the sibling `nullable: true` was ignored and the required `logprobs` field was generated as non-nullable (`OpenAICreateChatCompletionResponseChoicesLogprobs`). Azure returns `"logprobs": null` in every choice when log probabilities are not requested, so this required field must be nullable. Wrapping the `$ref` in `allOf` lets `nullable: true` apply, generating `OpenAICreateChatCompletionResponseChoicesLogprobs?`.

10. **Removed `default: true` from `parallel_tool_calls`**:

    - **Changed Schema**: `ChatCompletionsBody` — the `parallel_tool_calls` property.
    - **Original**:

      ```yaml
      parallel_tool_calls:
        type: boolean
        description: Whether to enable parallel function calling during tool use.
        default: true
      ```

    - **Updated**: Removed the `default: true` line so the property has no default:

      ```yaml
      parallel_tool_calls:
        type: boolean
        description: Whether to enable parallel function calling during tool use.
      ```

    - **Reason**: With `default: true` (and the property not being `required`), the Ballerina
      OpenAPI tool generates a required-with-default field `boolean parallel_tool_calls = true;`.
      That field is therefore always present on `ChatCompletionsBody` and always serialized onto
      the wire — even for requests that carry no `tools`. Azure OpenAI rejects such requests with
      `400 - "'parallel_tool_calls' is only allowed when 'tools' are specified."` Removing the
      default makes the tool generate an optional field `boolean parallel_tool_calls?;`, which is
      serialized only when the caller explicitly sets it (the `ai.azure` provider now sets it only
      when tools are present). Per the OpenAI/Azure API contract the field is meaningful only
      alongside `tools`, so an optional field is the correct representation.

11. **Removed `default: 1` from `temperature`, `top_p` and `n`**:

    - **Changed Schema**: `ChatCompletionsBody` — the `temperature`, `top_p` and `n` properties.
    - **Original**:

      ```yaml
      temperature:
        default: 1
        type: number
        nullable: true
      top_p:
        default: 1
        type: number
        nullable: true
      'n':
        minimum: 1
        maximum: 128
        description: How many chat completion choices to generate for each input message. ...
        default: 1
        type: integer
        nullable: true
      ```

    - **Updated**: Removed the `default: 1` line from each of the three properties; the
      `minimum`/`maximum` constraints, `nullable` markers and descriptions are unchanged.

    - **Reason**: This is sanitation item 10 applied to the remaining defaulted request
      parameters. `default: 1` on a non-`required` property makes the Ballerina OpenAPI tool
      generate a required-with-default field (`decimal? temperature = 1;`), which is always
      present on `ChatCompletionsBody` and therefore always serialized by
      `jsondata:toJson(payload)` (`ballerina/client.bal`). Every request went out carrying
      `"temperature":1.0,"top_p":1.0,"n":1` even when the caller set none of them. Azure
      documents `temperature` and `top_p` as **not supported** for the reasoning models —
      *"The following are currently unsupported with reasoning models: `temperature`, `top_p`,
      `presence_penalty`, `frequency_penalty`, `logprobs`, `top_logprobs`, `logit_bias`,
      `max_tokens`"*
      ([Azure OpenAI reasoning models](https://learn.microsoft.com/en-us/azure/ai-foundry/openai/how-to/reasoning)) —
      so every GPT-5-series and o-series call carried parameters the deployment rejects with
      `400 Unsupported parameter: 'temperature' is not supported with this model.`, a failure
      that occurs even when the value is the default `1`. Removing the defaults makes the tool
      generate plain optional fields (`decimal? temperature?;`, `int? n?;`) that are serialized
      only when the caller sets them. `n` is not on the unsupported list, but it is included for
      consistency and because it was previously impossible to omit. Upstream
      `azure-v1-v1-generated.json` declares all three as optional with no requirement to send
      them, and the values being sent were the service-side defaults, so behaviour for the
      GPT-4 and GPT-3.5 families is unchanged.

## OpenAPI cli command

The following command was used to generate the Ballerina client from the OpenAPI specification. The command should be executed from the repository root directory.

```bash
bal openapi -i docs/spec/openapi.yaml --mode client --license docs/license.txt -o ballerina
```
