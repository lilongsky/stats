# Calendar performance and verification scope

The first continuous-scrolling implementation recreated 336 date views, week
numbers and a constraint-based grid whenever its date buffer moved. Profiling
found long pauses on the main thread during that work.

The current implementation keeps a fixed pool of date and week-number views,
places them directly in a regular grid and updates their date content in place.
It preserves the visible week and within-row offset when the buffer moves.
Month calculations are skipped within the same week anchor, and hover lookup
uses the pointer's row and column.

## Controlled results

The same optimized-production-code benchmark was run before and after the change
in an isolated AppKit window on Apple Silicon:

| Main-thread work | Initial implementation | Reusable date views |
| --- | ---: | ---: |
| Median buffer rebase | 118.50 ms | 2.51 ms |
| Slowest rebase in 12 samples | 306.10 ms | 3.47 ms |
| Slowest scroll step in 600 samples | 357.01 ms | 2.97 ms |

These measurements include event handling and layout. They do not include
physical display frame pacing, input-to-display latency or a hardware trackpad
gesture. Re-run the benchmark on the target system instead of treating these
numbers as a frame-rate guarantee.

The correctness checks cover 103 calendar assertions, including leap dates,
year boundaries, bounded cache size, fractional-row offsets, date labels,
tooltips, week-number toggles, hover clearing and Today marker restoration.
An additional 840-step delta replay covers fast scrolling, deceleration curves,
interrupted inertia and abrupt reversals, checking logical date displacement
after every step. The initial replay found no date discontinuities.

Actual running popup checks also cover rapid forward/reverse scrolling,
sub-row positioning, the fixed weekday header/footer and the Today button.
The automation interface does not expose a physical two-finger gesture's native
momentum phases. A manual trackpad acceptance check on the development machine
reported smooth fast scrolling and abrupt reversals. Physical display frame
pacing was not instrumented.
