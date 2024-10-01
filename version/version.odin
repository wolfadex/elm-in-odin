package version


import "core:strconv"
import "core:strings"

Version :: distinct [3]u8

Error :: enum {
	MissingMajor,
	InvalidMajor,
	MissingMinor,
	InvalidMinor,
	MissingPatch,
	InvalidPatch,
	TooLong,
}


parse :: proc(str: string) -> (version: Version, err: Error) {
	parts := strings.split(str, ".")
	defer delete(parts)

	size := len(parts)

	if size > 3 {
		return {}, .TooLong
	} else if size == 3 {
		major, major_ok := strconv.parse_uint(parts[0])

		if !major_ok {
			return {}, .InvalidMajor
		}

		minor, minor_ok := strconv.parse_uint(parts[1])

		if !minor_ok {
			return {}, .InvalidMinor
		}

		patch, patch_ok := strconv.parse_uint(parts[2])

		if !patch_ok {
			return {}, .InvalidPatch
		}

		return {u8(major), u8(minor), u8(patch)}, nil
	} else if size == 2 {
		return {}, .MissingPatch
	} else if size == 1 {
		return {}, .MissingMinor
	}

	return {}, .MissingMajor
}

decode_bytes :: proc(data: []u8, start_offset: u64) -> (version: Version, end_offset: u64) {
	end_offset = start_offset
	major_version := data[end_offset]
	end_offset += 1
	minor_version := data[end_offset]
	end_offset += 1
	patch_version := data[end_offset]

	return {major_version, minor_version, patch_version}, end_offset + 1
}
