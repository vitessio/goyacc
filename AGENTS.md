# AGENTS.md

This file provides guidance to AI agents when working with code in this repository.

## Commands

```bash
# Build
go build .

# Run
go run . [flags] grammar.y

# Test (no test suite exists; validate by generating a grammar)
go vet ./...
```

There is no Makefile; standard Go tooling is used throughout.

## Architecture

This is a single-file tool (`goyacc.go`, ~3700 lines, `package main`) that reads a YACC grammar (`.y` file) and writes a Go parser. All logic lives in one file — there are no sub-packages.

The upstream source is [`cmd/goyacc`](https://cs.opensource.google/go/x/tools/+/master:cmd/goyacc/) in the Go `x/tools` repository ([GitHub mirror](https://github.com/golang/tools/blob/master/cmd/goyacc/)). This fork adds the enhancements described below.

### Processing pipeline

1. **Lexing** — `gettok()` / `getword()` tokenize the `.y` input
2. **Grammar parsing** — `setup()` reads productions, types, and directives into global arrays
3. **State generation** — `stagen()` builds the LALR(1) automaton (states, items, lookahead sets)
4. **Table output** — `output()` / `go2out()` write the action/goto tables to the output file
5. **Code emission** — `cppcode()`, `cpyact()`, and related functions copy user code sections verbatim into the output

### Key data structures

- `Pitem` / `Item` — a production rule with a dot position and lookahead set
- `Symb` — a grammar symbol (terminal or nonterminal)
- `Lkset` — a bitset representing lookahead tokens
- `Row` — one row of the action table (actions + default)
- `Error` — a custom error message keyed by (state, token)

### Enhancements over standard goyacc

**Discriminated union** (`%union`): Instead of a struct with one field per type, generates a single `union any` field plus typed accessor methods (e.g., `exprUnion() Expr`). Reduces parser stack size.

**Fast-append** (`-f`): For rules of the form `$$ = append($1, $2)`, bypasses the interface box/unbox by using `unsafe.Pointer` directly into the `union` field. Eliminates per-reduction heap allocations for slice-typed grammar symbols.

**`%struct` directive**: Members declared with `%struct` become direct fields on `yySymType` (original behavior); `%union` members go through the `any` accessor path. Mix both to balance stack size vs. direct access.

**Custom error messages**: `// error: "message"` comments in grammar rules are collected into a lookup table keyed by (state, token) pair and emitted into the generated parser.

### Generated output

The emitted file is valid but unformatted Go. Callers should post-process with `goimports` and/or `gofumpt`.

Generated parsers expose:
- `yySymType` — the semantic value type on the parser stack
- `yyLexer` interface — `Lex(lval *yySymType) int`
- `yyParser` interface — `Parse(yylex yyLexer) int`
- `yyParse(yylex yyLexer) int` — convenience entry point
