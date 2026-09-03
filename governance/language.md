# Language Guidelines

## Two audiences, two languages

The team communicates with the Trainer, and it communicates with itself. These need not be the same language, and usually should not be.

- **Trainer-facing** — the language the Trainer uses. Onboarding records the preference in `governance/trainer.local.md`.
- **Internal** — one workspace language, chosen at onboarding, used for every task packet, worklog entry, status file, and internal report.

Pick **English** as the workspace language unless there is a specific reason not to. Most CLI tools, error messages, library documentation, and model training weight toward it, and a packet in the same language as the stack it describes loses less in translation.

When the two differ, the default reply shape is: the working body — explanation, analysis, intermediate steps — in the workspace language, followed by a short summary in the Trainer's language. For a brief or conversational message, replying entirely in the Trainer's language is fine.

## Trainer-facing communication

- Use the Trainer's configured form of address.
- Match the Trainer's level of technical familiarity — neither talking down nor hiding behind jargon.
- Preserve each member's voice without sacrificing precision.
- When summarizing an internal result, translate it. Do not hand the Trainer a raw internal packet.

## Internal communication

- Task packets, worklogs, meeting notes, decision records, and status files use the workspace language, unless the artifact is meant for the Trainer.
- Keep identifiers, commands, paths, and code exactly as their tools require. Never translate a symbol.
- When translating, preserve technical meaning and label any unavoidable ambiguity rather than silently choosing one reading.

## Token discipline

Packets sent to members may be telegraphic — drop filler, articles, and pleasantries; prefer lists and tables. Dispatch volume is where token cost accumulates, and prose is where it hides.

**Terseness compresses form, never meaning.** Never drop a technical qualifier, a condition, or a named component. "Wrapped in a payment-provider abstraction" and "managed-first **default**, self-hosting supported" survive compression intact, because removing those words changes what gets built.

Do not apply terseness to:

- Trainer-facing replies; or
- precise specifications — financial rules, security boundaries, authorization logic — where full clarity outranks token savings.

There is no forced terse mode. Each dispatcher applies this judgment per message.

## Pronouns and voice

Each member uses the voice configured in the roster and persona files. A persona's voice affects tone; it never overrides a fact, authorization decision, or safety judgment.

When referring to a person whose pronouns have not been stated — the Trainer included — use they/them. A name does not reveal pronouns, and a wrong guess misgenders a real person in a way the neutral default never does.
