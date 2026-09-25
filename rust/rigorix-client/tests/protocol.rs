//! JSON-RPC framing, version negotiation, and typed dispatch (ADR-0001 D1).

use rigorix_client::client::BatchCall;
use rigorix_client::transport::MockTransport;
use rigorix_client::types::{AuditReadParams, RunParams, UsageGuideResult};
use rigorix_client::{ApiError, Client, ClientError};
use serde_json::json;

fn response(id: i64, result: serde_json::Value) -> String {
    json!({ "jsonrpc": "2.0", "id": id, "result": result }).to_string()
}

#[test]
fn single_call_framing_and_typed_result() {
    let transport = MockTransport::ok(vec![response(1, json!({ "guide": "hi" }))]);
    let client = Client::new(transport);

    let out: UsageGuideResult = client.usage_guide().expect("typed result");
    assert_eq!(out.guide, "hi");

    let request: serde_json::Value =
        serde_json::from_str(&client.transport().requests()[0]).expect("request json");
    assert_eq!(request["jsonrpc"], "2.0");
    assert_eq!(request["method"], "rigorix.usageGuide");
    assert_eq!(request["id"], 1);
    assert_eq!(request["params"], json!({}));
}

#[test]
fn notification_framing_has_no_id() {
    let transport = MockTransport::ok(vec![String::new()]);
    let client = Client::new(transport);

    client
        .notify(
            "rigorix.audit.read",
            &AuditReadParams {
                execution_id: "e".to_string(),
                format: None,
            },
        )
        .expect("notification");

    let request: serde_json::Value =
        serde_json::from_str(&client.transport().requests()[0]).expect("request json");
    assert!(request.get("id").is_none(), "notification must omit `id`");
    assert_eq!(request["method"], "rigorix.audit.read");
}

#[test]
fn batch_framing_is_a_json_array() {
    let transport = MockTransport::ok(vec![json!([
        { "jsonrpc": "2.0", "id": 1, "result": { "guide": "a" } },
        { "jsonrpc": "2.0", "id": 2, "result": { "guide": "b" } }
    ])
    .to_string()]);
    let client = Client::new(transport);

    let calls = vec![
        BatchCall::new("rigorix.usageGuide", json!({})),
        BatchCall::new("rigorix.usageGuide", json!({})),
    ];
    let responses = client.batch_raw(&calls).expect("batch");
    assert_eq!(responses.len(), 2);

    let request: serde_json::Value =
        serde_json::from_str(&client.transport().requests()[0]).expect("batch json");
    assert!(request.is_array(), "a batch is one JSON array");
    assert_eq!(request.as_array().map(Vec::len), Some(2));
    assert_eq!(request[0]["id"], 1);
    assert_eq!(request[1]["id"], 2);
}

#[test]
fn rpc_error_maps_to_typed_taxonomy() {
    let transport = MockTransport::ok(vec![json!({
        "jsonrpc": "2.0",
        "id": 1,
        "error": {
            "code": -32010,
            "message": "denied",
            "data": { "type": "denied_by_sequence", "rule_id": "r1", "step": "deploy" }
        }
    })
    .to_string()]);
    let client = Client::new(transport);

    let error = client
        .run(&RunParams {
            template_name: "t".to_string(),
            execution_id: None,
            repository: None,
            author: None,
        })
        .expect_err("rpc error");
    match error {
        ClientError::Rpc {
            error_type, code, ..
        } => {
            assert_eq!(error_type, ApiError::DeniedBySequence);
            assert_eq!(code, -32010);
        }
        other => panic!("expected Rpc error, got {other:?}"),
    }
}

#[test]
fn version_negotiation_accepts_matching_major() {
    let transport = MockTransport::ok(vec![response(
        1,
        json!({
            "name": "rigorix-server",
            "engine_version": "1.7.0",
            "api_version": "1.0.0",
            "schemas": ["api/catalog.json"],
            "capabilities": ["jsonrpc-2.0"]
        }),
    )]);
    let client = Client::new(transport);
    let version = client.version().expect("version");
    assert_eq!(version.api_version, "1.0.0");
}

#[test]
fn version_negotiation_rejects_wrong_major() {
    let transport = MockTransport::ok(vec![response(
        1,
        json!({
            "name": "server",
            "engine_version": "x",
            "api_version": "2.0.0",
            "schemas": [],
            "capabilities": []
        }),
    )]);
    let client = Client::new(transport);
    assert!(matches!(
        client.version(),
        Err(ClientError::VersionMismatch { .. })
    ));
}

#[test]
fn protocol_error_when_neither_result_nor_error() {
    let transport = MockTransport::ok(vec![json!({ "jsonrpc": "2.0", "id": 1 }).to_string()]);
    let client = Client::new(transport);
    assert!(matches!(
        client.usage_guide(),
        Err(ClientError::Protocol(_))
    ));
}
