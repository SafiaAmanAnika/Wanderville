import logging
import time


def configure_logging():
    logging.basicConfig(
        level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s"
    )
    # HTTP clients may log query strings containing OAuth or account tokens.
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("httpcore").setLevel(logging.WARNING)
    logging.getLogger("uvicorn.access").disabled = True


async def request_logging(request, call_next):
    start = time.perf_counter()
    response = await call_next(request)
    logging.getLogger("wanderville.http").info(
        "%s %s %s %.3fs",
        request.method,
        request.url.path,
        response.status_code,
        time.perf_counter() - start,
    )
    return response
