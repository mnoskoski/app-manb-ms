from fastapi import FastAPI

from app.api.routes import health
from app.core.config import get_settings

settings = get_settings()

app = FastAPI(title=settings.app_name, version=settings.app_version)

app.include_router(health.router)


@app.get("/")
async def root() -> dict[str, str]:
    return {"service": settings.app_name, "environment": settings.environment, "status": "running"}
