# Ubiquitous Language

> Canonical glossary for **rigorix-sdk**.
> All code MUST use these terms. Aliases/synonyms listed below are **prohibited** in source identifiers.
> Drift is detected by `.pi/scripts/validate-ubiquitous-language.sh`.

## Glossary

| Term | Definition | Bounded Context | Aliases/Synonyms | Examples |
|------|-----------|----------------|-----------------|---------|
| <!-- Add your terms here --> |  |  |  |  |
| <!-- Format: | TermName | What it means | ModuleName | Alias1, Alias2 | `code example` | --> |

## Adding New Terms

1. Identify the term used in conversation and code
2. Add a row to the Glossary table
3. Define the term's **bounded context** (which module it lives in)
4. List any **aliases/synonyms** that agents might mistakenly use
5. Provide **code examples** showing correct usage
6. Run `.pi/scripts/validate-ubiquitous-language.sh` to detect drift

> **Rule of thumb:** If two agents use different names for the same concept, add an entry.
> The canonical term is the one used in the architecture module documents.

## Term Conflicts (language gaps)

When the same term is used with different meanings by different parts of the
business (e.g. "transaction" = a database transaction for engineers but a
statement line for the business), that is a bounded-context boundary signal —
record the conflict here and resolve it in the exploration review:

| Term A | Term B | Why conflicting | Resolution |
|--------|--------|-----------------|-----------|
| <!-- e.g. Transaction | Booking | engineering vs business meaning | adopt "Booking" in Billing context --> |

