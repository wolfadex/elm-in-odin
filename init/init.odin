package init


import "../terminal"
import "../version"
import "core:encoding/ansi"
import "core:encoding/endian"
import "core:encoding/json"
import "core:fmt"
import "core:io"
import "core:log"
import "core:mem"
import "core:os"
import "core:path/filepath"
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
			create_elm_json()
			break get_answer
		case:
			response, err = terminal.ask("Must type 'y' for yes or 'n' for no: ")
		}
	}
}


create_elm_json :: proc() {
	cache_dir := get_cache_dir("packages")
	defer delete(cache_dir)
	registry_dat_path := filepath.join({cache_dir, "registry.dat"})
	defer delete(registry_dat_path)

	if os.exists(registry_dat_path) {
		data, read_err := os.read_entire_file_from_filename_or_err(registry_dat_path)
		defer delete(data)

		if read_err != nil {
			log.debug("Registry read error", read_err)
			return
		}

		registry_data := parse_registry(data)

		for _, knwn_vers in registry_data.packages {
			delete_dynamic_array(knwn_vers.previous)
		}
		delete_map(registry_data.packages)
	} else {
		// todo fetch data
		log.debug("Registry is missing!?")
	}

	fmt.println("Okay, I created it. Now read that link!")
}


parse_registry :: proc(data: []u8) -> Registry {
	package_versions_count, package_versions_count_ok := endian.get_u64(
		data[:8],
		endian.Byte_Order.Big,
	)
	packages_count, packages_count_ok := endian.get_u64(data[8:16], endian.Byte_Order.Big)
	// log.debug("package_versions_count", package_versions_count, package_versions_count_ok)
	// log.debug("packages_count", packages_count, packages_count_ok)


	packages: map[string]KnownVersions

	byte_offset: u64 = 16

	for package_offset := 0; package_offset < int(packages_count); package_offset += 1 {
		// for package_offset := 0; package_offset < 2; package_offset += 1 {

		user_name_length := u64(data[byte_offset])
		byte_offset += 1
		user_name := string(data[byte_offset:byte_offset + user_name_length])
		// log.debug("user_name", user_name)
		byte_offset += user_name_length


		project_name_length := u64(data[byte_offset])
		byte_offset += 1
		project_name := string(data[byte_offset:byte_offset + project_name_length])
		// log.debug("project_name", project_name)
		byte_offset += project_name_length

		newest_version, next_offset := version.decode_bytes(data, byte_offset)
		byte_offset = next_offset
		// log.debug("latest version", newest_version)

		previous_versions_count, previous_versions_count_ok := endian.get_u64(
			data[byte_offset:byte_offset + 8],
			endian.Byte_Order.Big,
		)
		// log.debug("previous_versions_count", previous_versions_count)
		byte_offset += 8

		previous_versions: [dynamic]version.Version
		reserve(&previous_versions, previous_versions_count)

		for versions_decoded: u64 = 0;
		    versions_decoded < previous_versions_count;
		    versions_decoded += 1 {

			prev_version, following_offset := version.decode_bytes(data, byte_offset)
			append(&previous_versions, prev_version)
			byte_offset = following_offset
		}

		known_versions := KnownVersions {
			newest   = newest_version,
			previous = previous_versions,
		}
		// log.debug("known_versions", known_versions)

		package_name, package_name_err := strings.join({user_name, project_name}, "/")

		if package_name_err != nil {
			log.error("Error making package name", package_name_err)
		}

		map_insert(&packages, package_name, known_versions)
		delete(package_name)
	}

	// log.debug("Packages", packages)

	return Registry{count = int(packages_count), packages = packages}
}


registry_path :: proc(dir: string) -> string {
	return filepath.join({dir, "registry.dat"})
}

get_cache_dir :: proc(project_name: string) -> string {
	elm_home := get_elm_home()
	defer delete(elm_home)
	cache_dir := filepath.join({elm_home, "0.19.1", project_name})

	if !os.exists(cache_dir) {
		os.make_directory(cache_dir)
	}

	return cache_dir
}


get_elm_home :: proc() -> string {
	elm_home, found := os.lookup_env("ELM_HOME")

	if !found {
		// todo: don't hard code this
		home_path := os.get_env("HOME")
		elm_home = filepath.join({home_path, ".elm"})
	}

	return elm_home
}


Registry :: struct {
	count:    int,
	packages: map[string]KnownVersions,
}

KnownVersions :: struct {
	newest:   version.Version,
	previous: [dynamic]version.Version,
}
