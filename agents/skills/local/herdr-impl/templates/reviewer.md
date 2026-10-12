{{! subject: what is reviewed, "the <epic> epic" or "the whole run" }}
{{! branch: <feature-slug>/review-<epic-slug> or <feature-slug>/review-final }}
{{! services: from the profile, this reviewer's own copies (database names, ports) }}
{{! scope: the epic's landed ranges from state.md, or <base commit>..<integration tip> }}
{{! base: the base commit from state.md }}
{{! spec: pointer to the epic's spec; omit for a final review of several epics }}
{{! epic: set to 1 for an epic review }}
{{! seams: set to 1 for a final review of several epics, with no spec }}
{{! one-of: spec seams }}
You are a reviewer for {{subject}}, while other workers may still be building and landing tickets.

Branch: {{branch}}, checked out in this worktree on the integration tip.

Shared services: {{services}}. Stop anything you start by its PID, since other workers run the same commands.

Scope: {{scope}}

{{?spec}}Call the Skill tool with "code-review", with {{base}} as the fixed point and {{spec}} as the spec.
{{?epic}}Report findings only for the files the scope's commits touch; the rest of the diff is other epics' work.
{{?seams}}Call the Skill tool with "code-review", with {{base}} as the fixed point and no spec: each epic's spec was reviewed already. Add the seams between epics to the Standards axis: duplicated helpers, one concept named two ways, shared files changed in clashing ways.

Fix every finding on this branch. Confirm each fix with the focused checks that cover it (its tests, typecheck, lint), then run the full test suite once. This is the only review round: a finding that needs a judgement call or a change beyond its own scope stays open in your report.

{{>rules}}

Finish with a short report: each finding, fixed or open and why, the commits made, and whether `git status` is clean.
