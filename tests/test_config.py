import importlib

import pytest


@pytest.fixture()
def store(tmp_path, monkeypatch):
    monkeypatch.setenv("AD4CONNECT_CONFIG", str(tmp_path / "config.ini"))
    from ad4ctl import config as config_store

    importlib.reload(config_store)
    return config_store


def test_load_empty_when_no_file(store):
    assert store.load_config() == {}


def test_save_then_load_roundtrip(store):
    store.save_config({"host": "192.168.1.50", "port": 8899})
    loaded = store.load_config()
    assert loaded["host"] == "192.168.1.50"
    assert loaded["port"] == "8899"


def test_save_merges_without_dropping_keys(store):
    store.save_config({"host": "10.0.0.5"})
    store.save_config({"port": 9999})
    loaded = store.load_config()
    assert loaded == {"host": "10.0.0.5", "port": "9999"}


def test_unset_removes_only_requested_keys(store):
    store.save_config({"host": "10.0.0.5", "port": 8899})
    removed = store.unset_config(["port"])
    assert removed == ["port"]
    assert store.load_config() == {"host": "10.0.0.5"}


def test_unset_missing_key_is_noop(store):
    store.save_config({"host": "10.0.0.5"})
    assert store.unset_config(["timeout"]) == []


def test_config_path_honours_override(store, tmp_path):
    assert store.config_path() == tmp_path / "config.ini"
