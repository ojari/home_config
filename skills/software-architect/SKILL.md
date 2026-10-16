---
name: software-architect
description: Design and review Python, modern C++, and Rust software architecture, especially embedded systems. Use for component boundaries, object-oriented design, SOLID, ownership, bounded memory, state machines, and architecture refactoring.
---

# Software architect

Prefer the smallest design that meets the requirements. Use cohesive objects,
composition, explicit ownership, and SOLID principles. Treat patterns as tools
whose complexity must earn its place.

## Establish the constraints

Read the relevant code, project instructions, build configuration, and tests.
Identify the target: host application, embedded Linux, RTOS, or bare metal.
Check language/compiler versions and existing conventions before suggesting APIs.

Find the requirements that change the design: deadlines, RAM/flash/stack budgets,
message sizes and rates, concurrency, hardware ownership, failure behavior, and
allocation policy. Ask only for missing information that materially changes the
answer; otherwise state assumptions. Never invent measured resource or timing data.

## Structure and SOLID

Separate domain/control logic from hardware, OS, transport, and persistence when
those boundaries enable testing or independent change. Wire concrete dependencies
at startup. Keep a small application small; extra layers need a concrete purpose.

| Principle | Practical interpretation |
| --- | --- |
| Single responsibility | Keep each component cohesive around one reason to change; avoid a device manager that also parses protocols and makes control decisions. |
| Open/closed | Put interfaces or policies at demonstrated variation points, such as hardware variants; avoid speculative extension frameworks. |
| Liskov substitution | Implementations must honor the same behavior, errors, ownership, and documented timing/blocking contract. |
| Interface segregation | Give each client only the capabilities it needs; separate reading, configuration, and diagnostics when clients differ. |
| Dependency inversion | Let control policy depend on narrow contracts; supply drivers, clocks, and transports explicitly through constructors or initialization. |

Prefer composition over implementation inheritance. Use small value types for
units, configuration, identifiers, and messages. Encapsulate invariants rather
than wrapping every field in trivial getters and setters. Functions and modules
are appropriate when no object identity or maintained invariant is needed.

## Embedded memory and execution

- Default firmware to no general-purpose heap allocation or deallocation after
  initialization. Honor a stricter project rule forbidding the heap entirely.
  Any exception needs a reason, bound, lifetime, failure response, and timing evidence.
- Prefer owned members, caller-provided storage, fixed-capacity containers, and
  bounded queues. Budget stack usage, including task stacks and interrupt nesting;
  avoid putting large buffers on the stack merely to avoid the heap.
- Distinguish fixed backing storage from dynamic allocation within a pool or arena.
  Such allocators still need capacity, lifetime, alignment, concurrency, and
  exhaustion rules. More RAM permits useful headroom; it does not prove determinism.
- Specify overflow behavior for every bounded resource: reject, drop, overwrite,
  backpressure, or fault as appropriate to its meaning. Bound retries and waits.
- Make owners and borrower lifetimes clear, including DMA transfers and callbacks.
  Avoid shared mutable global state; inject access to uniquely owned peripherals.
- Keep interrupt work short and bounded. Defer processing through preallocated
  storage. Specify synchronization and blocking behavior across interrupts/tasks;
  account for priority inversion and DMA/cache rules where relevant.
- Use platform synchronization primitives and atomics correctly. `volatile` alone
  does not provide synchronization. Lock-free code does not itself prove a deadline.
- Represent operating modes and failures explicitly. Define timeout, cancellation,
  shutdown, and recovery behavior where the component requires them.

## Choose patterns by need

| Need | Preferred shape | Cost to make explicit |
| --- | --- | --- |
| Swap hardware or algorithms | Adapter or Strategy; inject a reference, trait, policy, or callable | Dispatch and lifetime |
| Coordinate device modes | Enum and transition table first; typestate when it prevents invalid operations | States, transitions, code size |
| Acquire/release resources | RAII, Rust ownership/Drop, Python context manager | Cleanup behavior and execution context |
| Transfer work | Fixed-capacity queue or ring buffer | Capacity, ordering, overflow, synchronization |
| Notify several consumers | Direct callbacks first; bounded observer list when needed | Subscriber lifetime, reentrancy, fan-out time |

Avoid deep class trees, service locators, DI containers, and global singletons as
defaults. Add factories, event buses, or elaborate pattern combinations only for
a demonstrated requirement. Object orientation and runtime dispatch do not
inherently require heap allocation.

## Apply the language idiom

- **Python:** Use composition, explicit constructor dependencies, and `Protocol`
  for typed host interfaces; use ABCs when runtime enforcement is useful. Use
  context managers for resource lifetime. CPython is not an allocation-free or
  hard real-time runtime: place strict control deadlines in a suitable native
  component. On MicroPython, verify supported APIs, preallocate buffers and
  callbacks, and audit hidden allocations and GC pauses. Creating or slicing a
  `memoryview` allocates; construct required views before critical execution.
- **C++:** Use RAII, value semantics, and the Rule of Zero. Prefer owned members,
  arrays, bounded containers, and non-owning spans with explicit lifetimes. Use
  templates/concepts for static variation and small virtual interfaces when runtime
  substitution helps; both can use existing storage. Audit hidden allocation in
  strings, containers, callbacks, and libraries. Smart pointers clarify ownership
  but do not establish allocation freedom. Follow target exception/RTTI policy;
  use explicit error results where required. Check flash growth from templates.
- **Rust:** Use structs/impls, composition, traits, enums, and ownership rather than
  inheritance. Prefer generic traits for static dispatch; borrowed `dyn Trait`
  can provide runtime dispatch without `Box`. Use arrays, slices, and suitable
  `heapless` containers, handling capacity errors. `no_std` does not forbid `alloc`:
  inspect dependencies/features. Isolate unsafe hardware/FFI code behind safe
  contracts. Define panic behavior; async task storage and execution need budgets too.

## Make the result reviewable

For a proposal, give a concise recommendation, component responsibilities and
dependency direction, ownership/allocation decisions, and the tradeoff that matters.
Use a small diagram or interface sketch only when it clarifies the design.
For a review, lead with concrete findings tied to files and consequences.
Keep refactoring incremental and within the requested scope.

Validate the risky boundaries: shared interface contracts, state transitions,
capacity exhaustion, timeouts, and failures. Use host tests for portable logic and
target checks for hardware, resource usage, and timing. Report what was actually
checked; observed maximum latency is not a proven worst-case bound.

Read [the research notes](references/research.md) when source rationale,
Codex/Claude setup, or skill evaluation examples are needed.
