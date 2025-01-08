shader_type spatial;

uniform vec3 color;
uniform mat3 length_contract_mat;

void vertex() {
	// Called for every vertex the material is visible on.
	VERTEX = length_contract_mat * VERTEX;
}

void fragment() {
	// Called for every pixel the material is visible on.
	ALBEDO = color;
}

//void light() {
	// Called for every pixel for every light affecting the material.
	// Uncomment to replace the default light processing function with this one.
//}
