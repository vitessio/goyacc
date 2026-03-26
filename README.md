# goyacc

A YACC parser generator for Go, derived from the Go Authors' `cmd/goyacc`
(itself derived from Inferno's `iyacc`).

This fork is maintained by the [Vitess](https://github.com/vitessio/vitess)
project to generate its SQL parser, and includes several enhancements over
the original tool.

## Enhancements over standard goyacc

### Discriminated union via `any`

The original goyacc maps `%union` members directly to struct fields in
`yySymType`. This fork replaces that with a single `union any` field
and generates typed accessor methods for each member (e.g.,
`exprUnion() Expr`). This means each `yySymType` value holds exactly
one semantic value at a time instead of allocating space for all of
them, which significantly reduces the size of the parser stack for
grammars with many types. The accessor methods preserve compile-time
type safety.

### Fast-append optimization

For grammar rules that build up slices with `append($$, ...)`, the
generated code uses `unsafe.Pointer` to access the underlying slice
directly rather than boxing and unboxing through an interface:

```go
// Direct slice pointer manipulation — no interface boxing
yyySLICE := (*[]Expr)(yyIaddr(yyVAL.union))
*yyySLICE = append(*yyySLICE, yyDollar[2].exprUnion())
```

This optimization is always enabled and can meaningfully reduce
allocations in grammars with many list production rules.

### `%struct` directive

In addition to `%union`, this fork adds a `%struct` directive. Members
declared with `%struct` become direct fields on `yySymType` (like the
original `%union` behavior), while `%union` members go through the
`any` field with accessors. This allows grammars to use both
approaches: `%struct` for small, frequently-accessed values that
benefit from direct field access, and `%union` for the larger set of
semantic types that benefit from the smaller stack footprint.

### Custom error messages

Supports `// error: "message"` comments in grammar rules to provide
context-specific parse error messages. The generated parser looks up
error messages by (state, token) pairs and falls back to listing
expected tokens.

### POSIX-style flags

Uses [pflag](https://github.com/spf13/pflag) for command-line parsing,
which supports combined short flags (e.g., `-fo sql.go` combines `-f` and
`-o sql.go`).

## Installation

As a standalone binary:

```bash
go install github.com/vitessio/goyacc@latest
```

As a [tool dependency](https://go.dev/doc/modules/managing-dependencies#tools) in your module:

```bash
go get -tool github.com/vitessio/goyacc@latest
```

Then invoke it with `go tool goyacc` or `go run github.com/vitessio/goyacc`.

## Usage

```bash
goyacc [flags] grammar.y
```

### Flags

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--output` | `-o` | `y.go` | Parser output file |
| `--prefix` | `-p` | `yy` | Name prefix for generated identifiers |
| `--verbose-output` | `-v` | `y.output` | Verbose parsing tables output file |
| `--disable-line-directives` | `-l` | `false` | Disable line directives in generated code |

### Example

```bash
goyacc -o sql.go sql.y
```

The generated output is valid Go source but is not formatted. Callers
should run `goimports` and/or `gofumpt` on the output file after
generation.

## Provenance

This tool's lineage:

1. **Inferno `iyacc/yacc.c`** — the original C implementation
2. **Go `cmd/yacc`** — ported to Go by the Go Authors
3. **This fork** — enhanced by the Vitess Authors with fast-append, typed
   unions, and custom error messages

## License

MIT — see [LICENSE](LICENSE) for details.
