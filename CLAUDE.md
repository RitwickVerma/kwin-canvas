# kwin-canvas

The instructions for working in this repository are in **[AGENTS.md](AGENTS.md)**.
Read that first: it holds the commands, the verification ladder, the conventions,
the deliberate choices and the traps. This file is only a pointer, so that a tool
which looks for `CLAUDE.md` does not need a second copy that can drift away from
the first.

The shortest version: never test in the live session (`make test` and `make play`
use a nested KWin), keep `make lint` green, say in the commit what you verified,
and leave [docs/status.md](docs/status.md) current.
