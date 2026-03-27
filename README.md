# goyacc

A YACC parser generator for Go, derived from the Go Authors' `cmd/goyacc`
(itself derived from Inferno's `iyacc`).

This fork is maintained by the [Vitess](https://github.com/vitessio/vitess)
project to generate its SQL parser, and includes several enhancements over
the original tool.

## Enhancements over standard goyacc

### Discriminated `unsafe.Pointer` union

The original goyacc maps `%union` members directly to struct fields in
`yySymType`, making the struct as large as the sum of all member types.
This fork replaces that layout with a compact discriminated union that
mimics how a C `union` works: all member types share the same block of
memory, with the largest member determining the allocation size.

```go
type yySymType struct {
    data yyData  // [N]uintptr — raw storage, sized to largest member
    ptrs yyPtrs  // [M]unsafe.Pointer — GC keepalive for pointer words
    yys  int
}
```

The `data` array size and the pointer-word layout for each member are
inferred automatically at generation time using `go/packages`. Typed
accessor and setter methods are generated for each member:

```go
func (st *yySymType) expr() Expr     { ... }      // getter
func (st *yySymType) setexpr(v Expr) { ... }      // setter
```

All reads and writes go through `unsafe.Pointer` casts into `data`,
eliminating interface boxing (`convTslice`/`convT`) on every grammar
reduction. The `ptrs` array keeps pointer-containing words visible to
the GC. `yySymType` can shrink dramatically (e.g. 136 → 40 bytes),
reducing stack copy cost on every parser push/pop operation.

### Custom error messages

Supports `// error: "message"` comments in grammar rules to provide
context-specific parse error messages. The generated parser looks up
error messages by (state, token) pairs and falls back to listing
expected tokens.

### Location tracking (`%locations`)

Supports Bison-style source location tracking via a `%locations` directive.
When declared, each symbol on the parse stack carries a `yyloc` field of
type `yyLocation`:

```go
type yyLocation struct {
    FirstLine, FirstColumn int
    LastLine,  LastColumn  int
}
```

The names `yyLocation`, `yySymType`, and `yyLocDefault` shown here assume
the default `yy` prefix. With `-p`/`--prefix`, substitute the chosen prefix
throughout.

In action code, `@N` and `@$` access the location of the Nth RHS symbol
and the LHS result, respectively — mirroring how `$N` and `$$` work for
semantic values. Named references (`@name`, `@name@N`) are also supported.

```yacc
expr: expr '+' expr
    {
        $$ = $1 + $3
        @$.FirstLine   = @1.FirstLine
        @$.FirstColumn = @1.FirstColumn
        @$.LastLine    = @3.LastLine
        @$.LastColumn  = @3.LastColumn
    }
```

Before each action runs, `yyLocDefault` is called to automatically merge
the RHS span into `@$` (the YYLLOC_DEFAULT equivalent). To customise the
merge logic, use `%loctype` and supply your own implementation.

Lexers supply location information by setting `lval.yyloc` before
returning. Shifts copy the full `yySymType`, so token locations land on
the stack automatically.

#### Custom location type (`%loctype`)

To use a custom location type instead of the generated `yyLocation`, use
`%loctype`:

```yacc
%loctype MyLocation
```

When `%loctype` is used, `yyLocation` and `yyLocDefault` are not generated.
The user must define `yyLocDefault` with a matching signature (substitute
the prefix for `yy` if using `-p`/`--prefix`):

```go
func yyLocDefault(cur *MyLocation, rhs []yySymType, n int) {
    // ...
}
```

### POSIX-style flags

Uses [pflag](https://github.com/spf13/pflag) for command-line parsing,
which supports POSIX-style combined short flags.

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
3. **This fork** — enhanced by the Vitess Authors with typed unions, 
   custom error messages, and location tracking

## License

MIT — see [LICENSE](LICENSE) for details.
