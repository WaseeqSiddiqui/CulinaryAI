from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
from datetime import datetime, timezone
from threading import RLock

from fastapi import Body, FastAPI, HTTPException
from fastapi.testclient import TestClient
from starlette.responses import JSONResponse
import pytest

from app.services.subscription_service import FirestoreUsageStore, PLAN_LIMITS, SubscriptionService, active_plan
from app.services.usage_middleware import UsageLimitMiddleware


class Reference:
    def __init__(self, db, path):
        self.db, self.path = db, path
    def collection(self, name):
        return Reference(self.db, self.path + '/' + name)
    def document(self, name):
        return Reference(self.db, self.path + '/' + name)
    def get(self, **kwargs):
        value = deepcopy(self.db.records.get(self.path))
        class Snapshot:
            def to_dict(self):
                return value
        return Snapshot()


class FakeDatabase:
    def __init__(self):
        self.records = {}
        self.lock = RLock()
    def collection(self, name):
        return Reference(self, name)
    def transaction(self, **kwargs):
        return self
    def set(self, reference, value, merge=False):
        self.records[reference.path] = {**(self.records.get(reference.path, {}) if merge else {}), **value}
    def update(self, reference, value):
        self.set(reference, value, merge=True)


@pytest.fixture
def billing(monkeypatch):
    from firebase_admin import firestore
    db = FakeDatabase()
    def transactional(function):
        def apply(transaction):
            with db.lock:
                return function(transaction)
        return apply
    monkeypatch.setattr(firestore, 'transactional', transactional)
    store = FirestoreUsageStore()
    store._database = db
    def verify(header):
        if not header or not header.startswith('Bearer '):
            raise HTTPException(status_code=401, detail='Sign in')
        return header[7:]
    monkeypatch.setattr(store, 'verify_user', verify)
    clock = [datetime(2026, 11, 23, tzinfo=timezone.utc)]
    service = SubscriptionService(store=store, clock=lambda: clock[0])
    return service, db, clock


def test_free_quota_is_persistent_across_service_instances_and_cannot_be_bypassed_by_user_id(billing):
    service, db, clock = billing
    for _ in range(20):
        reservation = service.reserve('alice', 'chat')
        service.finish(reservation, success=True)
    restored_store = FirestoreUsageStore()
    restored_store._database = db
    restored = SubscriptionService(store=restored_store, clock=lambda: clock[0])
    assert restored.view('alice')['used']['chat'] == 20
    with pytest.raises(HTTPException) as error:
        restored.reserve('alice', 'chat')
    assert error.value.status_code == 429
    assert error.value.detail['code'] == 'quota_exceeded'
    assert restored.view('bob')['used']['chat'] == 0


def test_plus_requires_active_unexpired_server_entitlement_and_keeps_monthly_usage(billing):
    service, db, clock = billing
    db.records['billing_entitlements/alice'] = {'plan': 'plus', 'status': 'active', 'expires_at': datetime(2026, 12, 1, tzinfo=timezone.utc)}
    assert service.view('alice')['limits'] == PLAN_LIMITS['plus']
    db.records['billing_usage/alice/months/2026-11'] = {'chat': 25, 'photo': 4}
    db.records['billing_entitlements/alice']['expires_at'] = datetime(2026, 11, 22, tzinfo=timezone.utc)
    assert service.view('alice')['plan'] == 'free'
    with pytest.raises(HTTPException):
        service.reserve('alice', 'chat')
    assert active_plan({'plan': 'plus', 'status': 'active'}, clock[0]) == 'free'


def test_resets_follow_server_utc_month_and_refunds_apply_to_original_month(billing):
    service, db, clock = billing
    old = service.reserve('alice', 'photo')
    clock[0] = datetime(2026, 12, 1, tzinfo=timezone.utc)
    assert service.view('alice')['used']['photo'] == 0
    assert service.view('alice')['resets_at'].startswith('2027-01-01')
    service.finish(old, success=False)
    assert db.records['billing_usage/alice/months/2026-11']['photo'] == 0
    assert service.view('alice')['used']['photo'] == 0


def test_failed_request_refund_is_idempotent(billing):
    service, _, _ = billing
    reservation = service.reserve('alice', 'photo')
    service.finish(reservation, success=False)
    service.finish(reservation, success=False)
    assert service.view('alice')['used']['photo'] == 0


def test_concurrent_requests_cannot_exceed_allowance(billing):
    service, _, _ = billing
    def attempt(_):
        try:
            return service.reserve('alice', 'chat')
        except HTTPException as error:
            assert error.status_code == 429
            return None
    with ThreadPoolExecutor(max_workers=10) as pool:
        reservations = list(pool.map(attempt, range(35)))
    assert sum(value is not None for value in reservations) == 20
    assert service.view('alice')['used']['chat'] == 20


def application(service):
    app = FastAPI()
    app.add_middleware(UsageLimitMiddleware, service=service)
    calls = []
    @app.post('/chef-chat')
    def chat(body: dict = Body(...)):
        calls.append(body)
        return JSONResponse({'reply': 'Hello'}, status_code=body.get('status', 200))
    @app.post('/parse-receipt')
    @app.post('/scan-fridge')
    @app.post('/analyze-meal')
    @app.post('/validate-cooking-step')
    def photo(body: dict = Body(...)):
        return JSONResponse({'status': 'unable_to_assess' if body.get('refund') else 'ready'},
            headers={'X-AI-Usage-Refund': '1'} if body.get('refund') else {})
    return TestClient(app), calls


def test_middleware_verifies_identity_before_ai_and_reserves_before_model_call(billing, monkeypatch):
    monkeypatch.setenv('USAGE_LIMITS_ENABLED', 'true')
    service, _, _ = billing
    client, calls = application(service)
    assert client.post('/chef-chat', json={}, headers={'X-User-Id': 'alice'}).status_code == 401
    for _ in range(20):
        assert client.post('/chef-chat', json={}, headers={'Authorization': 'Bearer alice', 'X-User-Id': 'bob'}).status_code == 200
    response = client.post('/chef-chat', json={}, headers={'Authorization': 'Bearer alice'})
    assert response.status_code == 429
    assert response.headers['x-usage-limit'] == 'exceeded'
    assert len(calls) == 20


def test_middleware_refunds_validation_provider_and_unassessable_photo_failures(billing, monkeypatch):
    monkeypatch.setenv('USAGE_LIMITS_ENABLED', 'true')
    service, _, _ = billing
    client, _ = application(service)
    headers = {'Authorization': 'Bearer alice'}
    assert client.post('/chef-chat', content='invalid JSON', headers={**headers, 'Content-Type': 'application/json'}).status_code == 422
    for status in (429, 500, 503):
        response = client.post('/chef-chat', json={'status': status}, headers=headers)
        assert response.status_code == status
        assert 'x-usage-limit' not in response.headers
    assert service.view('alice')['used']['chat'] == 0
    response = client.post('/validate-cooking-step', json={'refund': True}, headers=headers)
    assert 'x-ai-usage-refund' not in response.headers
    assert service.view('alice')['used']['photo'] == 0


def test_all_photo_features_share_the_same_monthly_pool(billing, monkeypatch):
    monkeypatch.setenv('USAGE_LIMITS_ENABLED', 'true')
    service, _, _ = billing
    client, _ = application(service)
    headers = {'Authorization': 'Bearer alice'}
    for route in ['/parse-receipt', '/scan-fridge', '/analyze-meal']:
        assert client.post(route, json={}, headers=headers).status_code == 200
    assert client.post('/validate-cooking-step', json={}, headers=headers).status_code == 429


def test_missing_sign_in_and_bad_tokens_are_not_trusted(monkeypatch):
    from firebase_admin import auth
    store = FirestoreUsageStore()
    with pytest.raises(HTTPException) as error:
        store.verify_user(None)
    assert error.value.status_code == 401
    monkeypatch.setattr(store, '_firebase_app', lambda: object())
    def invalid(*args, **kwargs):
        raise ValueError('Invalid signature')
    monkeypatch.setattr(auth, 'verify_id_token', invalid)
    with pytest.raises(HTTPException) as error:
        store.verify_user('Bearer fake-token')
    assert error.value.status_code == 401


def test_readiness_checks_auth_and_refunds_only_the_reserved_service_identity(billing, monkeypatch):
    from firebase_admin import auth
    service, db, _ = billing
    monkeypatch.setattr(service.store, '_firebase_app', lambda: object())
    seen = []
    def missing(uid, **kwargs):
        seen.append(uid)
        raise auth.UserNotFoundError('Readiness identity is not a user')
    monkeypatch.setattr(auth, 'get_user', missing)
    service.check_ready()
    assert seen == ['__culinary_subscription_readiness__']
    assert service.view(seen[0])['used']['chat'] == 0
    reservations = [value for key, value in db.records.items() if key.startswith('billing_reservations/')]
    assert len(reservations) == 1
    assert reservations[0]['state'] == 'refunded'
    assert reservations[0]['uid'] == seen[0]


def test_readiness_failure_stops_startup_without_exposing_credentials(billing, monkeypatch):
    service, _, _ = billing
    def fail():
        raise ValueError('private credential contents')
    monkeypatch.setattr(service.store, 'check_ready', fail)
    with pytest.raises(RuntimeError) as error:
        service.check_ready()
    assert 'Monthly usage setup failed' in str(error.value)
    assert 'private credential contents' not in str(error.value)
