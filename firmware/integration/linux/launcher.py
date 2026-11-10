"""Entry point for the staged Linux development probe; run with python3 -I."""
from pathlib import Path
import sys

# Isolated mode ignores user site-packages and environment Python paths. The
# integration package is loaded only from this launcher's installation directory.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from airlink.board_probe import main

if __name__ == '__main__':
    main()
