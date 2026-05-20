# Agent rules for taiya/carla

## No internal references in commits or pushes

**Do not commit or push any content that references internal infrastructure,
company names, internal hostnames, registry URLs, storage accounts, cluster
names, or any other non-public identifiers.**

Specifically, never include in any committed file:
- Registry hostnames such as `*.azurecr.io` or any variant
- Azure storage account names
- Internal cluster, project, or team names
- Employee usernames or email addresses beyond what is already public

`common.mk` is the designated escape hatch for site-local targets that must
reference internal infrastructure. It is listed in `.gitignore` and must
never be committed.
