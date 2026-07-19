from fastapi import FastAPI

app = FastAPI(
    title="Bedoux Commerce Cloud API",
    description=(
        "Products and orders API for the Bedoux Commerce Cloud reference "
        "implementation. See docs/IMPLEMENTATION-PLAN.md for scope."
    ),
    version="0.1.0",
)


@app.get("/health")
def health() -> dict[str, str]:
    """Liveness/readiness probe target. Must never touch the database."""
    return {"status": "ok"}
