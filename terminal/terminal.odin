package terminal

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


Command :: struct {
	name:    string,
	summary: string,
	details: string,
	example: string,
	run:     proc(_: []string),
}


exit_with_help :: proc(command: Command) {
	log.debug("Implement `exit_with_help`")
}

exit_with_unknown :: proc(commands: []Command, command_name: string) {
	nearby_knowns: [dynamic]string = {}
	defer delete(nearby_knowns)

	for command in commands {
		dist, err := strings.levenshtein_distance(command_name, command.name)
		if dist <= 3 {
			append(&nearby_knowns, command.name)
		}
	}

	fmt.printf(
		"There is no " +
		ansi.CSI +
		ansi.FG_BRIGHT_RED +
		ansi.SGR +
		"%s" +
		ansi.CSI +
		ansi.RESET +
		ansi.SGR +
		" command. ",
		command_name,
	)

	nearby := len(nearby_knowns)

	if nearby > 2 {
		fmt.printf(
			"Try " +
			ansi.CSI +
			ansi.FG_BRIGHT_GREEN +
			ansi.SGR +
			"%s" +
			ansi.CSI +
			ansi.RESET +
			ansi.SGR,
			nearby_knowns[0],
		)
		for i := 1; i < nearby - 1; i += 1 {
			fmt.printf(
				", " +
				ansi.CSI +
				ansi.FG_BRIGHT_GREEN +
				ansi.SGR +
				"%s" +
				ansi.CSI +
				ansi.RESET +
				ansi.SGR,
				nearby_knowns[i],
			)
		}
		fmt.printf(
			" or " +
			ansi.CSI +
			ansi.FG_BRIGHT_GREEN +
			ansi.SGR +
			"%s" +
			ansi.CSI +
			ansi.RESET +
			ansi.SGR +
			" instead?",
			nearby_knowns[nearby - 1],
		)

	} else if nearby > 1 {
		fmt.printf(
			"Try " +
			ansi.CSI +
			ansi.FG_BRIGHT_GREEN +
			ansi.SGR +
			"%s" +
			ansi.CSI +
			ansi.RESET +
			ansi.SGR +
			" or " +
			ansi.CSI +
			ansi.FG_BRIGHT_GREEN +
			ansi.SGR +
			"%s" +
			ansi.CSI +
			ansi.RESET +
			ansi.SGR +
			" instead?",
			nearby_knowns[0],
			nearby_knowns[1],
		)
	} else if nearby > 0 {
		fmt.printf(
			"Try " +
			ansi.CSI +
			ansi.FG_BRIGHT_GREEN +
			ansi.SGR +
			"%s" +
			ansi.CSI +
			ansi.RESET +
			ansi.SGR +
			" instead?",
			nearby_knowns[0],
		)
	}

	fmt.print("\n\nRun `elm` with no arguments to get more hints.\n\n")
}


exit_with_overview :: proc(commands: []Command) {
	intro()
	fmt.print("\nThe most common commands are:\n\n")

	for command in commands[:min(3, len(commands))] {
		fmt.printf(
			"    " +
			ansi.CSI +
			ansi.FG_BRIGHT_CYAN +
			ansi.SGR +
			"elm %s\n" +
			ansi.CSI +
			ansi.RESET +
			ansi.SGR,
			command.name,
		)
		summary_lines := strings.split(command.summary, "\n")
		defer delete(summary_lines)
		for line in summary_lines {
			fmt.printf("        %s\n", line)
		}
		fmt.print("\n")
	}

	fmt.print("There are a bunch of other commands as well though. Here is a full list:\n\n")

	longest_cmd: int

	for command in commands {
		longest_cmd = max(longest_cmd, len(command.name))
	}

	for command in commands {
		padded_cmd_name := strings.left_justify(command.name, longest_cmd, " ")
		defer delete(padded_cmd_name)
		fmt.printf(
			"    " +
			ansi.CSI +
			ansi.FG_CYAN +
			ansi.SGR +
			"elm %s --help\n" +
			ansi.CSI +
			ansi.RESET +
			ansi.SGR,
			padded_cmd_name,
		)
	}

	fmt.print("\nAdding the --help flag gives a bunch of additional details about each one.\n\n")

	outro()
}


intro :: proc() {
	fmt.print(
		"Hi, thank you for trying out " +
		ansi.CSI +
		ansi.FG_BRIGHT_GREEN +
		ansi.SGR +
		"Elm (0.19.1-Odin)" +
		ansi.CSI +
		ansi.RESET +
		ansi.SGR +
		". I hope you like it!\n\n" +
		ansi.CSI +
		ansi.FG_BRIGHT_BLACK +
		ansi.SGR +
		"-------------------------------------------------------------------------------\n" +
		"I highly recommend working through <https://guide.elm-lang.org> to get started.\n" +
		"It teaches many important concepts, including how to use `elm` in the terminal.\n" +
		"-------------------------------------------------------------------------------" +
		ansi.CSI +
		ansi.RESET +
		ansi.SGR +
		"\n",
	)
}

outro :: proc() {
	fmt.print(
		`Be sure to ask on the Elm slack if you run into trouble! Folks are friendly and
happy to help out. They hang out there because it is fun, so be kind to get the
best results!

`,
	)
}


ask :: proc(question: string) -> (string, os.Error) {
	fmt.print(question)

	buf: [256]byte
	n, err := os.read(os.stdin, buf[:])

	if err != nil {
		log.error("Error reading: ", err)
		return "", err
	}

	str := string(buf[:n])
	str = strings.trim(str, " \n\t\r")
	return strings.clone(str), nil
}
