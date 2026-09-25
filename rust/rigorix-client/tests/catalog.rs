//! Catalog drift + error-taxonomy mapping against the frozen contracts.

use std::collections::{BTreeSet, HashSet};

use rigorix_client::{catalog, ApiError};

#[test]
fn client_binds_every_frozen_catalog_method() {
    let text = rigorix_schemas::schema("api/catalog.json").expect("embedded catalog");
    let catalog: serde_json::Value = serde_json::from_str(text).expect("catalog parses");

    let frozen: BTreeSet<String> = catalog["methods"]
        .as_array()
        .expect("methods")
        .iter()
        .map(|method| method["name"].as_str().expect("name").to_string())
        .collect();
    let bound: BTreeSet<String> = catalog::names()
        .iter()
        .map(|name| name.to_string())
        .collect();

    assert_eq!(
        frozen, bound,
        "the client catalog must mirror schemas/api/catalog.json exactly"
    );
    for name in &frozen {
        assert!(
            catalog::find(name).is_some(),
            "{name} must have an explicit binding (typed or server-only)"
        );
    }
    catalog::assert_no_raw_step_execution().expect("no raw step-execution surface");
}

#[test]
fn every_error_type_maps_to_a_distinct_variant_and_round_trips() {
    let text = rigorix_schemas::schema("api/errors.json").expect("embedded errors");
    let errors: serde_json::Value = serde_json::from_str(text).expect("errors parses");
    let types: Vec<String> = errors["$defs"]["errorType"]["enum"]
        .as_array()
        .expect("errorType enum")
        .iter()
        .map(|value| value.as_str().expect("string").to_string())
        .collect();

    let mut seen: HashSet<ApiError> = HashSet::new();
    for name in &types {
        let mapped = ApiError::from_type(name);
        assert_eq!(mapped.as_type(), name, "round-trip for `{name}`");
        assert!(seen.insert(mapped), "a distinct variant per `{name}`");
    }

    // An unknown type never panics and is preserved verbatim.
    assert_eq!(
        ApiError::from_type("totally_unknown"),
        ApiError::Unknown("totally_unknown".to_string())
    );
}
