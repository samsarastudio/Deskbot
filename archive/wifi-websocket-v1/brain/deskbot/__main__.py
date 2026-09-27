from __future__ import annotations

from deskbot.gateway.server import create_app
from deskbot.settings import get_settings


def main() -> None:
    import uvicorn

    settings = get_settings()
    uvicorn.run(
        create_app(settings),
        host=settings.server.host,
        port=settings.server.port,
        log_level="info",
    )


if __name__ == "__main__":
    main()
