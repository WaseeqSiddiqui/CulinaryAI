"""Google Play subscriptions, verified on the server and bound to Firebase users."""
from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import hmac
import os
from urllib.parse import quote

from fastapi import HTTPException

from app.services.subscription_service import active_plan

PACKAGE_NAME = "com.enterprise.culinaryAI"
PRODUCT_ID = "culinary_plus_monthly"
BASE_PLAN_ID = "monthly"
SCOPE = "https://www.googleapis.com/auth/androidpublisher"
ACTIVE_STATES = {
    "SUBSCRIPTION_STATE_ACTIVE", "SUBSCRIPTION_STATE_IN_GRACE_PERIOD",
    "SUBSCRIPTION_STATE_CANCELED",  # Cancellation stops renewal, not paid access.
}


class PlayPurchaseGone(HTTPException):
    def __init__(self):
        super().__init__(410, "This Google Play subscription has expired. You can subscribe again.")


def checkout_enabled():
    return os.getenv("GOOGLE_PLAY_BILLING_ENABLED", "false").strip().lower() == "true"


def account_id(uid):
    return hashlib.sha256(uid.encode()).hexdigest()


def token_id(token):
    return hashlib.sha256(token.encode()).hexdigest()


def timestamp(value):
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        return parsed if parsed.tzinfo else None
    except (TypeError, ValueError, AttributeError):
        return None


@dataclass(frozen=True)
class VerifiedPurchase:
    token: str
    checked_at: datetime
    expires_at: datetime | None
    active: bool
    state: str
    acknowledge: bool
    linked_token: str | None = None


class GooglePlayApi:
    def __init__(self, usage_store):
        self.usage_store = usage_store

    def _request(self, method, path, **kwargs):
        try:
            from google.auth.transport.requests import AuthorizedSession
            credential = self.usage_store._firebase_app().credential.get_credential()
            if hasattr(credential, "with_scopes"):
                credential = credential.with_scopes([SCOPE])
            with AuthorizedSession(credential) as session:
                response = session.request(method, "https://androidpublisher.googleapis.com/androidpublisher/v3/" + path,
                                           timeout=8, **kwargs)
            if response.status_code == 410:
                raise PlayPurchaseGone()
            if response.status_code in (400, 404):
                raise HTTPException(400, "Google Play could not verify this subscription. Use Restore purchases or contact support.")
            if response.status_code >= 400:
                raise HTTPException(503, "Google Play verification is temporarily unavailable. Please try again.")
            return response.json() if response.content else {}
        except HTTPException:
            raise
        except Exception:
            # Never include request URLs, purchase tokens, credentials or upstream bodies.
            raise HTTPException(503, "Google Play verification is temporarily unavailable. Please try again.") from None

    def get(self, token):
        return self._request("GET", f"applications/{PACKAGE_NAME}/purchases/subscriptionsv2/tokens/{quote(token, safe='')}")

    def acknowledge(self, token):
        self._request("POST", f"applications/{PACKAGE_NAME}/purchases/subscriptions/{PRODUCT_ID}/tokens/{quote(token, safe='')}:acknowledge", json={})


def validate_purchase(payload, uid, token, now):
    external = payload.get("externalAccountIdentifiers") or {}
    claimed = external.get("obfuscatedExternalAccountId", "")
    if not isinstance(claimed, str) or not hmac.compare_digest(claimed, account_id(uid)):
        raise HTTPException(403, "This purchase belongs to a different CulinaryAI account. Sign in to the account used to subscribe.")
    items = [item for item in payload.get("lineItems", [])
             if item.get("productId") == PRODUCT_ID and (item.get("offerDetails") or {}).get("basePlanId") == BASE_PLAN_ID]
    if len(items) != 1:
        raise HTTPException(400, "This is not the CulinaryAI Plus monthly subscription.")
    item = items[0]
    expires = timestamp(item.get("expiryTime"))
    state = payload.get("subscriptionState", "")
    active = state in ACTIVE_STATES and expires is not None and expires > now
    if state in ACTIVE_STATES and expires is None:
        raise HTTPException(503, "Google Play returned incomplete subscription details. Please try again.")
    if active and payload.get("acknowledgementState") not in {
        "ACKNOWLEDGEMENT_STATE_PENDING", "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
    }:
        raise HTTPException(503, "Google Play returned incomplete subscription details. Please try again.")
    return VerifiedPurchase(token, now, expires, active, state,
                            active and payload.get("acknowledgementState") == "ACKNOWLEDGEMENT_STATE_PENDING",
                            payload.get("linkedPurchaseToken"))


class PlayPurchaseStore:
    def __init__(self, usage_store):
        self.usage_store = usage_store

    def current(self, uid):
        return self.usage_store.db().collection("billing_entitlements").document(uid).get(timeout=5).to_dict() or {}

    def token(self, purchase_id):
        return self.usage_store.db().collection("billing_play_purchases").document(purchase_id).get(timeout=5).to_dict() or {}

    def apply(self, uid, purchase):
        from firebase_admin import firestore
        db = self.usage_store.db()
        key = token_id(purchase.token)
        purchase_ref = db.collection("billing_play_purchases").document(key)
        entitlement_ref = db.collection("billing_entitlements").document(uid)
        linked_key = token_id(purchase.linked_token) if purchase.linked_token else None
        linked_ref = db.collection("billing_play_purchases").document(linked_key) if linked_key else None

        @firestore.transactional
        def apply(transaction):
            saved = purchase_ref.get(transaction=transaction).to_dict() or {}
            current = entitlement_ref.get(transaction=transaction).to_dict() or {}
            linked = linked_ref.get(transaction=transaction).to_dict() or {} if linked_ref else {}
            if saved.get("uid", uid) != uid or linked.get("uid", uid) != uid:
                raise HTTPException(403, "This purchase is already linked to another account.")
            if saved.get("verified_at") and saved["verified_at"] > purchase.checked_at:
                return  # An older in-flight Google response must not undo a newer one.
            current_key = current.get("purchase_id")
            is_current = current.get("provider") == "google_play" and current_key == key
            replaceable = not current or active_plan(current, purchase.checked_at) == "free" or current_key == linked_key
            grant = not saved.get("superseded_by") and (is_current or (purchase.active and replaceable))
            if purchase.active and not grant and not saved.get("superseded_by"):
                raise HTTPException(409, "An active subscription is already attached to this account. Use Restore purchases.")
            transaction.set(purchase_ref, {
                "uid": uid, "purchase_token": purchase.token, "verified_at": purchase.checked_at,
                "state": purchase.state, "expires_at": purchase.expires_at,
            }, merge=True)
            if grant:
                transaction.set(entitlement_ref, {
                    "provider": "google_play", "purchase_id": key, "plan": "plus",
                    "status": "active" if purchase.active else "inactive",
                    "expires_at": purchase.expires_at, "verified_at": purchase.checked_at,
                })
                if linked_ref and linked_key != key:
                    transaction.set(linked_ref, {"uid": uid, "superseded_by": key}, merge=True)
        apply(db.transaction(max_attempts=5))


class PlayBillingService:
    def __init__(self, usage_store, *, api=None, store=None, clock=None):
        self.api = api or GooglePlayApi(usage_store)
        self.store = store or PlayPurchaseStore(usage_store)
        self.clock = clock or (lambda: datetime.now(timezone.utc))

    def verify(self, uid, token, *, restoring=False):
        if not restoring and not checkout_enabled():
            raise HTTPException(503, "Google Play subscriptions are not available yet.")
        try:
            started_at = self.clock()
            purchase = validate_purchase(self.api.get(token), uid, token, started_at)
            self.store.apply(uid, purchase)
            if purchase.acknowledge:
                # Persist entitlement first. Retries are idempotent if acknowledgment fails.
                self.api.acknowledge(token)
            return purchase
        except HTTPException:
            raise
        except Exception:
            raise HTTPException(503, "Your subscription could not be verified. Please try Restore purchases again.") from None

    def refresh(self, uid):
        """Recheck paid access before every metered request, including refunds/holds."""
        try:
            current = self.store.current(uid)
            if current.get("provider") != "google_play":
                return
            saved = self.store.token(current["purchase_id"])
            if saved.get("uid") != uid or not saved.get("purchase_token"):
                raise ValueError("Missing server-owned purchase record")
            try:
                self.verify(uid, saved["purchase_token"], restoring=True)
            except PlayPurchaseGone:
                # Google stops returning very old expired tokens. Keep Free usable.
                now = self.clock()
                self.store.apply(uid, VerifiedPurchase(saved["purchase_token"], now,
                    current.get("expires_at"), False, "SUBSCRIPTION_STATE_EXPIRED", False))
        except HTTPException:
            raise
        except Exception:
            raise HTTPException(503, "Your subscription could not be checked. Please try again.") from None
