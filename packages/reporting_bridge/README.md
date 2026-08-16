# reporting_bridge

Dart/IO transport, cache, runtime-session, and Presenter protocol core for
Ultimate Report Builder.

This package must not import Flutter UI libraries. Flutter hosts consume
`reporting_bridge_flutter`, which re-exports this core.

## Responsibilities

- Report Server transport and approved dynamic headers
- System/template synchronization and cache isolation
- Presenter download/cache and runtime-session lifecycle
- Online/offline launch preparation and PDF protocol transport

## Usage

Hosts should depend on `reporting_bridge_flutter` unless they need the core
package directly (for example Presenter protocol types).
