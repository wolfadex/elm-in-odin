package main

import "core:encoding/ansi"
import "core:fmt"
import "core:io"
import "core:log"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"
import "core:unicode"
import "core:unicode/utf8"
import "terminal"


state := struct {
	had_error: bool,
}{}


key_words := map[string]TokenType {
	"if"       = .IF,
	"then"     = .THEN,
	"else"     = .ELSE,
	"false"    = .FALSE,
	"true"     = .TRUE,
	"type"     = .TYPE,
	"alias"    = .ALIAS,
	"let"      = .LET,
	"in"       = .IN,
	"module"   = .MODULE,
	"exposing" = .EXPOSING,
	"import"   = .IMPORT,
}

main :: proc() {
	when ODIN_DEBUG {
		// setup debug logging
		logger := log.create_console_logger()
		context.logger = logger

		// setup tracking allocator for making sure all memory is cleaned up
		default_allocator := context.allocator
		tracking_allocator: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking_allocator, default_allocator)
		context.allocator = mem.tracking_allocator(&tracking_allocator)

		reset_tracking_allocator :: proc(a: ^mem.Tracking_Allocator) -> bool {
			err := false

			for _, value in a.allocation_map {
				fmt.printfln("%v: Leaked %v bytes", value.location, value.size)
				err = true
			}

			mem.tracking_allocator_clear(a)

			return err
		}

		defer reset_tracking_allocator(&tracking_allocator)
	}

	if len(os.args) > 2 {
		fmt.println("Usage: jlox [script]")
		os.exit(64)
	}


	if len(os.args) == 1 {
		terminal.exit_with_overview(KNOWN_COMMANDS)
	}

	switch os.args[1] {
	case "--help":
		terminal.exit_with_overview(KNOWN_COMMANDS)
	case "--version":
		fmt.println("0.19.1-Odin")
	case "init":
	case:
		terminal.exit_with_unknown(KNOWN_COMMANDS, os.args[1])
	}

	// if len(os.args) == 2 {
	// 	run_file(os.args[1])
	// } else {
	// 	run_prompt()
	// }
}


KNOWN_COMMANDS: []terminal.Command : {REPL, INIT, REACTOR, MAKE, INSTALL, BUMP, DIFF, PUBLISH}
KNOWN_COMMANDS_MIN: []terminal.Command : {REPL, INIT, REACTOR}

REPL :: terminal.Command {
	name    = "repl",
	summary = `Open up an interactive programming session. Type in Elm expressions like
(2 + 2) or (String.length "test") and see if they equal four!`,
	details = "The `repl` command opens up an interactive programming session:",
	example = `Start working through <https://guide.elm-lang.org> to learn how to use this!
It has a whole chapter that uses the REPL for everything, so that is probably
the quickest way to get started.`,
}

INIT :: terminal.Command {
	name    = "init",
	summary = `Start an Elm project. It creates a starter elm.json file and provides a
link explaining what to do from there.`,
	details = "The `init` command helps start Elm projects:",
	example = `It will ask permission to create an elm.json file, the one thing common
to all Elm projects. It also provides a link explaining what to do from there.`,
}

REACTOR :: terminal.Command {
	name    = "reactor",
	summary = `Compile code with a click. It opens a file viewer in your browser, and
when you click on an Elm file, it compiles and you see the result.`,
	details = "The `reactor` command starts a local server on your computer:",
	example = `After running that command, you would have a server at <http://localhost:8000>
that helps with development. It shows your files like a file viewer. If you
click on an Elm file, it will compile it for you! And you can just press
the refresh button in the browser to recompile things.`,
}

MAKE :: terminal.Command {
	name    = "make",
	summary = ``,
	details = "The `make` command compiles Elm code into JS or HTML:",
	example = ``,
}

INSTALL :: terminal.Command {
	name    = "install",
	summary = ``,
	details = "The `install` command fetches packages from <https://package.elm-lang.org> for use in your project:",
	example = ``,
}

BUMP :: terminal.Command {
	name    = "bump",
	summary = ``,
	details = "The `bump` command figures out the next version number based on API changes:",
	example = ``,
}

DIFF :: terminal.Command {
	name    = "diff",
	summary = ``,
	details = "The `diff` command detects API changes:",
	example = ``,
}

PUBLISH :: terminal.Command {
	name    = "publish",
	summary = ``,
	details = "The `publish` command publishes your package on <https://package.elm-lang.org> so that anyone in the Elm community can use it.",
	example = ``,
}


//
//
//
//
//
//
//
//


run_file :: proc(filename: string) {
	data, err := os.read_entire_file_from_filename_or_err(filename)
	defer delete(data)
	scanner: Scanner = {
		source_file = filename,
		data        = utf8.string_to_runes(string(data)),
	}

	run(&scanner)

	for token in scanner.tokens {
		switch lit in token.literal {
		case f32:
		case int:
		case string:
			delete(lit)
		}
	}

	delete(scanner.data)
	delete(scanner.tokens)

	if state.had_error {
		os.exit(65)
	}
}

run_prompt :: proc() {
	log.debug("TODO: run prompt")
}

run :: proc(scanner: ^Scanner) {
	scan_all(scanner)

	for token in scanner.tokens {
		log.debug(token)
	}
}


Scanner :: struct {
	source_file: string,
	data:        []rune,
	start:       uint,
	current:     uint,
	line:        uint,
	column:      uint,
	tokens:      [dynamic]Token,
}


scan_all :: proc(scanner: ^Scanner) {
	scanner.line = 1
	scanner.column = 1

	for !is_at_end(scanner) {
		scanner.start = scanner.current
		scan_token(scanner)
	}


	append(&scanner.tokens, Token{type = .EOF, line = scanner.line})
}

scan_token :: proc(scanner: ^Scanner) {
	r := advance(scanner)
	switch r {
	case '(':
		type_to_token(scanner, .LEFT_PAREN, 1)
	case ')':
		type_to_token(scanner, .RIGHT_PAREN, 1)
	case '{':
		type_to_token(scanner, .LEFT_BRACE, 1)
	case '}':
		type_to_token(scanner, .RIGHT_BRACE, 1)
	case '[':
		type_to_token(scanner, .LEFT_BRACKET, 1)
	case ']':
		type_to_token(scanner, .RIGHT_BRACKET, 1)
	case ',':
		type_to_token(scanner, .COMMA, 1)
	case ':':
		type_to_token(scanner, .COLON, 1)
	case '*':
		type_to_token(scanner, .STAR, 1)
	case '|':
		type_to_token(scanner, .PIPE, 1)
	//
	case '.':
		if match(scanner, '.') {
			type_to_token(scanner, .DOT_DOT, 2)
		} else {
			type_to_token(scanner, .DOT, 1)
		}
	case '+':
		if match(scanner, '.') {
			type_to_token(scanner, .PLUS_PLUS, 2)
		} else {
			type_to_token(scanner, .PLUS, 1)
		}
	case '-':
		if match(scanner, '-') {
			type_to_token(scanner, .MINUS_MINUS, 2)
		} else {
			type_to_token(scanner, .MINUS, 1)
		}
	case '/':
		if match(scanner, '=') {
			type_to_token(scanner, .SLASH_EQUAL, 2)
		} else if match(scanner, '/') {
			type_to_token(scanner, .SLASH_SLASH, 2)
		} else {
			type_to_token(scanner, .SLASH, 1)
		}
	case '=':
		if match(scanner, '=') {
			type_to_token(scanner, .EQUAL_EQUAL, 2)
		} else {
			type_to_token(scanner, .EQUAL, 1)
		}
	case '<':
		if match(scanner, '=') {
			type_to_token(scanner, .LESS_EQUAL, 2)
		} else {
			type_to_token(scanner, .LESS, 1)
		}
	case '>':
		if match(scanner, '=') {
			type_to_token(scanner, .GREATER_EQUAL, 2)
		} else {
			type_to_token(scanner, .GREATER, 1)
		}
	case ' ':
		scanner.column += 1
	case '\r':
	// ignore
	case '\t':
		scanner.column += 1
		error(scanner, "Found tab")
	case '\n':
		scanner.column = 1
		scanner.line += 1
	case '"':
		scanner.column = 1
		scan_string(scanner)
	case:
		if unicode.is_digit(r) {
			number(scanner)
		} else if unicode.is_alpha(r) {
			identifier(scanner)
		} else {
			scanner.column += 1
			error(scanner, fmt.aprintf("Unexpexted character: %v", r))}
	}
}


identifier :: proc(scanner: ^Scanner) {
	start_col := scanner.current - 1
	gather_identifier(scanner)

	ident := utf8.runes_to_string(scanner.data[start_col:scanner.current])


	key_word := key_words[ident]

	if key_word == nil {
		to_token(scanner, .IDENTIFIER, scanner.column, ident)
	} else {
		to_token(scanner, key_word, scanner.column, nil)
		delete(ident)
	}

}


number :: proc(scanner: ^Scanner) {
	start_col := scanner.current - 1
	gather_digits(scanner)

	next_rune := peek(scanner)
	switch r in next_rune {
	case nil:
		int_runes := utf8.runes_to_string(scanner.data[start_col:scanner.current])
		defer delete(int_runes)
		int, ok := strconv.parse_int(int_runes)
		if ok {
			to_token(scanner, .INTEGER, scanner.column, int)
			return
		} else {
			error(scanner, "Expected an integer")
		}
	case rune:
		if r == '.' {
			following_rune := peek(scanner)
			switch fr in following_rune {
			case nil:
				error(scanner, "Floats cannot end with a .")
			case rune:
				advance(scanner)
				gather_digits(scanner)
				float_runes := utf8.runes_to_string(scanner.data[start_col:scanner.current])
				defer delete(float_runes)
				float, ok := strconv.parse_f32(float_runes)
				if ok {
					to_token(scanner, .FLOAT, scanner.column, float)
					return
				} else {
					error(scanner, "Expected a float")
				}
			}
		}

		int_runes := utf8.runes_to_string(scanner.data[start_col:scanner.current])
		defer delete(int_runes)
		int, ok := strconv.parse_int(int_runes)
		if ok {
			to_token(scanner, .INTEGER, scanner.column, int)
		} else {
			error(scanner, "Expected an integer")
		}
	}
}

gather_digits :: proc(scanner: ^Scanner) {
	for {
		next_rune := peek(scanner)

		switch r in next_rune {
		case nil:
			return
		case rune:
			if unicode.is_digit(r) {
				advance(scanner)
				continue
			}
			return
		}
	}
}

gather_identifier :: proc(scanner: ^Scanner) {
	for {
		next_rune := peek(scanner)

		switch r in next_rune {
		case nil:
			return
		case rune:
			if unicode.is_digit(r) || unicode.is_alpha(r) || r == '_' {
				advance(scanner)
				continue
			}
			return
		}
	}
}


scan_string :: proc(scanner: ^Scanner) {
	prev_char: rune = ---
	col_count: uint

	for {
		next_rune := peek(scanner)
		switch r in next_rune {
		case nil:
			error(scanner, "Unterminated string")
			return
		case rune:
			col_count += 1
			scanner.current += 1

			if r == '"' {
				to_token(
					scanner,
					.STRING,
					col_count,
					utf8.runes_to_string(
						scanner.data[scanner.current - col_count - 1:scanner.current],
					),
				)
				return
			}

			if r == '\n' && prev_char != '\\' {
				error(scanner, "Strings cannot have newlines, try a multiline string")
				return
			}

			prev_char = r
		}
	}
}

match :: proc(scanner: ^Scanner, expected: rune) -> bool {
	if is_at_end(scanner) {
		return false
	}

	if scanner.data[scanner.current] != expected {
		return false
	}

	scanner.current += 1
	return true
}

peek :: proc(scanner: ^Scanner) -> union {
		rune,
	} {
	if is_at_end(scanner) {
		return nil
	}

	return scanner.data[scanner.current]
}

advance :: proc(scanner: ^Scanner) -> rune {
	c := scanner.data[scanner.current]
	scanner.current += 1
	return c
}

type_to_token :: proc(scanner: ^Scanner, type: TokenType, columns: uint) {
	to_token(scanner, type, columns, "")
}

to_token :: proc(scanner: ^Scanner, type: TokenType, columns: uint, literal: Literal) {
	append(
		&scanner.tokens,
		Token{type = type, line = scanner.line, column = scanner.column, literal = literal},
	)
	scanner.column += columns
}

is_at_end :: proc(scanner: ^Scanner) -> bool {
	return scanner.current >= len(scanner.data)
}

Token :: struct {
	type:    TokenType,
	lexeme:  string,
	literal: Literal,
	line:    uint,
	column:  uint,
}

Literal :: union {
	string,
	f32,
	int,
}

token_to_string :: proc(token: Token) -> string {
	return fmt.aprintf("%s $s %s", token_type_to_string(token.type), token.lexeme, token.literal)
}

token_type_to_string :: proc(type: TokenType) -> string {
	str := ""

	switch type {
	case .LEFT_PAREN:
		str = "LEFT_PAREN"
	case .RIGHT_PAREN:
		str = "RIGHT_PAREN"
	case .LEFT_BRACE:
		str = "LEFT_BRACE"
	case .RIGHT_BRACE:
		str = "RIGHT_BRACE"
	case .LEFT_BRACKET:
		str = "LEFT_BRACKET"
	case .RIGHT_BRACKET:
		str = "RIGHT_BRACKET"
	case .COMMA:
		str = "COMMA"
	case .PLUS:
		str = "PLUS"
	case .PLUS_PLUS:
		str = "PLUS_PLUS"
	case .COLON:
		str = "COLON"
	case .STAR:
		str = "STAR"
	case .PIPE:
		str = "PIPE"
	case .PIPE_PIPE:
		str = "PIPE_PIPE"
	case .DOT:
		str = "DOT"
	case .DOT_DOT:
		str = "DOT_DOT"
	case .MINUS:
		str = "MINUS"
	case .MINUS_MINUS:
		str = "MINUS_MINUS"
	case .SLASH:
		str = "SLASH"
	case .SLASH_EQUAL:
		str = "SLASH_EQUAL"
	case .SLASH_SLASH:
		str = "SLASH_SLASH"
	case .EQUAL:
		str = "EQUAL"
	case .EQUAL_EQUAL:
		str = "EQUAL_EQUAL"
	case .GREATER:
		str = "GREATER"
	case .GREATER_EQUAL:
		str = "GREATER_EQUAL"
	case .LESS:
		str = "LESS"
	case .LESS_EQUAL:
		str = "LESS_EQUAL"
	case .IDENTIFIER:
		str = "IDENTIFIER"
	case .STRING:
		str = "STRING"
	case .INTEGER:
		str = "INTEGER"
	case .FLOAT:
		str = "FLOAT"
	case .IF:
		str = "IF"
	case .THEN:
		str = "THEN"
	case .ELSE:
		str = "ELSE"
	case .FALSE:
		str = "FALSE"
	case .TRUE:
		str = "TRUE"
	case .TYPE:
		str = "TYPE"
	case .ALIAS:
		str = "ALIAS"
	case .LET:
		str = "LET"
	case .IN:
		str = "IN"
	case .MODULE:
		str = "MODULE"
	case .EXPOSING:
		str = "EXPOSING"
	case .IMPORT:
		str = "IMPORT"
	case .EOF:
		str = "EOF"
	}

	return str
}

TokenType :: enum {
	// Single-character tokens
	LEFT_PAREN,
	RIGHT_PAREN,
	LEFT_BRACE,
	RIGHT_BRACE,
	LEFT_BRACKET,
	RIGHT_BRACKET,
	COMMA,
	COLON,
	STAR,

	// One or two character tokens
	PLUS,
	PLUS_PLUS,
	DOT,
	DOT_DOT,
	PIPE,
	PIPE_PIPE,
	MINUS,
	MINUS_MINUS,
	SLASH,
	SLASH_EQUAL,
	SLASH_SLASH,
	EQUAL,
	EQUAL_EQUAL,
	GREATER,
	GREATER_EQUAL,
	LESS,
	LESS_EQUAL,

	// Literals
	IDENTIFIER,
	STRING,
	INTEGER,
	FLOAT,

	// Keywords
	IF,
	THEN,
	ELSE,
	FALSE,
	TRUE,
	TYPE,
	ALIAS,
	LET,
	IN,
	MODULE,
	EXPOSING,
	IMPORT,

	// Other
	EOF,
}

error :: proc(scanner: ^Scanner, message: string) {
	report(scanner, message)
}

report :: proc(scanner: ^Scanner, message: string) {
	fmt.printfln("[line %d, col %d] Error: %s", scanner.line, scanner.column, message)
	state.had_error = true
}
