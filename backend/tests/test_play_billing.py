from copy import deepcopy
from dataclasses import replace
from datetime import timedelta

from fastapi import HTTPException
from fastapi.testclient import TestClient
import pytest

from test_subscription_limits import billing
from app.services.play_billing import (
    PlayBillingService, PlayPurchaseStore, VerifiedPurchase, PlayPurchaseGone, account_id,
    token_id, validate_purchase, PRODUCT_ID, BASE_PLAN_ID,
)


def payload(uid, now, state='SUBSCRIPTION_STATE_ACTIVE', **updates):
    return {
        'externalAccountIdentifiers': {'obfuscatedExternalAccountId': account_id(uid)},
        'lineItems': [{'productId': PRODUCT_ID, 'offerDetails': {'basePlanId': BASE_PLAN_ID},
                       'expiryTime': (now + timedelta(days=30)).isoformat()}],
        'subscriptionState': state, 'acknowledgementState': 'ACKNOWLEDGEMENT_STATE_PENDING',
        **updates,
    }


class FakePlayApi:
    def __init__(self, result):
        self.result = result
        self.acknowledged = []
        self.reads = 0
    def get(self, token):
        self.reads += 1
        return deepcopy(self.result)
    def acknowledge(self, token):
        self.acknowledged.append(token)


@pytest.fixture
def play(billing, monkeypatch):
    monkeypatch.setenv('GOOGLE_PLAY_BILLING_ENABLED', 'true')
    subscriptions, db, clock = billing
    api = FakePlayApi(payload('alice', clock[0]))
    service = PlayBillingService(subscriptions.store, api=api, clock=lambda: clock[0])
    return service, subscriptions, db, clock, api


def test_verified_purchase_grants_plus_once_and_preserves_existing_usage(play):
    play_service, subscriptions, db, clock, api = play
    db.records['billing_usage/alice/months/2026-11'] = {'chat': 18, 'photo': 2}
    play_service.verify('alice', 'purchase-secret')
    play_service.verify('alice', 'purchase-secret')
    status = subscriptions.view('alice')
    assert status['plan'] == 'plus'
    assert status['limits'] == {'chat': 500, 'photo': 50}
    assert status['used'] == {'chat': 18, 'photo': 2}
    assert len([key for key in db.records if key.startswith('billing_play_purchases/')]) == 1
    assert 'purchase-secret' not in str(status)
    assert api.acknowledged == ['purchase-secret', 'purchase-secret']


@pytest.mark.parametrize('state,active', [
    ('SUBSCRIPTION_STATE_ACTIVE', True), ('SUBSCRIPTION_STATE_CANCELED', True),
    ('SUBSCRIPTION_STATE_IN_GRACE_PERIOD', True), ('SUBSCRIPTION_STATE_PENDING', False),
    ('SUBSCRIPTION_STATE_ON_HOLD', False), ('SUBSCRIPTION_STATE_PAUSED', False),
    ('SUBSCRIPTION_STATE_EXPIRED', False), ('SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED', False),
])
def test_google_subscription_lifecycle_is_authoritative(billing, state, active):
    _, _, clock = billing
    verified = validate_purchase(payload('alice', clock[0], state), 'alice', 'token', clock[0])
    assert verified.active is active


def test_wrong_user_product_and_base_plan_never_grant_access(play):
    play_service, subscriptions, db, clock, api = play
    with pytest.raises(HTTPException) as error:
        play_service.verify('bob', 'stolen-token')
    assert error.value.status_code == 403
    for field, bad in [('productId', 'another_product'), ('offerDetails', {'basePlanId': 'annual'})]:
        api.result = payload('alice', clock[0])
        api.result['lineItems'][0][field] = bad
        with pytest.raises(HTTPException):
            play_service.verify('alice', 'token')
    assert subscriptions.view('alice')['plan'] == 'free'
    assert api.acknowledged == []


def test_token_cannot_be_reassigned_even_when_google_claims_another_account(play):
    service, _, _, clock, api = play
    service.verify('alice', 'token')
    api.result = payload('bob', clock[0])
    with pytest.raises(HTTPException) as error:
        service.verify('bob', 'token')
    assert error.value.status_code == 403


def test_pending_purchase_is_not_acknowledged_or_activated(play):
    service, subscriptions, _, _, api = play
    api.result['subscriptionState'] = 'SUBSCRIPTION_STATE_PENDING'
    api.result['lineItems'][0].pop('expiryTime')
    service.verify('alice', 'token')
    assert subscriptions.view('alice')['plan'] == 'free'
    assert api.acknowledged == []


def test_refund_is_rechecked_before_metered_access_and_renewal_extends_expiry(play):
    service, subscriptions, _, clock, api = play
    service.verify('alice', 'token')
    subscriptions.entitlement_refresher = service.refresh
    api.result = payload('alice', clock[0], 'SUBSCRIPTION_STATE_EXPIRED')
    assert subscriptions.view('alice')['plan'] == 'free'
    api.result = payload('alice', clock[0] + timedelta(days=20))
    subscriptions.reserve('alice', 'chat')
    assert subscriptions.view('alice')['plan'] == 'plus'
    assert api.reads >= 4


def test_older_in_flight_result_cannot_undo_refund(play):
    service, subscriptions, _, clock, api = play
    earlier = validate_purchase(api.result, 'alice', 'token', clock[0])
    service.store.apply('alice', earlier)
    service.store.apply('alice', replace(earlier, checked_at=clock[0] + timedelta(seconds=5), active=False))
    service.store.apply('alice', earlier)
    assert subscriptions.view('alice')['plan'] == 'free'


def test_verification_orders_by_request_start_not_delayed_response_completion(play):
    service, subscriptions, _, clock, api = play
    earlier = validate_purchase(api.result, 'alice', 'token', clock[0])
    service.store.apply('alice', earlier)
    def delayed_response(token):
        clock[0] += timedelta(seconds=5)
        service.store.apply('alice', replace(earlier, checked_at=clock[0], active=False))
        return api.result
    api.get = delayed_response
    service.verify('alice', 'token')
    assert subscriptions.view('alice')['plan'] == 'free'


def test_replacement_supersedes_old_token_and_old_replay_cannot_reactivate(play):
    service, subscriptions, db, clock, api = play
    service.verify('alice', 'old-token')
    api.result['linkedPurchaseToken'] = 'old-token'
    service.verify('alice', 'new-token')
    assert db.records['billing_entitlements/alice']['purchase_id'] == token_id('new-token')
    api.result.pop('linkedPurchaseToken')
    service.verify('alice', 'old-token')
    assert db.records['billing_entitlements/alice']['purchase_id'] == token_id('new-token')


def test_verification_is_disabled_until_console_setup_and_api_failures_fail_closed(play, monkeypatch):
    service, subscriptions, _, _, api = play
    monkeypatch.setenv('GOOGLE_PLAY_BILLING_ENABLED', 'false')
    with pytest.raises(HTTPException) as error:
        service.verify('alice', 'token')
    assert error.value.status_code == 503
    assert api.reads == 0
    monkeypatch.setenv('GOOGLE_PLAY_BILLING_ENABLED', 'true')
    service.verify('alice', 'token')
    subscriptions.entitlement_refresher = service.refresh
    def fail(token):
        raise ValueError('private-purchase-token')
    api.get = fail
    with pytest.raises(HTTPException) as error:
        subscriptions.reserve('alice', 'chat')
    assert error.value.status_code == 503
    assert 'private-purchase-token' not in str(error.value.detail)


def test_verify_endpoint_uses_firebase_identity_and_rejects_client_entitlements(play, monkeypatch):
    import app.main as main
    service, subscriptions, _, _, _ = play
    monkeypatch.setattr(main, 'subscriptions', subscriptions)
    monkeypatch.setattr(main, 'play_billing', service)
    client = TestClient(main.app)
    assert client.post('/subscription/google-play/verify', json={'purchase_token': 'token'}).status_code == 401
    response = client.post('/subscription/google-play/verify', json={'purchase_token': 'token', 'uid': 'bob', 'plan': 'plus'},
                           headers={'Authorization': 'Bearer alice'})
    assert response.status_code == 422
    response = client.post('/subscription/google-play/verify', json={'purchase_token': 'token'},
                           headers={'Authorization': 'Bearer alice'})
    assert response.status_code == 200
    assert response.json()['subscription']['plan'] == 'plus'


def test_old_expired_google_token_does_not_block_free_access_forever(play):
    service, subscriptions, _, _, api = play
    service.verify('alice', 'token')
    subscriptions.entitlement_refresher = service.refresh
    def gone(token):
        raise PlayPurchaseGone()
    api.get = gone
    assert subscriptions.view('alice')['plan'] == 'free'
    subscriptions.reserve('alice', 'chat')
