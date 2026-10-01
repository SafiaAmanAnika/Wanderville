import uvicorn

from app.core.config import settings

if __name__ == "__main__":
    uvicorn.run(
        "app.main:app",
        host=settings.wanderville_host,
        port=settings.wanderville_port,
        access_log=False,
    )
