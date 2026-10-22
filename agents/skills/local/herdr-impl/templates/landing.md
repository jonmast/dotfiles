{{! integration: the integration branch }}
{{! landed: the tickets landed since this worker spawned or last rebased, each as title and one-line intent }}
{{! early: set to 1 when other workers land ahead of this one }}
{{! final: set to 1 when this worker is next to land }}
{{! dropped: the range of a landing rolled back after this worker rebased onto it }}
{{! one-of: early final }}
Rebase this branch onto {{integration}} to land it. Since you spawned or last rebased, it has gained these landed tickets:
{{landed}}

{{?dropped}}The landing {{dropped}} failed its verify and was rolled back from {{integration}}, but your branch is rebased onto it. Drop its commits: rebase with `git rebase --onto {{integration}} <the range's end>`, so only your own commits are replayed.

{{?early}}Others land ahead of you, so this rebase is early: you'll get another turn to catch up on them.

Before rebasing, note `git merge-base HEAD {{integration}}`: their side is that commit up to {{integration}}, your side is your own commits. Resolve any conflicts so your ticket's behaviour and theirs both survive; editing their code is in scope for this.

{{?early}}Then run the repo's static checks (codegen, typecheck, lint) and stop; tests wait for your catch-up turn.
{{?final}}Then run the repo's static checks (codegen, typecheck, lint) and the tests covering the files changed on either side. After a conflict, add the tests covering every conflicted file and what calls into it. The full suite runs once you land, so don't run it here.

Report: each conflicted file and how you resolved it, or "conflict-free"; what you ran and the result; whether `git status` is clean; and any resolution you are unsure of.
