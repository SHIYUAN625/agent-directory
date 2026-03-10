"""LDAP client safety tests."""

from enterprise.provisioner.ldap_client import LDAPClient, _escape_filter_value


def test_escape_filter_value_rfc4515_characters():
    assert _escape_filter_value(r"a*(b)\x") == r"a\2a\28b\29\5cx"
    assert _escape_filter_value("null\x00byte") == r"null\00byte"


def test_search_agents_escapes_user_supplied_filter_values(monkeypatch):
    client = LDAPClient(
        uri="ldaps://localhost",
        base_dn="DC=test,DC=local",
        bind_dn="CN=admin,DC=test,DC=local",
        bind_pw="test",
    )

    captured = {}

    def _fake_ldapsearch(base_dn, ldap_filter, scope, attributes):
        captured["filter"] = ldap_filter
        return []

    monkeypatch.setattr(client, "_ldapsearch", _fake_ldapsearch)
    client.search_agents(
        agent_type="worker*)(|(objectClass=*))",
        name="agent)(bad",
    )

    ldap_filter = captured["filter"]
    assert "(objectClass=x-agent)" in ldap_filter
    assert r"x-agent-Type=worker\2a\29\28|\28objectClass=\2a\29\29" in ldap_filter
    assert r"sAMAccountName=agent\29\28bad$" in ldap_filter
