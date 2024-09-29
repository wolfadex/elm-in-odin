package init


import "../terminal"
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


run :: proc(args: []string) {
	if os.exists("elm.json") {
		header := strings.left_justify("-- EXISTING PROJECT ", LINE_LEN, "-")
		defer delete(header)
		fmt.printfln(
			ansi.CSI + ansi.FG_CYAN + ansi.SGR + "%s" + ansi.CSI + ansi.RESET + ansi.SGR,
			header,
		)
		fmt.println(
			"\nYou already have an elm.json file, so there is nothing for me to initialize!\n",
		)
		fmt.print(
			"Maybe " +
			ansi.CSI +
			ansi.FG_BRIGHT_GREEN +
			ansi.SGR +
			"<https://elm-lang.org/0.19.1/init>" +
			ansi.CSI +
			ansi.RESET +
			ansi.SGR +
			" can help you figure out what to do\nnext?\n\n",
		)
	} else {
		ask_to_init()
	}
}


LINE_LEN :: len("--------------------------------------------------------------------------------")


ask_to_init :: proc() {
	fmt.print(
		"Hello! Elm projects always start with an " +
		ansi.CSI +
		ansi.FG_BRIGHT_GREEN +
		ansi.SGR +
		"elm.json" +
		ansi.CSI +
		ansi.RESET +
		ansi.SGR +
		" file. I can create them!\n\n" +
		`Now you may be wondering, what will be in this file? How do I add Elm files to
my project? How do I see it in the browser? How will my code grow? Do I need
more directories? What about tests? Etc.

Check out ` +
		ansi.CSI +
		ansi.FG_BRIGHT_CYAN +
		ansi.SGR +
		"<https://elm-lang.org/0.19.1/init>" +
		ansi.CSI +
		ansi.RESET +
		ansi.SGR +
		` for all the answers!

`,
	)

	response, err := terminal.ask(
		"Knowing all that, would you like me to create an elm.json file now? [Y/n]: ",
	)
	defer delete(response)

	get_answer: for {
		if err != nil {
			log.debug("Err?", err)
			break
		}

		switch response {
		case "n":
			fmt.println("Okay, I did not make any changes!")
			break get_answer
		case "y", "Y":
			log.debug("Create elm.json")
			fmt.println("Okay, I created it. Now read that link!")
			break get_answer
		case:
			response, err = terminal.ask("Must type 'y' for yes or 'n' for no: ")
		}

	}

}
