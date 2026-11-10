# VM Overview

Muse runs on a Linux virtual machine. The machine can reboot without warning, and a reboot kills every live lane. The notes record 12 all-lane deaths so far.

The restart script brings lanes back in about four minutes. This means continuity depends on recovery rather than on assuming a process will live forever.

The VM is one part of the larger system: memory survives in files, running processes do not, and skills/connectors provide the playbooks and connected accounts that let work continue.
