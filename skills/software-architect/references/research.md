# Software architect skill: research notes

Researched 2026-10-16. Scope: a reusable skill for Codex and Claude Code, focused
on object-oriented Python, modern C++, Rust, and embedded systems.
The skill's defaults are an engineering synthesis of the sources below and the
requested preferences, rather than a universal embedded coding standard.

## Main findings

**Use SOLID with composition and explicit ownership.** Prefer a few cohesive
components with narrow contracts. An interface is valuable at a real hardware,
testing, or change boundary; every class does not need an abstract counterpart.
Robert C. Martin's original discussion explains substitutability, dependency
inversion, and interface segregation; his SOLID overview identifies all five
principles. These are design principles, distinct from named implementation
patterns such as Strategy or Adapter.
[Principles and Patterns](https://objectmentor.com/resources/articles/Principles_and_Patterns.pdf),
[SOLID overview](https://cleancoder.com/files/solid.md).

**Modern object orientation can avoid the heap.** The C++ Core Guidelines prefer
concrete types, scoped objects, and RAII. They explicitly explain that a virtual
interface can refer to an object in existing storage, including in systems that
prohibit dynamic allocation. Thus a blanket ban on virtual methods does not follow
from a heap ban. Assess dispatch latency and code size on the actual target.
[C++ Core Guidelines: C.10](https://isocpp.github.io/CppCoreGuidelines/CppCoreGuidelines#Rc-concrete),
[resource management](https://isocpp.github.io/CppCoreGuidelines/CppCoreGuidelines#S-resource).

**Choose predictable resource use even with generous RAM.** Fixed capacities make
exhaustion visible in the design. Rust's `heapless` collections keep storage inline
and return errors when capacity is exceeded; their backing object can live in
different memory regions. Fixed capacity does not require a stack allocation.
Our recommended firmware default is fixed storage and no general-purpose heap
activity during operation, with startup-only allocation permitted only by project
policy. Pools remain allocation mechanisms and need their own exhaustion rules.
[heapless documentation](https://docs.rs/heapless/latest/heapless/).

## Language choices

| Language | Object-oriented design | Memory and timing implications |
| --- | --- | --- |
| Python on a host or embedded Linux | Small classes, composition, constructor injection, typed `Protocol` contracts | Suitable for tooling, tests, and supervision; use a separate native component for strict deterministic control. |
| MicroPython | Small persistent objects, simple interfaces, preallocated I/O buffers | Audit interpreter operations and GC; do not assume CPython modules or typing facilities exist. |
| Modern C++ | Value types, RAII, concrete composition, templates or narrow virtual interfaces | Audit library allocations and borrowed lifetimes; follow the target's compiler and exception policy. |
| Rust | Structs, traits, enums, ownership, selective typestate | Static or borrowed dynamic dispatch; bounded collections and deliberate panic policy. |

Python `Protocol` supports structural typing: a type can satisfy an interface
without inheriting from it. It primarily serves static checking, so it does not
establish behavioral or timing guarantees.
[Python typing documentation](https://docs.python.org/3/library/typing.html#typing.Protocol).

Python's ordinary data model relies on objects with managed lifetimes. Treating
CPython as a general no-allocation runtime is therefore an unsuitable architectural
assumption. The recommendation to keep strict control loops native follows from
this model and the requested timing/allocation constraints.
[Python data model](https://docs.python.org/3/reference/datamodel.html#objects-values-and-types).

MicroPython's interrupt guidance forbids creating heap objects in hard ISRs and
recommends preallocated buffers. Even constructing a bound-method reference can
allocate. Its performance guide explains that constructing or slicing a
`memoryview` also allocates, despite avoiding a copy of the underlying bytes.
Preallocate the views and callback references as well as the buffers. Avoid
treating disabled GC as proof that allocation cannot occur.
[Interrupt handlers](https://docs.micropython.org/en/latest/reference/isr_rules.html),
[MicroPython performance](https://docs.micropython.org/en/latest/reference/speed_python.html).

Rust `no_std` removes the standard-library assumption; allocation remains
possible through `alloc` with allocator support. A borrowed trait object such as
`&mut dyn Sensor` can use runtime dispatch without allocating a `Box`. Generic
dispatch trades runtime flexibility for specialization, which may increase flash
use. Typestate encodes selected states in types and can prevent operations before
configuration, but a simple enum is often enough for ordinary runtime modes.
[Embedded Rust: no_std](https://docs.rust-embedded.org/book/intro/no-std.html),
[trait objects](https://doc.rust-lang.org/book/ch18-02-trait-objects.html),
[typestate](https://docs.rust-embedded.org/book/static-guarantees/typestate-programming.html).

Reuse established hardware interfaces where they fit. `embedded-hal` aims for
minimal, composable, device-independent driver contracts with explicit errors.
Check the execution model: its core traits are blocking; async and nonblocking
variants live in companion crates. Reuse does not require a new interface layer
around every existing HAL trait.
[embedded-hal design goals](https://docs.rs/embedded-hal/latest/embedded_hal/).

## Patterns worth considering

These choices are the study's recommendations, not a ranking established by a
benchmark or a requirement to apply every pattern.

| Pattern or technique | Embedded use | Keep it bounded |
| --- | --- | --- |
| Adapter | Isolate vendor HAL or protocol details | Keep registers and vendor types out of control policy where practical. |
| Strategy | Swap a sensor, transport, or control algorithm | Inject an existing object, policy, trait, or callable. |
| State machine | Device lifecycle, protocol, fault recovery | Start with an enum and explicit transitions. |
| RAII / ownership | Peripheral, lock, transaction, resource lifetime | Keep cleanup valid and bounded for its execution context. |
| Observer / callbacks | Required event fan-out | Bound subscribers; define unsubscription, reentrancy, and lifetime. |
| Pool / arena | Necessary variable lifetimes in fixed storage | Specify capacity, alignment, reclamation, and failure; it is still allocation. |

Use more memory for deliberate buffer capacity and headroom where useful.
Choose capacity from burst and service requirements, and choose overflow behavior
from message semantics. Reserve complex factories, global event buses, and
frameworks for demonstrated requirements.

## One skill for Codex and Claude Code

Both support a folder containing `SKILL.md` with YAML metadata and Markdown
instructions. Keep the common `name` and `description` fields, a precise trigger,
and a compact instruction body. Load this research reference only when needed.
The two products support additional metadata with different meanings, so the
shared skill avoids vendor-specific tool permissions, command interpolation,
and agent orchestration.
[OpenAI skill documentation](https://learn.chatgpt.com/docs/build-skills),
[Claude Code skill documentation](https://code.claude.com/docs/en/skills).

The repository's `skills/software-architect/` folder is the portable source;
merely saving it here does not install it in either tool's discovery directory.
For local use, copy or symlink the whole folder into a documented location:

| Tool | Project location | Personal location | Explicit invocation |
| --- | --- | --- | --- |
| Codex | `.agents/skills/software-architect/` | `~/.agents/skills/software-architect/` | `$software-architect` |
| Claude Code | `.claude/skills/software-architect/` | `~/.claude/skills/software-architect/` | `/software-architect` |

Both document symlinked skill directories. Existing Codex installations may use
legacy locations; check the installed version before changing an existing setup.
[Codex discovery locations](https://learn.chatgpt.com/docs/build-skills#where-codex-loads-local-skills),
[Claude discovery locations](https://code.claude.com/docs/en/skills#choose-where-skills-load).

Example request after installation:

> Review this sensor controller using software-architect. Prefer SOLID and
> composition. No heap activity after startup; explain ownership, queue capacity,
> failure behavior, and which timing assumptions need target measurements.

## Lightweight evaluation

Try the same representative requests in both tools. Check the decisions and
proposed code rather than looking for particular wording:

- **C++ RTOS sensor controller:** It should allow a small virtual interface over
  existing objects, identify ownership and buffer limits, and avoid a DI container.
- **Rust no_std driver:** It should reuse a suitable HAL trait, handle full buffers,
  and avoid assuming `no_std` automatically rules out heap use in dependencies.
- **Python telemetry supervisor:** It should use ordinary Python composition while
  identifying a separate boundary for any strict real-time requirement.
- **MicroPython interrupt callback:** It should notice hidden allocation from
  callback references or view construction and move that setup before interrupts.

These are evaluation scenarios, not completed cross-tool behavioral tests.
Verify actual code with the project's compiler/runtime versions; documentation
examples, especially older embedded-book snippets, can target older APIs.
