package registry

import "../terminal"
import http_client "../vendored/odin-http/client"
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
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"
import "core:unicode"
import "core:unicode/utf8"


Registry :: struct {
	count:    int,
	packages: map[string]KnownVersions,
}

KnownVersions :: struct {
	newest:   version.Version,
	previous: [dynamic]version.Version,
}


load :: proc(cache_dir: string, registry: ^Registry) {
	registry_dat_path := filepath.join({cache_dir, "registry.dat"})
	defer delete(registry_dat_path)

	if os.exists(registry_dat_path) {
		data, read_err := os.read_entire_file_from_filename_or_err(registry_dat_path)
		defer delete(data)

		if read_err != nil {
			log.debug("Registry read error", read_err)
			return
		}

		cached_registry := decode(data)

		has_changes := update(&cached_registry)

		if has_changes {
			encoded_reg := encode(&cached_registry)
			defer delete(encoded_reg)
			carl_path := filepath.join({cache_dir, "registry.dat-odin"})
			defer delete(carl_path)
			write_err := os.write_entire_file_or_err(carl_path, encoded_reg)
		}

		for nme, knwn_vers in cached_registry.packages {
			delete_dynamic_array(knwn_vers.previous)
			delete(nme)
		}
		delete_map(cached_registry.packages)
	} else {
		// todo fetch data
		log.debug("Registry is missing!?")
	}
}


update :: proc(cached_registry: ^Registry) -> (has_changes: bool) {
	req: http_client.Request
	http_client.request_init(&req, .Post)
	defer http_client.request_destroy(&req)

	full_url := fmt.aprintf(
		"https://package.elm-lang.org/all-packages/since/%d",
		cached_registry.count,
	)
	defer delete(full_url)

	res, err := http_client.request(&req, full_url)
	if err != nil {
		log.error("Request failed:", err)
		return
	}
	defer http_client.response_destroy(&res)

	if res.status == .OK {
		body_type, was_an_allocation, body_err := http_client.response_body(&res)
		if body_err != nil {
			log.error("Error retrieving response body:", body_err)
			return
		}
		defer http_client.body_destroy(body_type, was_an_allocation)

		// log.debug("Body", body_type)
		switch body in body_type {
		case http_client.Body_Error:
		// 🤔
		case http_client.Body_Url_Encoded:
		// 🤔
		case http_client.Body_Plain:
			new_packages: [dynamic]string
			new_pacakges_err := json.unmarshal(transmute([]u8)body, &new_packages)
			defer delete(new_packages)

			if new_pacakges_err != nil {
				log.error("Error decoding new package data", new_pacakges_err)
			}

			new_pacakge_count := len(new_packages)

			if len(new_packages) == 0 {
				return
			}

			cached_registry.count += new_pacakge_count

			for new_package in new_packages {
				package_parts_index := strings.index(new_package, "@")

				version, version_err := version.parse(new_package[package_parts_index + 1:])

				if version_err != nil {
					log.error("New package version parse error", version_err)
					continue
				}

				old_package, old_package_exists :=
					cached_registry.packages[new_package[:package_parts_index]]

				if old_package_exists {
					append(&old_package.previous, old_package.newest)
					old_package.newest = version
					cached_registry.packages[new_package[:package_parts_index]] = old_package
				} else {
					cached_registry.packages[new_package[:package_parts_index]] = KnownVersions {
						newest = version,
					}
				}
			}

			return true
		}
	}

	return
}


encode :: proc(registry: ^Registry) -> []u8 {
	data_size: u64 = 16
	data := make([dynamic]u8, data_size)

	endian.put_u64(data[:8], endian.Byte_Order.Big, u64(registry.count))

	packages_count := len(registry.packages)
	endian.put_u64(data[8:16], endian.Byte_Order.Big, u64(packages_count))

	byte_offset: u64 = 16

	package_name_sort :: proc(i, j: slice.Map_Entry(string, KnownVersions)) -> bool {
		i_sep_index := strings.index(i.key, "/")
		j_sep_index := strings.index(j.key, "/")

		if i.key[:i_sep_index] == j.key[:j_sep_index] {
			return i.key[i_sep_index:] < j.key[j_sep_index:]
		}

		return i.key[:i_sep_index] < j.key[:j_sep_index]
	}
	packages, packages_to_slice_err := slice.map_entries(registry.packages)
	defer delete(packages)
	slice.sort_by(packages, package_name_sort)

	for pkg in packages {
		data_size += 1 + 1 + 3 + 8 + (3 * u64(len(pkg.value.previous)))

		package_name := pkg.key
		for name_part in strings.split_iterator(&package_name, "/") {
			name_len := u8(len(name_part))

			data_size += u64(name_len)
			resize(&data, data_size)

			data[byte_offset] = name_len
			byte_offset += 1

			for i: u64 = 0; i < u64(name_len); i += 1 {
				data[byte_offset + i] = name_part[i]
			}
			byte_offset += u64(name_len)
		}

		version.encode_bytes(data[byte_offset:], pkg.value.newest)
		byte_offset += 3

		previous_versions_count := len(pkg.value.previous)

		endian.put_u64(
			data[byte_offset:byte_offset + 8],
			endian.Byte_Order.Big,
			u64(previous_versions_count),
		)
		byte_offset += 8

		for i := 0; i < previous_versions_count; i += 1 {
			version.encode_bytes(data[byte_offset:], pkg.value.previous[i])
			byte_offset += 3
		}
	}

	return data[:]
}


decode :: proc(data: []u8) -> Registry {
	// The first 8 bytes are the count of total package verseions
	package_versions_count, package_versions_count_ok := endian.get_u64(
		data[:8],
		endian.Byte_Order.Big,
	)
	// The next 8 bytes are the count of total packages
	packages_count, _ := endian.get_u64(data[8:16], endian.Byte_Order.Big)

	packages: map[string]KnownVersions

	byte_offset: u64 = 16

	// Now we gather the package info
	for package_offset := 0; package_offset < int(packages_count); package_offset += 1 {
		// For each package
		// the first byte is the length of the user name
		user_name_length := u64(data[byte_offset])
		byte_offset += 1
		// then we decode that name
		user_name := string(data[byte_offset:byte_offset + user_name_length])
		byte_offset += user_name_length

		// next comes the length of the project name
		project_name_length := u64(data[byte_offset])
		byte_offset += 1
		// which we then decode
		project_name := string(data[byte_offset:byte_offset + project_name_length])
		byte_offset += project_name_length

		// the next 3 bytes are the newest version
		newest_version, next_offset := version.decode_bytes(data, byte_offset)
		byte_offset = next_offset

		// followed by the count of the previous versions
		previous_versions_count, previous_versions_count_ok := endian.get_u64(
			data[byte_offset:byte_offset + 8],
			endian.Byte_Order.Big,
		)
		byte_offset += 8

		previous_versions: [dynamic]version.Version
		reserve(&previous_versions, previous_versions_count)

		// which we then decode
		for versions_decoded: u64 = 0;
		    versions_decoded < previous_versions_count;
		    versions_decoded += 1 {

			prev_version, following_offset := version.decode_bytes(data, byte_offset)
			append(&previous_versions, prev_version)
			byte_offset = following_offset
		}

		// culminating in our KnownVersions
		known_versions := KnownVersions {
			newest   = newest_version,
			previous = previous_versions,
		}

		package_name, package_name_err := strings.join({user_name, project_name}, "/")

		if package_name_err != nil {
			log.error("Error making package name", package_name_err)
		}

		// and finally the full package
		map_insert(&packages, package_name, known_versions)
	}

	return Registry{count = int(package_versions_count), packages = packages}
}


registry_path :: proc(dir: string) -> string {
	return filepath.join({dir, "registry.dat"})
}
