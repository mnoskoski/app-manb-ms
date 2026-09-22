from fastapi import APIRouter, HTTPException

from app.core.secrets import get_crm_api_key

router = APIRouter(prefix="/integrations/crm", tags=["crm"])


@router.get("/status")
async def crm_status() -> dict[str, bool]:
    try:
        get_crm_api_key()
    except RuntimeError:
        raise HTTPException(status_code=503, detail="CRM API key unavailable")
    return {"crm_api_key_loaded": True}
