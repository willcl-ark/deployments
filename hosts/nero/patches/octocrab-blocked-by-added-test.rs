use octocrab::models::timelines::TimelineEvent;

#[test]
fn preserves_gui_qml_blocked_by_added_event() {
    // Captured from bitcoin-core/gui-qml issue 753's public GitHub timeline.
    let original: serde_json::Value =
        serde_json::from_str(include_str!("octocrab-blocked-by-added.json")).unwrap();
    let event: TimelineEvent = serde_json::from_value(original.clone()).unwrap();
    let saved = serde_json::to_value(&event).unwrap();
    assert_eq!(saved["event"], original["event"]);
    assert_eq!(saved["id"], original["id"]);
    assert_eq!(saved["created_at"], original["created_at"]);
    for key in ["number", "title", "state", "state_reason"] {
        assert_eq!(saved["blocked_by"][key], original["blocked_by"][key]);
    }
    for key in ["id", "node_id", "name", "full_name", "url", "html_url"] {
        assert_eq!(
            saved["blocked_by"]["repository"][key],
            original["blocked_by"]["repository"][key]
        );
    }
}
