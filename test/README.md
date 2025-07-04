# ESP32 Camera Tests

The test suite runs without ESP32 camera hardware by using `esp32cam_mock`.
Hardware-specific behavior is covered through mocked board configurations and
flash timing checks.

## Test Files

```
test/
├── esp32cam_SUITE.erl          # Common Test integration and workflow checks
├── esp32cam_eunit_tests.erl    # EUnit coverage for public API behavior
└── esp32cam_prop_tests.erl     # PropEr properties
```

## Running Tests

Run the same checks used by CI:

```sh
rebar3 as test compile
rebar3 fmt --check
rebar3 eunit
rebar3 ct
rebar3 as test proper -m esp32cam_prop_tests -n 20
```

For a deeper property run:

```sh
rebar3 as test proper -m esp32cam_prop_tests
```

## Supported Mock Boards

- `ai_thinker`
- `wrover_kit`
- `esp32s3_wroom`
- `esp32s3_goouuu`
- `esp32s3_xiao`
- `m5cam`
- `m5cam_wide`
- `m5cam_psram`

The mock supports normal captures, flash captures, forced errors, slower
captures, and flash-sensitive image data.
