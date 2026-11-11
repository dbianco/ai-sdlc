# SDLC Artifacts

This workspace runs the `sdlc` plugin in local mode. Every PRD, Scoping
Doc, Jot Down, Data UI Inventory, and task lives here as markdown instead
of in Notion and Jira/Linear.

```
features/
└── 001-example-feature/
    ├── prd.md
    ├── scoping-doc.md
    ├── jotdown.md
    └── tasks/
        ├── README.md          # sequencing, critical path, coverage
        └── 001-first-task.md
```

These files are the specification — commit them.

To switch to Notion and Jira/Linear, run `/sdlc:sdlc-workspace-init --switch-mode`.
Existing files stay on disk; they are not migrated.
