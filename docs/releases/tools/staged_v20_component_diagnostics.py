"""Use the same pinned, read-only audit with component-only output."""
from staged_v20_audit import main


if __name__ == "__main__":
    main(default_mode="components")
