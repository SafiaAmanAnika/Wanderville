from pathlib import Path

import pytest


@pytest.fixture(scope="session", autouse=True)
def cleanup_test_dbs():
    """Delete all test *.db files after the test session completes."""
    yield
    test_dir = Path(__file__).resolve().parent
    for db_path in test_dir.glob("*.db"):
        try:
            db_path.unlink()
        except OSError:
            pass
    root_dir = test_dir.parent
    for db_path in root_dir.glob("*.db"):
        if db_path.name.startswith("test_"):
            try:
                db_path.unlink()
            except OSError:
                pass
