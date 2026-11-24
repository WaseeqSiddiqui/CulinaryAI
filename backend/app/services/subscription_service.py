"""Trusted subscription entitlements and atomic monthly AI usage accounting."""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
import json
import logging
import os
from threading import Lock
from uuid import uuid4

from fastapi import HTTPException

log = logging.getLogger(__name__)
PLAN_LIMITS = {"free": {"chat": 20, "photo": 3}, "plus": {"chat": 500, "photo": 50}}
READINESS_UID = "culinary-subscription-readiness-v1"


class SubscriptionSetupError(RuntimeError):
    """Only fixed stage names and exception types; never credential contents."""
    def __init__(self, stage, error_type):
        super().__init__(f"{stage} ({error_type})")


def usage_limits_enabled():
    return os.getenv("USAGE_LIMITS_ENABLED", "true").strip().lower() != "false"


def period_at(now):
    return now.strftime("%Y-%m")


def next_reset(now):
    return datetime(now.year + (now.month == 12), now.month % 12 + 1, 1, tzinfo=timezone.utc)


def active_plan(entitlement, now):
    expires = entitlement.get("expires_at")
    if isinstance(expires, str):
        try:
            expires = datetime.fromisoformat(expires.replace("Z", "+00:00"))
        except ValueError:
            expires = None
    if isinstance(expires, datetime) and expires.tzinfo is None:
        expires = expires.replace(tzinfo=timezone.utc)
    if entitlement.get("plan") == "plus" and entitlement.get("status") == "active" and isinstance(expires, datetime) and expires > now:
        return "plus"
    return "free"


def usage_snapshot(entitlement, usage, now):
    plan = active_plan(entitlement, now)
    return {
        "plan": plan, "period": period_at(now), "resets_at": next_reset(now).isoformat(),
        "limits": PLAN_LIMITS[plan],
        "used": {kind: max(0, int(usage.get(kind, 0))) for kind in ("chat", "photo")},
        "checkout_enabled": False,
    }


def check_allowance(snapshot, kind):
    if snapshot["used"][kind] >= snapshot["limits"][kind]:
        raise HTTPException(status_code=429, detail={
            "code": "quota_exceeded", "kind": kind, "plan": snapshot["plan"],
            "used": snapshot["used"][kind], "limit": snapshot["limits"][kind],
            "resets_at": snapshot["resets_at"],
            "message": f"Your monthly {'Chef request' if kind == 'chat' else 'photo scan'} allowance is used up.",
        })


@dataclass(frozen=True)
class UsageReservation:
    id: str
    uid: str
    period: str
    kind: str


class FirestoreUsageStore:
    def __init__(self):
        self._app = None
        self._database = None
        self._lock = Lock()
        self._credential_error_type = None

    def _firebase_app(self):
        if self._app is not None:
            return self._app
        with self._lock:
            if self._app is not None:
                return self._app
            try:
                import firebase_admin
                from firebase_admin import credentials
                value = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON", "").strip()
                credential = credentials.Certificate(json.loads(value)) if value else credentials.ApplicationDefault()
                credential.get_credential()
                project = os.getenv("FIREBASE_PROJECT_ID", "culinaryai-518b3")
                if getattr(credential, "project_id", project) != project:
                    raise ValueError("Firebase credential project does not match the configured project")
                self._app = firebase_admin.initialize_app(credential, {
                    "projectId": project, "httpTimeout": 5,
                }, name="culinary-subscriptions")
            except Exception as error:
                self._credential_error_type = type(error).__name__
                raise HTTPException(status_code=503, detail="Account usage is temporarily unavailable. Please try again later.") from None
        return self._app

    def verify_user(self, authorization):
        if not authorization or not authorization.startswith("Bearer "):
            raise HTTPException(status_code=401, detail="Sign in to use your monthly AI allowance.")
        app = self._firebase_app()
        try:
            from firebase_admin import auth
            token = auth.verify_id_token(authorization[7:].strip(), app=app, check_revoked=True)
            uid = token["uid"]
            if not isinstance(uid, str) or not uid or "/" in uid:
                raise ValueError("Invalid account")
            return uid
        except Exception:
            raise HTTPException(status_code=401, detail="Your session has expired. Please sign in again.") from None

    def check_ready(self):
        """Verify Auth access and Firestore transactions before accepting traffic."""
        from firebase_admin import auth
        # Firestore reserves IDs matching __.*__; use an ordinary service ID.
        # No real user's credits are used by this refunded startup reservation.
        try:
            app = self._firebase_app()
        except Exception as error:
            raise SubscriptionSetupError("credentials", self._credential_error_type or type(error).__name__) from None
        try:
            auth.get_user(READINESS_UID, app=app)
        except auth.UserNotFoundError:
            pass
        except Exception as error:
            raise SubscriptionSetupError("Firebase Auth access", type(error).__name__) from None
        try:
            reservation = self.reserve(READINESS_UID, "chat", datetime.now(timezone.utc))
        except Exception as error:
            raise SubscriptionSetupError("Firestore reservation", type(error).__name__) from None
        try:
            self.finish(reservation, success=False)
        except Exception as error:
            raise SubscriptionSetupError("Firestore refund", type(error).__name__) from None

    def db(self):
        if self._database is None:
            try:
                from firebase_admin import firestore
                self._database = firestore.client(app=self._firebase_app())
            except HTTPException:
                raise
            except Exception:
                raise HTTPException(status_code=503, detail="Account usage is temporarily unavailable. Please try again later.") from None
        return self._database

    def _refs(self, uid, period):
        db = self.db()
        return db.collection("billing_entitlements").document(uid), db.collection("billing_usage").document(uid).collection("months").document(period)

    def view(self, uid, now):
        entitlement, usage = self._refs(uid, period_at(now))
        return usage_snapshot(entitlement.get(timeout=5).to_dict() or {}, usage.get(timeout=5).to_dict() or {}, now)

    def reserve(self, uid, kind, now):
        from firebase_admin import firestore
        db = self.db()
        entitlement_ref, usage_ref = self._refs(uid, period_at(now))
        reservation = UsageReservation(uuid4().hex, uid, period_at(now), kind)
        reservation_ref = db.collection("billing_reservations").document(reservation.id)

        @firestore.transactional
        def apply(transaction):
            entitlement = entitlement_ref.get(transaction=transaction).to_dict() or {}
            usage = usage_ref.get(transaction=transaction).to_dict() or {}
            snapshot = usage_snapshot(entitlement, usage, now)
            check_allowance(snapshot, kind)
            transaction.set(usage_ref, {kind: snapshot["used"][kind] + 1, "updated_at": firestore.SERVER_TIMESTAMP}, merge=True)
            transaction.set(reservation_ref, {**reservation.__dict__, "state": "reserved", "created_at": firestore.SERVER_TIMESTAMP})
        apply(db.transaction(max_attempts=5))
        return reservation

    def finish(self, reservation, *, success):
        from firebase_admin import firestore
        db = self.db()
        _, usage_ref = self._refs(reservation.uid, reservation.period)
        reservation_ref = db.collection("billing_reservations").document(reservation.id)

        @firestore.transactional
        def apply(transaction):
            saved = reservation_ref.get(transaction=transaction).to_dict() or {}
            if saved.get("state") != "reserved":
                return
            if not success:
                usage = usage_ref.get(transaction=transaction).to_dict() or {}
                transaction.set(usage_ref, {reservation.kind: max(0, int(usage.get(reservation.kind, 0)) - 1)}, merge=True)
            transaction.update(reservation_ref, {"state": "charged" if success else "refunded", "finished_at": firestore.SERVER_TIMESTAMP})
        apply(db.transaction(max_attempts=5))


class SubscriptionService:
    def __init__(self, store=None, clock=None):
        self.store = store or FirestoreUsageStore()
        self.clock = clock or (lambda: datetime.now(timezone.utc))

    def verify_user(self, authorization):
        return self.store.verify_user(authorization)

    def check_ready(self):
        try:
            self.store.check_ready()
        except Exception as error:
            reason = str(error) if isinstance(error, SubscriptionSetupError) else type(error).__name__
            raise RuntimeError(
                f"Monthly usage setup failed at {reason}. Check Firebase server credentials, project ID, "
                "Auth access, and Firestore permissions before deploying."
            ) from None

    def view(self, uid):
        try:
            return self.store.view(uid, self.clock())
        except HTTPException:
            raise
        except Exception:
            raise HTTPException(status_code=503, detail="Account usage is temporarily unavailable. Please try again.") from None

    def reserve(self, uid, kind):
        try:
            return self.store.reserve(uid, kind, self.clock())
        except HTTPException:
            raise
        except Exception:
            raise HTTPException(status_code=503, detail="Your allowance could not be checked. Please try again.") from None

    def finish(self, reservation, *, success):
        try:
            self.store.finish(reservation, success=success)
        except Exception:
            # Reservations are retained so an operator can reconcile a failed refund.
            log.error("Could not finalize AI usage reservation %s", reservation.id)
