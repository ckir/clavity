"""Unit tests for the C5 bus conventions (agy_bus): req-id minting, request envelope,
and response correlation. All pure — no bus I/O."""

from agy_bus import (
    extract_req_id,
    make_request,
    match_response,
    new_req_id,
)


def test_new_req_id_is_unique_and_prefixed():
    a, b = new_req_id(), new_req_id()
    assert a.startswith("req-") and b.startswith("req-")
    assert a != b


def test_make_request_embeds_tag_and_round_trips():
    rid = "req-1a2b3c4d"
    content = make_request(rid, "create a file foo.txt")
    assert content.startswith(f"[req_id={rid}] ")
    assert extract_req_id(content) == rid


def test_extract_req_id_none_when_absent():
    assert extract_req_id("no tag here") is None
    assert extract_req_id("") is None
    assert extract_req_id(None) is None


def test_match_by_reply_to_is_preferred():
    rid = "req-deadbeef"
    signals = [
        {"content": "unrelated", "replyTo": "sig_other"},
        {"content": "done", "replyTo": "sig_req_1"},
    ]
    hit = match_response(signals, rid, request_signal_id="sig_req_1")
    assert hit is not None and hit["content"] == "done"


def test_match_by_req_id_in_content_fallback():
    # agy may echo the id bare (as it did in the live integration test) with no replyTo.
    rid = "IT-9931"
    signals = [{"content": "INTEGRATION-OK IT-9931", "replyTo": None}]
    hit = match_response(signals, rid)
    assert hit is not None and hit["content"] == "INTEGRATION-OK IT-9931"


def test_match_returns_none_when_no_match():
    signals = [{"content": "something else", "replyTo": "sig_x"}]
    assert match_response(signals, "req-nope", request_signal_id="sig_req_1") is None
