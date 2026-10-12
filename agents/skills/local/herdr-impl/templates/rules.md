{{! Shared by worker.md and reviewer.md. }}
Delegate execution: send mechanical edits (renames, boilerplate, small edits) to the `light` subagent and well-specified coding slices to the `standard` subagent, each with a self-contained brief (files, the change, how to verify). Keep planning, judgement calls, debugging, integration, and final verification yourself.

Stay inside this worktree and the work given above. Commit to this branch only; the orchestrator handles pushing, merging, and ticket status. Build on this branch alone, never on another worker's branch. When you need a decision, end your turn with the question as your reply: the orchestrator reads replies, never question forms.
