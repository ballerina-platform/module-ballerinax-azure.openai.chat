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

// Direct unit tests for the auto-generated query/URI serialization helpers in
// `utils.bal`. These helpers are not all reachable through the single-endpoint
// client, so they are exercised here to keep them verified and covered.

import ballerina/test;

@test:Config {
    groups: ["utils_tests"]
}
isolated function testGetEncodedUri() {
    test:assertEquals(getEncodedUri("hello world"), "hello%20world");
    test:assertEquals(getEncodedUri("a+b/c"), "a%2Bb%2Fc");
    test:assertEquals(getEncodedUri(2025), "2025");
    test:assertEquals(getEncodedUri(true), "true");
}

@test:Config {
    groups: ["utils_tests"]
}
isolated function testGetPathForQueryParamEmpty() returns error? {
    test:assertEquals(check getPathForQueryParam({}), "");
}

@test:Config {
    groups: ["utils_tests"]
}
isolated function testGetPathForQueryParamSimple() returns error? {
    string path = check getPathForQueryParam({"api-version": "2025-04-01-preview"});
    test:assertEquals(path, "?api-version=2025-04-01-preview");
}

@test:Config {
    groups: ["utils_tests"]
}
isolated function testGetPathForQueryParamNilValueIsDropped() returns error? {
    string path = check getPathForQueryParam({"skip": (), "keep": "yes"});
    test:assertEquals(path, "?keep=yes");
}

@test:Config {
    groups: ["utils_tests"]
}
isolated function testGetPathForQueryParamArrayValue() returns error? {
    string path = check getPathForQueryParam({"id": [1, 2, 3]});
    test:assertTrue(path.startsWith("?id="), "expected the array to be serialized under the 'id' key");

    string stringArrayPath = check getPathForQueryParam({"tags": ["a", "b"]});
    test:assertTrue(stringArrayPath.startsWith("?tags="), "expected the string array to be serialized under 'tags'");
}

@test:Config {
    groups: ["utils_tests"]
}
isolated function testGetPathForQueryParamRecordFormStyle() returns error? {
    QueryRec rec = {a: "1", b: "2"};
    string path = check getPathForQueryParam({"filter": rec});
    test:assertTrue(path.includes("a=1"), "expected exploded form-style record query");
    test:assertTrue(path.includes("b=2"));
}

@test:Config {
    groups: ["utils_tests"]
}
isolated function testGetPathForQueryParamRecordDeepObjectStyle() returns error? {
    QueryRec rec = {a: "1", b: "2"};
    map<Encoding> encodingMap = {"filter": {style: DEEPOBJECT, explode: true}};
    string path = check getPathForQueryParam({"filter": rec}, encodingMap);
    test:assertTrue(path.includes("filter[a]=1"), "expected deepObject-style record query");
}

@test:Config {
    groups: ["utils_tests"]
}
isolated function testGetSerializedArrayAllStyles() {
    // Default form style with explode (the "else" path).
    test:assertEquals(getSerializedArray("k", [1, 2, 3]), "k=1&k=2&k=3");
    // Form style without explode.
    test:assertEquals(getSerializedArray("k", [1, 2], FORM, false), "k=1,2");
    // Space delimited without explode.
    test:assertEquals(getSerializedArray("k", [1, 2], SPACEDELIMITED, false), "k=1%202");
    // Pipe delimited without explode.
    test:assertEquals(getSerializedArray("k", [1, 2], PIPEDELIMITED, false), "k=1|2");
    // Deep object style.
    test:assertEquals(getSerializedArray("k", [1, 2], DEEPOBJECT), "k[]=1&k[]=2");
    // Empty array yields an empty string.
    test:assertEquals(getSerializedArray("k", []), "");
}

@test:Config {
    groups: ["utils_tests"]
}
isolated function testGetFormStyleRequest() {
    NestedQueryRec rec = {scalar: "v", list: [1, 2], child: {a: "1", b: "2"}};
    // Call with the default `explode` argument to cover the defaultable parameter.
    string defaultExplode = getFormStyleRequest("p", rec);
    test:assertTrue(defaultExplode.includes("scalar=v"));

    string exploded = getFormStyleRequest("p", rec, true);
    test:assertTrue(exploded.includes("scalar=v"));
    test:assertTrue(exploded.includes("list=1"));

    string notExploded = getFormStyleRequest("p", rec, false);
    test:assertTrue(notExploded.includes("scalar,v"));
}

@test:Config {
    groups: ["utils_tests"]
}
isolated function testEncodingRecordWithCustomFields() returns error? {
    // Covers the optional `contentType` and `headers` fields of the Encoding record.
    QueryRec rec = {a: "1", b: "2"};
    map<Encoding> encodingMap = {
        "filter": {style: FORM, explode: true, contentType: "application/json", headers: {"x-custom": "v"}}
    };
    string path = check getPathForQueryParam({"filter": rec}, encodingMap);
    test:assertTrue(path.includes("a=1"));
}

@test:Config {
    groups: ["utils_tests"]
}
isolated function testGetSerializedRecordArray() {
    QueryRec[] recs = [{a: "1", b: "2"}, {a: "3", b: "4"}];

    string exploded = getSerializedRecordArray("p", recs);
    test:assertTrue(exploded.includes("a=1"));

    string notExploded = getSerializedRecordArray("p", recs, FORM, false);
    test:assertTrue(notExploded.startsWith("p="));

    string deepObject = getSerializedRecordArray("p", recs, DEEPOBJECT);
    test:assertTrue(deepObject.includes("p[0][a]=1"));
}

@test:Config {
    groups: ["utils_tests"]
}
isolated function testGetDeepObjectStyleRequest() {
    DeepQueryRec rec = {
        scalar: "v",
        list: [1, 2],
        child: {a: "1", b: "2"},
        children: [{a: "1", b: "2"}]
    };
    string serialized = getDeepObjectStyleRequest("p", rec);
    test:assertTrue(serialized.includes("p[scalar]=v"));
    test:assertTrue(serialized.includes("p[list]"));
    test:assertTrue(serialized.includes("p[child][a]=1"));
    test:assertTrue(serialized.includes("p[children]"));
}

type QueryRec record {
    string a;
    string b;
};

type NestedQueryRec record {
    string scalar;
    int[] list;
    QueryRec child;
};

type DeepQueryRec record {
    string scalar;
    int[] list;
    QueryRec child;
    QueryRec[] children;
};
