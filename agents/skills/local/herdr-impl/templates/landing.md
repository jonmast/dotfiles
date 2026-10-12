{{! integration: the integration branch }}
{{! landed: the landed tickets since this worker spawned, each as title and one-line intent }}
Your turn to land. Rebase this branch onto {{integration}}, which now holds these landed tickets: {{landed}}.

Resolve any conflicts so your ticket's behaviour and theirs both survive; editing their code is in scope for this. Then run the full test suite.

Report: each conflicted file and how you resolved it, the test result, whether `git status` is clean, and any resolution you are unsure of.
