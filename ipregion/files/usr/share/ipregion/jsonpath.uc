// SPDX-License-Identifier: MIT
'use strict';

function get_path(value, path) {
	let current = value;

	for (let i = 0; i < length(path); i++) {
		if (current == null)
			return null;

		current = current[path[i]];
	}

	return current;
}

return { get_path: get_path };
