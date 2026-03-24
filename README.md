# goyacc

A YACC parser generator for Go, derived from the Go Authors' `cmd/goyacc`
(itself derived from Inferno's `iyacc`).

This fork is maintained by the [Vitess](https://github.com/vitessio/vitess)
project to generate its SQL parser, and includes several enhancements over
the original tool.

## Enhancements over standard goyacc

### Fast-append optimization

The `-f` flag enables a performance optimization for grammar rules that use
`append($$, ...)` patterns in their reduction actions. Instead of going
through an interface type assertion on every append, the generated code uses
`unsafe.Pointer` to access the underlying slice directly:

```go
// Without fast-append: type assertion on every reduction
yyVAL.union = append(yyDollar[1].exprUnion(), yyDollar[2].exprUnion())

// With fast-append: direct slice pointer manipulation
yyySLICE := (*[]Expr)(yyIaddr(yyVAL.union))
*yyySLICE = append(*yyySLICE, yyDollar[2].exprUnion())
```

This avoids repeated boxing/unboxing of slice values through the `any`
interface in the parser's union type, which can meaningfully reduce
allocations in grammars with many list production rules.

### Discriminated union via `any`

The original goyacc maps `%union` members directly to struct fields in
`yySymType`. This fork replaces that with a single `union any` field
and generates typed accessor methods for each member (e.g.,
`exprUnion() Expr`). This means each `yySymType` value holds exactly
one semantic value at a time instead of allocating space for all of
them, which significantly reduces the size of the parser stack for
grammars with many types. The accessor methods preserve compile-time
type safety.

This is also what makes the fast-append optimization possible — the
`any` interface is what `$$Iaddr` reaches through via `unsafe.Pointer`.

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

```bash
go install github.com/vitessio/goyacc@latest
```

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
| `--fast-append` | `-f` | `false` | Enable fast-append optimization |

### Example

```bash
goyacc -fo sql.go sql.y
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
