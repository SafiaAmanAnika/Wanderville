from app.database import Base, engine

# Import models so they are registered with SQLAlchemy metadata.
from app import models as _models  # noqa: F401


def main() -> None:
    Base.metadata.create_all(bind=engine)
    print("Database initialized.")


if __name__ == "__main__":
    main()
