import asyncio

from fastapi import HTTPException
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import JSONResponse
from app.services.subscription_service import usage_limits_enabled


TEXT_PATHS = {"/chef-chat", "/step-explanation", "/cooking-step-chat", "/match-product", "/normalize-shopping-query"}
PHOTO_PATHS = {"/parse-receipt", "/scan-fridge", "/analyze-meal", "/validate-cooking-step"}


class UsageLimitMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, service):
        super().__init__(app)
        self.service = service

    async def dispatch(self, request, call_next):
        path = request.url.path
        # Only an explicit staging opt-out may bypass enforcement.
        enabled = usage_limits_enabled()
        if not enabled or request.method != "POST" or path not in TEXT_PATHS | PHOTO_PATHS:
            return await call_next(request)
        try:
            uid = await asyncio.to_thread(self.service.verify_user, request.headers.get("authorization"))
            request.state.user_id = uid
            reservation = await asyncio.to_thread(self.service.reserve, uid, "photo" if path in PHOTO_PATHS else "chat")
        except HTTPException as error:
            headers = {"X-Usage-Limit": "exceeded"} if error.status_code == 429 else None
            return JSONResponse(status_code=error.status_code, content={"detail": error.detail}, headers=headers)
        try:
            response = await call_next(request)
        except BaseException:
            await asyncio.shield(asyncio.to_thread(self.service.finish, reservation, success=False))
            raise
        refund = response.headers.get("X-AI-Usage-Refund") == "1"
        if "X-AI-Usage-Refund" in response.headers:
            del response.headers["X-AI-Usage-Refund"]
        await asyncio.to_thread(self.service.finish, reservation, success=response.status_code < 400 and not refund)
        response.headers["X-Usage-Updated"] = "1"
        return response
